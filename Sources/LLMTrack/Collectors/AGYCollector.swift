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

    /// Cached quota older than this triggers a headless refresh (kept well under 15s of
    /// end-to-end staleness once poll interval and ~4s query time are added).
    private static let staleInterval: TimeInterval = 7
    /// Minimum gap between automatic headless attempts, so a failing query can't
    /// respawn the language server on every poll.
    private static let headlessRetryInterval: TimeInterval = 10

    private static let languageServerPath = "/Applications/Antigravity.app/Contents/Resources/bin/language_server"
    private static let quotaPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"

    public init() {}

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

        // 3. Resolve quota: disk/memory cache, refreshed via a headless language_server
        // (CLI account). Forced refreshes block; stale-cache refreshes run in the background
        // so the regular poll stays fast, unless there is no cache at all to show.
        var record = loadDiskCache()

        if allowHeadless {
            if forceLive {
                if let fresh = refreshHeadlessSync() { record = fresh }
            } else {
                let isStale = record.map { Date().timeIntervalSince($0.updatedAt) > Self.staleInterval } ?? true
                if isStale && claimBackgroundRefresh() {
                    if record == nil {
                        if let fresh = refreshHeadlessSync() { record = fresh }
                        releaseBackgroundRefresh()
                    } else {
                        DispatchQueue.global(qos: .utility).async { [self] in
                            _ = refreshHeadlessSync()
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

    // MARK: - Headless refresh coordination

    /// Atomically decides whether an automatic refresh may start now (single-flight + retry throttle).
    private func claimBackgroundRefresh() -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard !Self.backgroundRefreshInFlight else { return false }
        if let last = Self.lastHeadlessAttempt,
           Date().timeIntervalSince(last) < Self.headlessRetryInterval {
            return false
        }
        Self.backgroundRefreshInFlight = true
        Self.lastHeadlessAttempt = Date()
        return true
    }

    private func releaseBackgroundRefresh() {
        Self.lock.lock()
        Self.backgroundRefreshInFlight = false
        Self.lock.unlock()
    }

    /// Runs the headless query (blocking) and persists the result on success.
    private func refreshHeadlessSync() -> AGYQuotaCacheRecord? {
        Self.headlessGate.lock()
        defer { Self.headlessGate.unlock() }

        Self.lock.lock()
        Self.lastHeadlessAttempt = Date()
        Self.lock.unlock()

        guard let fresh = spawnHeadlessQuotaQuery() else { return nil }
        saveDiskCache(fresh)
        return fresh
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
        guard let raw = raw, !raw.isEmpty else { return nil }
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
