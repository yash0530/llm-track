import Foundation
import Darwin

/// Persisted snapshot of the last quota response. Stores absolute reset timestamps
/// (not formatted strings) so countdowns can be recomputed at any later time.
public struct AGYQuotaCacheRecord: Codable, Sendable, Equatable {
    public var geminiWeeklyRemainingFraction: Double
    public var geminiWeeklyResetIso: String?
    public var geminiFiveHourRemainingFraction: Double
    public var geminiFiveHourResetIso: String?
    public var claudeGptWeeklyRemainingFraction: Double
    public var claudeGptFiveHourRemainingFraction: Double
    public var updatedAt: Date

    public init(
        geminiWeeklyRemainingFraction: Double = 0.0,
        geminiWeeklyResetIso: String? = nil,
        geminiFiveHourRemainingFraction: Double = 0.0,
        geminiFiveHourResetIso: String? = nil,
        claudeGptWeeklyRemainingFraction: Double = 1.0,
        claudeGptFiveHourRemainingFraction: Double = 1.0,
        updatedAt: Date = Date()
    ) {
        self.geminiWeeklyRemainingFraction = geminiWeeklyRemainingFraction
        self.geminiWeeklyResetIso = geminiWeeklyResetIso
        self.geminiFiveHourRemainingFraction = geminiFiveHourRemainingFraction
        self.geminiFiveHourResetIso = geminiFiveHourResetIso
        self.claudeGptWeeklyRemainingFraction = claudeGptWeeklyRemainingFraction
        self.claudeGptFiveHourRemainingFraction = claudeGptFiveHourRemainingFraction
        self.updatedAt = updatedAt
    }
}

public final class AGYCollector: @unchecked Sendable {
    private static var cachedRecord: AGYQuotaCacheRecord? = nil
    private static var lastHeadlessAttempt: Date? = nil
    private static var backgroundRefreshInFlight = false
    private static let lock = NSLock()
    /// Serializes spawns so a forced refresh and a background refresh never run two servers at once.
    private static let headlessGate = NSLock()

    /// Cached quota older than this triggers a background refresh. The direct API path costs
    /// a couple of small HTTPS calls, so this is effectively "every poll".
    private static let staleInterval: TimeInterval = 3
    /// Minimum gap between headless `language_server` fallback spawns (the expensive path),
    /// used only when the direct API path is unavailable (e.g. expired token).
    private static let headlessRetryInterval: TimeInterval = 60

    private static let cloudCodeBase = "https://daily-cloudcode-pa.googleapis.com/v1internal:"
    private static var cachedProjectId: String? = nil
    private static let apiSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }()

    private static let languageServerPath = "/Applications/Antigravity.app/Contents/Resources/bin/language_server"
    private static let quotaPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"

    public init() {
        _ = Self.reapOrphansOnce
    }

    /// Runs once per process.
    private static let reapOrphansOnce: Void = {
        reapOrphanedHeadlessServers()
    }()

    /// Kills headless servers we spawned in a previous app run that never got terminated
    /// (the app was killed mid-query so its `defer` cleanup never ran).
    private static func reapOrphanedHeadlessServers() {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-A", "-o", "pid=,etime=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return }

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  parts[2].hasPrefix(languageServerPath + " "),
                  parts[2].contains("--standalone"),
                  parts[2].contains("--headless"),
                  elapsedSeconds(String(parts[1])) > 20 else { continue }
            kill(pid, SIGTERM)
        }
    }

    /// Parses `ps` etime: [[dd-]hh:]mm:ss
    private static func elapsedSeconds(_ etime: String) -> Int {
        var days = 0
        var rest = etime
        if let dash = etime.firstIndex(of: "-") {
            days = Int(etime[..<dash]) ?? 0
            rest = String(etime[etime.index(after: dash)...])
        }
        let nums = rest.split(separator: ":").compactMap { Int($0) }
        var seconds = 0
        for n in nums { seconds = seconds * 60 + n }
        return days * 86400 + seconds
    }

    private static var cacheFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("llm-track", isDirectory: true)
            .appendingPathComponent("agy_quota_cache.json")
    }

    /// - Parameters:
    ///   - forceLive: user-initiated refresh; permits a headless query even if the cache is fresh.
    ///   - allowHeadless: set false for callers on the main thread that must not block (e.g. startup).
    public func collect(forceLive: Bool = false, allowHeadless: Bool = true) -> AGYStatus {
        var status = AGYStatus()

        // 1. Process matching — the agy CLI only. The Antigravity IDE runs under a different
        // account, so its processes/language_server must not influence status or quota.
        let matches = ProcessHelper.findProcesses(matching: ["agy "])
        let cliProcess = matches.first { $0.command.hasPrefix("agy ") || $0.command.contains("/agy ") }

        if let proc = cliProcess {
            status.process = AgentProcessInfo(
                isRunning: true,
                pid: proc.pid,
                cpuPercent: proc.cpuPercent,
                command: proc.command
            )

            // Parse model argument if present
            if let modelRange = proc.command.range(of: "--model ") {
                let after = proc.command[modelRange.upperBound...]
                let modelName = after.components(separatedBy: " ").first ?? ""
                if !modelName.isEmpty {
                    status.model = formatModelName(modelName)
                }
            }

            // Parse add-dir or project argument
            if let dirRange = proc.command.range(of: "--add-dir ") {
                let after = proc.command[dirRange.upperBound...]
                let dirPath = after.components(separatedBy: " ").first ?? ""
                status.activeDirectory = URL(fileURLWithPath: dirPath).lastPathComponent
            }
        } else {
            status.process = AgentProcessInfo(isRunning: false)
        }

        // 2. Extract plan tier from global storage if available
        if let tier = detectTierFromGlobalStorage() {
            status.planTier = tier
        } else {
            status.planTier = "Google AI Pro"
        }

        // 3. Resolve quota: disk/memory cache, refreshed via the direct Cloud Code API (CLI
        // account) with a headless language_server fallback. Forced refreshes block;
        // stale-cache refreshes run in the background so the regular poll stays fast,
        // unless there is no cache at all to show.
        var record = loadDiskCache()

        if allowHeadless {
            if forceLive {
                if let fresh = refreshQuotaSync(force: true) { record = fresh }
            } else {
                let isStale = record.map { Date().timeIntervalSince($0.updatedAt) > Self.staleInterval } ?? true
                if isStale && claimBackgroundRefresh() {
                    if record == nil {
                        if let fresh = refreshQuotaSync(force: false) { record = fresh }
                        releaseBackgroundRefresh()
                    } else {
                        DispatchQueue.global(qos: .utility).async { [self] in
                            _ = refreshQuotaSync(force: false)
                            releaseBackgroundRefresh()
                        }
                    }
                }
            }
        }

        if let record = record {
            Self.apply(record, to: &status)
        }

        return status
    }

    // MARK: - Refresh coordination

    /// Atomically allows only one automatic refresh in flight at a time.
    private func claimBackgroundRefresh() -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard !Self.backgroundRefreshInFlight else { return false }
        Self.backgroundRefreshInFlight = true
        return true
    }

    private func releaseBackgroundRefresh() {
        Self.lock.lock()
        Self.backgroundRefreshInFlight = false
        Self.lock.unlock()
    }

    /// Fetches quota (blocking) and persists it on success. Tries the cheap direct API first;
    /// falls back to spawning the headless language_server (throttled unless `force`).
    private func refreshQuotaSync(force: Bool) -> AGYQuotaCacheRecord? {
        Self.headlessGate.lock()
        defer { Self.headlessGate.unlock() }

        if let fresh = fetchDirectQuota() {
            saveDiskCache(fresh)
            return fresh
        }

        Self.lock.lock()
        let last = Self.lastHeadlessAttempt
        Self.lock.unlock()
        if !force, let last = last, Date().timeIntervalSince(last) < Self.headlessRetryInterval {
            return nil
        }

        Self.lock.lock()
        Self.lastHeadlessAttempt = Date()
        Self.lock.unlock()

        guard let fresh = spawnHeadlessQuotaQuery() else { return nil }
        saveDiskCache(fresh)
        return fresh
    }

    // MARK: - Direct Cloud Code API

    private final class HTTPResult: @unchecked Sendable {
        var status = 0
        var json: [String: Any]?
    }

    private static var tokenFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/antigravity-oauth-token")
    }

    /// Reads the agy CLI's OAuth access token (read-only). Returns nil if missing or about to expire;
    /// the CLI itself is responsible for refreshing it.
    private func readAccessToken() -> String? {
        guard let data = try? Data(contentsOf: Self.tokenFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? [String: Any],
              let access = token["access_token"] as? String, !access.isEmpty else { return nil }
        if let expiry = token["expiry"] as? String,
           let date = Self.parseISO(expiry),
           date.timeIntervalSinceNow < 60 {
            return nil
        }
        return access
    }

    private func postJSON(method: String, body: [String: Any], token: String) -> HTTPResult? {
        guard let url = URL(string: Self.cloudCodeBase + method),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("antigravity/2.26.0 darwin/arm64", forHTTPHeaderField: "User-Agent")

        let result = HTTPResult()
        let done = DispatchSemaphore(value: 0)
        Self.apiSession.dataTask(with: request) { data, response, error in
            if error == nil, let http = response as? HTTPURLResponse {
                result.status = http.statusCode
                if let data = data {
                    result.json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                }
            }
            done.signal()
        }.resume()
        done.wait()
        return result.status == 0 ? nil : result
    }

    private func loadProjectId(token: String) -> String? {
        Self.lock.lock()
        let cached = Self.cachedProjectId
        Self.lock.unlock()
        if let cached = cached { return cached }

        let body: [String: Any] = ["metadata": ["ideType": "ANTIGRAVITY", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]]
        guard let result = postJSON(method: "loadCodeAssist", body: body, token: token),
              result.status == 200,
              let project = result.json?["cloudaicompanionProject"] as? String, !project.isEmpty else { return nil }

        Self.lock.lock()
        Self.cachedProjectId = project
        Self.lock.unlock()
        return project
    }

    /// Two small HTTPS calls, no subprocess. Returns nil on any failure so the caller can fall back.
    private func fetchDirectQuota() -> AGYQuotaCacheRecord? {
        guard let token = readAccessToken(),
              let project = loadProjectId(token: token) else { return nil }

        guard let result = postJSON(method: "retrieveUserQuotaSummary", body: ["project": project], token: token) else {
            return nil
        }
        if result.status == 200, let groups = result.json?["groups"] as? [[String: Any]] {
            return parseQuotaGroups(groups)
        }
        if result.status == 400 || result.status == 403 || result.status == 404 {
            // Project may be stale; re-resolve next time.
            Self.lock.lock()
            Self.cachedProjectId = nil
            Self.lock.unlock()
        }
        return nil
    }

    // MARK: - Disk cache

    /// Persists the record to `~/.config/llm-track/agy_quota_cache.json` and updates the in-memory copy.
    private func saveDiskCache(_ record: AGYQuotaCacheRecord) {
        Self.lock.lock()
        Self.cachedRecord = record
        Self.lock.unlock()

        let url = Self.cacheFileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(to: url, options: .atomic)
        } catch {
            // Cache is best-effort; the in-memory copy still works for this session.
        }
    }

    /// Returns the freshest of the in-memory and on-disk records.
    private func loadDiskCache() -> AGYQuotaCacheRecord? {
        Self.lock.lock()
        let memory = Self.cachedRecord
        Self.lock.unlock()

        var disk: AGYQuotaCacheRecord? = nil
        if let data = try? Data(contentsOf: Self.cacheFileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            disk = try? decoder.decode(AGYQuotaCacheRecord.self, from: data)
        }

        switch (memory, disk) {
        case let (m?, d?): return m.updatedAt >= d.updatedAt ? m : d
        case let (m?, nil): return m
        case let (nil, d?):
            Self.lock.lock()
            Self.cachedRecord = d
            Self.lock.unlock()
            return d
        default: return nil
        }
    }

    // MARK: - Record -> status

    /// Converts a record into display values, recomputing countdowns against the current time.
    /// Windows whose reset time has passed are treated as replenished (100%).
    static func apply(_ record: AGYQuotaCacheRecord, to status: inout AGYStatus, now: Date = Date()) {
        let weeklyReset = parseISO(record.geminiWeeklyResetIso)
        let fiveHourReset = parseISO(record.geminiFiveHourResetIso)

        if let reset = weeklyReset, reset <= now {
            status.geminiWeeklyRemainingPct = 100.0
            status.geminiWeeklyResetString = "Quota refreshed"
            status.geminiWeeklyResetsAt = nil
        } else {
            status.geminiWeeklyRemainingPct = clampPct(record.geminiWeeklyRemainingFraction)
            status.geminiWeeklyResetsAt = weeklyReset
            status.geminiWeeklyResetString = weeklyReset.map { ClaudeStatus.formatRelativeCountdown($0) } ?? "Reset time unknown"
        }

        if let reset = fiveHourReset, reset <= now {
            status.geminiFiveHourRemainingPct = 100.0
            status.geminiFiveHourResetString = "Quota refreshed"
            status.geminiFiveHourResetsAt = nil
        } else {
            status.geminiFiveHourRemainingPct = clampPct(record.geminiFiveHourRemainingFraction)
            status.geminiFiveHourResetsAt = fiveHourReset
            status.geminiFiveHourResetString = fiveHourReset.map { ClaudeStatus.formatRelativeCountdown($0) } ?? "Reset time unknown"
        }

        status.claudeGptWeeklyRemainingPct = clampPct(record.claudeGptWeeklyRemainingFraction)
        status.claudeGptFiveHourRemainingPct = clampPct(record.claudeGptFiveHourRemainingFraction)
    }

    private static func clampPct(_ fraction: Double) -> Double {
        max(0.0, min(100.0, fraction * 100.0))
    }

    private static func parseISO(_ raw: String?) -> Date? {
        guard var raw = raw, !raw.isEmpty else { return nil }
        // Trim fractional seconds to at most 3 digits (e.g. ".249038" -> ".249").
        if let range = raw.range(of: #"\.\d{4,}"#, options: .regularExpression) {
            raw.replaceSubrange(range, with: String(raw[range].prefix(4)))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    // MARK: - Headless query

    /// Launches Antigravity's bundled `language_server` standalone (no IDE UI), fetches the quota
    /// summary, then terminates it. Blocking: ~2.5s typical, 3.5s max for the poll loop.
    private func spawnHeadlessQuotaQuery() -> AGYQuotaCacheRecord? {
        guard FileManager.default.isExecutableFile(atPath: Self.languageServerPath),
              let port = Self.findFreePort() else { return nil }

        let csrf = UUID().uuidString.lowercased()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.languageServerPath)
        process.arguments = [
            "--standalone",
            "--headless",
            "--override_ide_name", "antigravity",
            "--subclient_type", "hub",
            "--override_ide_version", "2.26.0",
            "--override_user_agent_name", "antigravity",
            "--https_server_port", String(port),
            "--csrf_token", csrf,
            "--app_data_dir", "antigravity",
            "--api_server_url", "https://generativelanguage.googleapis.com",
            "--cloud_code_endpoint", "https://daily-cloudcode-pa.googleapis.com"
        ]
        // /dev/null avoids pipe-buffer hangs from a chatty child nobody is reading.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        defer {
            process.terminate()
            // Escalate if SIGTERM is ignored so we never leak a 160MB background process.
            let deadline = Date().addingTimeInterval(1.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        let deadline = Date().addingTimeInterval(3.5)
        while Date() < deadline {
            guard process.isRunning else { return nil }
            if let record = queryQuota(port: String(port), csrf: csrf) {
                return record
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    /// Asks the kernel for a free ephemeral loopback port by binding to port 0.
    private static func findFreePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    /// POSTs RetrieveUserQuotaSummary to a language_server instance. Returns nil on any failure.
    private func queryQuota(port: String, csrf: String) -> AGYQuotaCacheRecord? {
        let curlProcess = Process()
        curlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curlProcess.arguments = [
            "-k", "-s", "-m", "2", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-H", "x-codeium-csrf-token: \(csrf)",
            "-d", "{}",
            "https://127.0.0.1:\(port)\(Self.quotaPath)"
        ]
        let curlPipe = Pipe()
        curlProcess.standardOutput = curlPipe
        curlProcess.standardError = FileHandle.nullDevice

        do {
            try curlProcess.run()
        } catch {
            return nil
        }
        let data = curlPipe.fileHandleForReading.readDataToEndOfFile()
        curlProcess.waitUntilExit()

        guard curlProcess.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseObj = json["response"] as? [String: Any],
              let groups = responseObj["groups"] as? [[String: Any]] else {
            return nil
        }
        return parseQuotaGroups(groups)
    }

    private func parseQuotaGroups(_ groups: [[String: Any]]) -> AGYQuotaCacheRecord {
        var record = AGYQuotaCacheRecord(updatedAt: Date())

        for group in groups {
            let groupName = (group["displayName"] as? String) ?? ""
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }

            let isGemini = groupName.localizedCaseInsensitiveContains("gemini")
            let isThirdParty = groupName.localizedCaseInsensitiveContains("claude") || groupName.localizedCaseInsensitiveContains("gpt")
            guard isGemini || isThirdParty else { continue }

            for bucket in buckets {
                let bucketId = (bucket["bucketId"] as? String) ?? ""
                let window = (bucket["window"] as? String) ?? ""
                let resetTimeStr = bucket["resetTime"] as? String
                // Proto3 JSON omits zero-valued fields: a bucket that has a reset time but no
                // remainingFraction is exhausted (0), not full.
                let fraction = (bucket["remainingFraction"] as? NSNumber)?.doubleValue
                    ?? (resetTimeStr == nil ? 1.0 : 0.0)

                let isFiveHour = bucketId.contains("5h") || window == "5h"
                let isWeekly = bucketId.contains("weekly") || window == "weekly"

                if isGemini {
                    if isFiveHour {
                        record.geminiFiveHourRemainingFraction = fraction
                        record.geminiFiveHourResetIso = resetTimeStr
                    } else if isWeekly {
                        record.geminiWeeklyRemainingFraction = fraction
                        record.geminiWeeklyResetIso = resetTimeStr
                    }
                } else {
                    if isFiveHour {
                        record.claudeGptFiveHourRemainingFraction = fraction
                    } else if isWeekly {
                        record.claudeGptWeeklyRemainingFraction = fraction
                    }
                }
            }
        }

        return record
    }

    private func detectTierFromGlobalStorage() -> String? {
        let dbPath = ("~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus';"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let base64Str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let rawData = Data(base64Encoded: base64Str),
                  let text = String(data: rawData, encoding: .ascii) else {
                return nil
            }

            if text.contains("g1-pro-tier") || text.contains("Google AI Pro") {
                return "Google AI Pro"
            } else if text.contains("Google AI Ultra") {
                return "Google AI Ultra"
            }
            return nil
        } catch {
            return nil
        }
    }

    private func formatModelName(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("flash") {
            return "Gemini 3.8 Flash High"
        } else if raw.localizedCaseInsensitiveContains("pro") {
            return "Gemini 3.5 Pro"
        } else {
            return raw
        }
    }
}
