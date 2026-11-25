import Foundation

public final class ClaudeCollector: @unchecked Sendable {
    private struct ClaudeDiskCache: Codable {
        let fiveHourUsedPct: Double?
        let fiveHourRemainingPct: Double?
        let fiveHourResetsAt: Date?
        let sevenDayUsedPct: Double?
        let sevenDayRemainingPct: Double?
        let sevenDayResetsAt: Date?
        let remainingDollars: Double?
        let updatedAt: Date
    }

    private static var lastLiveFetchTime: Date = .distantPast
    private static var rateLimitBackoffUntil: Date = .distantPast
    private static var cachedLiveUsage: [String: Any]? = nil
    private static var cachedLiveUsageDate: Date = .distantPast
    private static var lastFailureReason: String? = nil
    private static var lastFetchWasAuthFailure = false
    private static var lastCLIRefreshAttempt: Date = .distantPast
    /// At most one `claude -p /usage` token refresh per 10 minutes.
    private static let cliRefreshMinGap: TimeInterval = 600
    private static let lock = NSLock()

    /// The usage endpoint 429s with Retry-After: 300 after a handful of calls, so poll gently.
    private static let livePollInterval: TimeInterval = 180
    private static let forcedMinGap: TimeInterval = 20

    private static var cacheFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("llm-track", isDirectory: true)
            .appendingPathComponent("claude_quota_cache.json")
    }

    public init() {}

    public func collect(forceLive: Bool = false) -> ClaudeStatus {
        var status = ClaudeStatus()

        // 1. Process telemetry
        let matches = ProcessHelper.findProcesses(matching: ["claude ", "/claude", "claude-code"])
        let primaryProcess = matches.first { m in
            let cmd = m.command.lowercased()
            return cmd.hasPrefix("claude ") || cmd.hasPrefix("claude") || cmd.contains("/claude ") || cmd.hasSuffix("/claude")
        } ?? matches.first

        if let proc = primaryProcess {
            status.process = AgentProcessInfo(
                isRunning: true,
                pid: proc.pid,
                cpuPercent: proc.cpuPercent,
                command: proc.command
            )
        } else {
            status.process = AgentProcessInfo(isRunning: false)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser

        // 2. Parse model accurately from settings.json or statusline
        status.model = detectModel(home: home)

        let statuslineURL = home.appendingPathComponent(".claude/statusline_state.json")
        var statuslineData: [String: Any]? = nil
        var statuslineModDate: Date = .distantPast

        if let values = try? statuslineURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modDate = values.contentModificationDate {
            statuslineModDate = modDate
        }

        if let slData = try? Data(contentsOf: statuslineURL),
           let slJson = try? JSONSerialization.jsonObject(with: slData) as? [String: Any] {
            statuslineData = slJson
            if let modelObj = slJson["model"] as? [String: Any],
               let name = modelObj["display_name"] as? String, !name.isEmpty {
                status.model = formatModelName(name)
            }
        }

        // 3. Quota resolution: live OAuth usage, falling back to the last good response.
        //    Every value shown carries `dataAsOf` so the UI can tell live from stale.
        var appliedLiveQuota = false
        var dataAsOf: Date? = nil
        let now = Date()

        var creds = fetchKeychainCredentials()
        let tokenExpired = creds?.expiresAt.map { $0 <= now } ?? false
        Self.lock.lock()
        let wantsRefresh = (tokenExpired || Self.lastFetchWasAuthFailure)
            && now.timeIntervalSince(Self.lastCLIRefreshAttempt) >= Self.cliRefreshMinGap
        if wantsRefresh { Self.lastCLIRefreshAttempt = now }
        Self.lock.unlock()
        if wantsRefresh, refreshTokenViaCLI() {
            // The CLI rewrote the keychain entry; re-read it and fetch right away.
            creds = fetchKeychainCredentials()
            Self.lock.lock()
            Self.lastFetchWasAuthFailure = false
            Self.rateLimitBackoffUntil = .distantPast
            Self.lastLiveFetchTime = .distantPast
            Self.lock.unlock()
        }

        if let creds = creds {
            if let exp = creds.expiresAt, exp <= now {
                // The CLI refreshes this token only when `claude` runs; calling with it just 401s.
                Self.lock.lock()
                Self.lastFailureReason = "Token expired"
                Self.lock.unlock()
            } else {
                var shouldFetch = false
                Self.lock.lock()
                if now >= Self.rateLimitBackoffUntil {
                    let minGap = forceLive ? Self.forcedMinGap : Self.livePollInterval
                    if now.timeIntervalSince(Self.lastLiveFetchTime) >= minGap {
                        shouldFetch = true
                        Self.lastLiveFetchTime = now
                    }
                }
                Self.lock.unlock()

                if shouldFetch {
                    let fetchResult = fetchLiveOAuthUsage(token: creds.accessToken)
                    Self.lock.lock()
                    if let liveUsage = fetchResult.json {
                        Self.cachedLiveUsage = liveUsage
                        Self.cachedLiveUsageDate = Date()
                        Self.rateLimitBackoffUntil = .distantPast
                        Self.lastFailureReason = nil
                        Self.lastFetchWasAuthFailure = false
                    } else {
                        switch fetchResult.statusCode {
                        case 429:
                            Self.lastFailureReason = "Rate limited"
                            Self.rateLimitBackoffUntil = Date().addingTimeInterval(max(60.0, fetchResult.retryAfter ?? 300.0))
                        case 401, 403:
                            Self.lastFailureReason = "Auth failed"
                            Self.lastFetchWasAuthFailure = true
                            Self.rateLimitBackoffUntil = Date().addingTimeInterval(120.0)
                        case 0:
                            Self.lastFailureReason = "Offline"
                            Self.rateLimitBackoffUntil = Date().addingTimeInterval(30.0)
                        default:
                            Self.lastFailureReason = "HTTP \(fetchResult.statusCode)"
                            Self.rateLimitBackoffUntil = Date().addingTimeInterval(60.0)
                        }
                    }
                    Self.lock.unlock()
                }
            }
        } else {
            Self.lock.lock()
            Self.lastFailureReason = "No Claude login"
            Self.lock.unlock()
        }

        Self.lock.lock()
        let cached = Self.cachedLiveUsage
        let cachedDate = Self.cachedLiveUsageDate
        let failureReason = Self.lastFailureReason
        Self.lock.unlock()

        if let cached = cached {
            applyLiveUsageJson(cached, to: &status)
            dataAsOf = cachedDate
            appliedLiveQuota = true
            if failureReason == nil, now.timeIntervalSince(cachedDate) < 1 {
                saveDiskCache(status: status, asOf: cachedDate)
            }
        } else if let disk = loadDiskCache() {
            applyDiskCache(disk, to: &status)
            dataAsOf = disk.updatedAt
            appliedLiveQuota = true
        }

        // 4. Fallback to local files ONLY if no live/cached OAuth quota could be resolved
        if !appliedLiveQuota {
            // Check statusline rate limits if the file is fresh (< 30 minutes old)
            if now.timeIntervalSince(statuslineModDate) < 1800,
               let slJson = statuslineData,
               let rateLimits = slJson["rate_limits"] as? [String: Any] {
                applyStatuslineRateLimits(rateLimits, to: &status)
                dataAsOf = statuslineModDate
            }

            // Fallback to ~/.claude.json cachedUsageUtilization, but only if it is recent:
            // it can be weeks old and would otherwise show a long-gone window as live.
            if status.fiveHourRemainingPct == nil {
                let claudeConfigURL = home.appendingPathComponent(".claude.json")
                if let configData = try? Data(contentsOf: claudeConfigURL),
                   let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
                   let cachedUsage = configJson["cachedUsageUtilization"] as? [String: Any],
                   let fetchedAtMs = (cachedUsage["fetchedAtMs"] as? NSNumber)?.doubleValue,
                   let utilization = cachedUsage["utilization"] as? [String: Any] {
                    let fetchedAt = Date(timeIntervalSince1970: fetchedAtMs / 1000.0)
                    if now.timeIntervalSince(fetchedAt) < 1800 {
                        applyLiveUsageJson(utilization, to: &status)
                        dataAsOf = fetchedAt
                    }
                }
            }
        }

        status.dataAsOf = dataAsOf
        status.fetchError = failureReason

        // 5. Check recent assistant turn in transcripts for active rate limit block
        if let info = detectExhaustionFromRecentTurn(home: home) {
            status.fiveHourUsedPct = 100.0
            status.fiveHourRemainingPct = 0.0
            if let resetsAt = info.resetsAt {
                status.fiveHourResetsAt = resetsAt
                status.resetTimeString = ClaudeStatus.formatRelativeCountdown(resetsAt)
            } else if let existing = status.fiveHourResetsAt {
                status.resetTimeString = ClaudeStatus.formatRelativeCountdown(existing)
            } else {
                status.resetTimeString = info.resetText
            }
        }

        // 6. Reset handling. A window's usage is unknown (never "100% left") when:
        //    - its reset time passed and our data predates the reset, or
        //    - the API gave no reset time (window not started yet) and the data is stale:
        //      any usage since then started a new window we know nothing about, or
        //    - the data is older than the window itself.
        let asOf = status.dataAsOf ?? .distantPast
        let age = now.timeIntervalSince(asOf)
        let isStale = age > ClaudeStatus.staleAfter
        func windowUnknown(resetsAt: Date?, length: TimeInterval) -> Bool {
            if age > length { return true }
            if let r = resetsAt { return r <= now && asOf < r }
            return isStale
        }
        if windowUnknown(resetsAt: status.fiveHourResetsAt, length: 5 * 3600) {
            status.fiveHourUsedPct = nil
            status.fiveHourRemainingPct = nil
        }
        if let resetsAt = status.fiveHourResetsAt, resetsAt <= now {
            status.fiveHourResetsAt = nil
            status.resetTimeString = "Window reset"
        } else if let resetsAt = status.fiveHourResetsAt {
            status.resetTimeString = ClaudeStatus.formatRelativeCountdown(resetsAt)
        } else if status.fiveHourRemainingPct == nil {
            status.resetTimeString = nil
        }
        if windowUnknown(resetsAt: status.sevenDayResetsAt, length: 7 * 86400) {
            status.sevenDayUsedPct = nil
            status.sevenDayRemainingPct = nil
        }
        if let resetsAt = status.sevenDayResetsAt, resetsAt <= now {
            status.sevenDayResetsAt = nil
            status.sevenDayResetsInString = "Window reset"
        } else if let resetsAt = status.sevenDayResetsAt {
            status.sevenDayResetsInString = ClaudeStatus.formatRelativeCountdown(resetsAt)
        }

        status.lastUpdated = Date()
        return status
    }

    private func detectModel(home: URL) -> String {
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let modelSettings = json["modelSettings"] as? [String: Any] {
                if modelSettings["claude-opus-5-5"] != nil {
                    return "Opus 5.5"
                }
                for key in modelSettings.keys {
                    if key.contains("opus") { return "Opus 5.5" }
                    if key.contains("sonnet") { return "Sonnet 4.5" }
                }
            }
            if let m = json["model"] as? String {
                if m.localizedCaseInsensitiveContains("opus") {
                    return "Opus 5.5"
                } else if m.localizedCaseInsensitiveContains("sonnet") {
                    return "Sonnet 4.5"
                }
            }
        }
        return "Opus 5.5"
    }

    private struct ExhaustionResult {
        let resetText: String
        let resetsAt: Date?
    }

    private func detectExhaustionFromRecentTurn(home: URL) -> ExhaustionResult? {
        let projectsURL = home.appendingPathComponent(".claude/projects")
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: nil) else {
            return nil
        }

        var allJsonlFiles: [URL] = []
        for dir in projectDirs {
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                allJsonlFiles.append(contentsOf: files.filter { $0.pathExtension == "jsonl" })
            }
        }

        guard !allJsonlFiles.isEmpty else { return nil }

        let sorted = allJsonlFiles.sorted { u1, u2 in
            let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 > d2
        }

        guard let latestFile = sorted.first else { return nil }

        let fileModDate = (try? latestFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        guard Date().timeIntervalSince(fileModDate) < 5 * 3600 else { return nil }

        guard let fileHandle = try? FileHandle(forReadingFrom: latestFile) else { return nil }
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        let readLength = min(fileSize, 131072) // Read up to 128KB tail
        fileHandle.seek(toFileOffset: fileSize - readLength)
        let data = fileHandle.readDataToEndOfFile()

        guard let tailText = String(data: data, encoding: .utf8) else { return nil }
        let lines = tailText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Find the newest assistant turn, scanning through recent user or queue-operation items
        for line in lines.reversed().prefix(200) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String
            if type == "assistant" {
                let isApiError = (json["isApiErrorMessage"] as? Bool) ?? false
                let err = json["error"] as? String
                let status = json["apiErrorStatus"] as? Int
                let apiError = json["apiError"] as? String

                if isApiError || err == "rate_limit" || status == 429 || apiError == "usage_limit_reached" {
                    var resetsAtDate: Date? = nil

                    if let quotaLimits = json["quotaLimits"] as? [String: Any] {
                        if let num = (quotaLimits["resetsAt"] as? NSNumber)?.doubleValue ?? (quotaLimits["resets_at"] as? NSNumber)?.doubleValue {
                            resetsAtDate = Date(timeIntervalSince1970: num)
                        } else if let str = (quotaLimits["resetsAt"] as? String) ?? (quotaLimits["resets_at"] as? String) {
                            resetsAtDate = parseISO8601(str)
                        }
                    }

                    if resetsAtDate == nil, let apiParams = json["apiErrorParams"] as? [String: Any],
                       let rateLimitInfo = apiParams["rate_limit_info"] as? [String: Any] {
                        if let num = (rateLimitInfo["resetsAt"] as? NSNumber)?.doubleValue ?? (rateLimitInfo["resets_at"] as? NSNumber)?.doubleValue {
                            resetsAtDate = Date(timeIntervalSince1970: num)
                        } else if let str = (rateLimitInfo["resetsAt"] as? String) ?? (rateLimitInfo["resets_at"] as? String) {
                            resetsAtDate = parseISO8601(str)
                        }
                    }

                    if let resetsAt = resetsAtDate, resetsAt.timeIntervalSince(Date()) <= 0 {
                        return nil
                    }

                    return ExhaustionResult(resetText: "Resets soon", resetsAt: resetsAtDate)
                }

                // If newest assistant response was normal, session was working
                return nil
            }
        }

        return nil
    }

    private func applyStatuslineRateLimits(_ rateLimits: [String: Any], to status: inout ClaudeStatus) {
        if let fiveHour = rateLimits["five_hour"] as? [String: Any] {
            if let usedPct = (fiveHour["used_percentage"] as? NSNumber)?.doubleValue {
                status.fiveHourUsedPct = usedPct
                status.fiveHourRemainingPct = max(0, 100.0 - usedPct)
            }
            if let resetsAtNum = (fiveHour["resets_at"] as? NSNumber)?.doubleValue {
                let date = Date(timeIntervalSince1970: resetsAtNum)
                status.fiveHourResetsAt = date
                status.resetTimeString = ClaudeStatus.formatRelativeCountdown(date)
            } else if let resetsAtStr = fiveHour["resets_at"] as? String,
                      let date = parseISO8601(resetsAtStr) {
                status.fiveHourResetsAt = date
                status.resetTimeString = ClaudeStatus.formatRelativeCountdown(date)
            }
        }

        if let sevenDay = rateLimits["seven_day"] as? [String: Any] {
            if let usedPct = (sevenDay["used_percentage"] as? NSNumber)?.doubleValue {
                status.sevenDayUsedPct = usedPct
                status.sevenDayRemainingPct = max(0, 100.0 - usedPct)
            }
            if let resetsAtNum = (sevenDay["resets_at"] as? NSNumber)?.doubleValue {
                let date = Date(timeIntervalSince1970: resetsAtNum)
                status.sevenDayResetsAt = date
                status.sevenDayResetsInString = ClaudeStatus.formatRelativeCountdown(date)
            } else if let resetsAtStr = sevenDay["resets_at"] as? String,
                      let date = parseISO8601(resetsAtStr) {
                status.sevenDayResetsAt = date
                status.sevenDayResetsInString = ClaudeStatus.formatRelativeCountdown(date)
            }
        }
    }

    private func saveDiskCache(status: ClaudeStatus, asOf: Date) {
        let url = Self.cacheFileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let record = ClaudeDiskCache(
            fiveHourUsedPct: status.fiveHourUsedPct,
            fiveHourRemainingPct: status.fiveHourRemainingPct,
            fiveHourResetsAt: status.fiveHourResetsAt,
            sevenDayUsedPct: status.sevenDayUsedPct,
            sevenDayRemainingPct: status.sevenDayRemainingPct,
            sevenDayResetsAt: status.sevenDayResetsAt,
            remainingDollars: status.remainingDollars,
            updatedAt: asOf
        )
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadDiskCache() -> ClaudeDiskCache? {
        let url = Self.cacheFileURL
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ClaudeDiskCache.self, from: data) else {
            return nil
        }
        return cache
    }

    private func applyDiskCache(_ cache: ClaudeDiskCache, to status: inout ClaudeStatus) {
        status.fiveHourUsedPct = cache.fiveHourUsedPct
        status.fiveHourRemainingPct = cache.fiveHourRemainingPct
        status.fiveHourResetsAt = cache.fiveHourResetsAt
        status.sevenDayUsedPct = cache.sevenDayUsedPct
        status.sevenDayRemainingPct = cache.sevenDayRemainingPct
        status.sevenDayResetsAt = cache.sevenDayResetsAt
        status.remainingDollars = cache.remainingDollars
        // Reset/countdown handling happens once, in collect() step 6, using updatedAt.
    }

    private func formatModelName(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("qwen") {
            return "Opus 5.5"
        }
        if raw.localizedCaseInsensitiveContains("opus-5-5") || raw.localizedCaseInsensitiveContains("opus 5.5") {
            return "Opus 5.5"
        } else if raw.localizedCaseInsensitiveContains("opus") {
            return "Opus 5.5"
        } else if raw.localizedCaseInsensitiveContains("sonnet") {
            return "Sonnet 4.5"
        } else {
            return "Opus 5.5"
        }
    }

    private func applyLiveUsageJson(_ utilization: [String: Any], to status: inout ClaudeStatus) {
        if let fiveHour = utilization["five_hour"] as? [String: Any],
           let used = (fiveHour["utilization"] as? NSNumber)?.doubleValue {
            status.fiveHourUsedPct = used
            status.fiveHourRemainingPct = max(0, 100.0 - used)
            if let resetsAtString = fiveHour["resets_at"] as? String,
               let date = parseISO8601(resetsAtString) {
                status.fiveHourResetsAt = date
                status.resetTimeString = ClaudeStatus.formatRelativeCountdown(date)
            } else if let resetsAtNum = (fiveHour["resets_at"] as? NSNumber)?.doubleValue {
                let date = Date(timeIntervalSince1970: resetsAtNum)
                status.fiveHourResetsAt = date
                status.resetTimeString = ClaudeStatus.formatRelativeCountdown(date)
            }
        }

        if let sevenDay = utilization["seven_day"] as? [String: Any],
           let used = (sevenDay["utilization"] as? NSNumber)?.doubleValue {
            status.sevenDayUsedPct = used
            status.sevenDayRemainingPct = max(0, 100.0 - used)
            if let resetsAtString = sevenDay["resets_at"] as? String,
               let date = parseISO8601(resetsAtString) {
                status.sevenDayResetsAt = date
                status.sevenDayResetsInString = ClaudeStatus.formatRelativeCountdown(date)
            } else if let resetsAtNum = (sevenDay["resets_at"] as? NSNumber)?.doubleValue {
                let date = Date(timeIntervalSince1970: resetsAtNum)
                status.sevenDayResetsAt = date
                status.sevenDayResetsInString = ClaudeStatus.formatRelativeCountdown(date)
            }
        }

        if let iguana = utilization["iguana_necktie"] as? [String: Any],
           let rem = (iguana["remaining_dollars"] as? NSNumber)?.doubleValue {
            status.remainingDollars = rem
        }
    }

    /// The keychain OAuth token is only refreshed by the Claude Code CLI, and Desktop-app
    /// sessions never touch it, so it goes stale after ~8h. `claude -p /usage` is a local
    /// slash command: it refreshes and rewrites the token through the CLI's own logic and
    /// makes no model call (0 tokens), so this never consumes quota or rotates tokens behind
    /// the CLI's back.
    private func refreshTokenViaCLI() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        guard let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["-p", "/usage", "--output-format", "json",
                             "--no-session-persistence", "--strict-mcp-config"]
        var env = ProcessInfo.processInfo.environment
        for key in env.keys where key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") || key == "ANTHROPIC_BASE_URL" {
            env.removeValue(forKey: key)
        }
        process.environment = env
        let workDir = home.appendingPathComponent(".config/llm-track", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = workDir
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    private struct KeychainCredentials {
        let accessToken: String
        let expiresAt: Date?
    }

    private func fetchKeychainCredentials() -> KeychainCredentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let jsonData = str.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String else {
                return nil
            }
            let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000.0) }
            return KeychainCredentials(accessToken: token, expiresAt: expiresAt)
        } catch {
            return nil
        }
    }

    private struct LiveUsageFetchResult {
        let json: [String: Any]?
        let statusCode: Int
        let retryAfter: Double?
    }

    private func fetchLiveOAuthUsage(token: String) -> LiveUsageFetchResult {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1") else {
            return LiveUsageFetchResult(json: nil, statusCode: 0, retryAfter: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.310", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var resultJson: [String: Any]?
        var statusCode = 0
        var retryAfter: Double?

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                statusCode = http.statusCode
                if let retryHeader = http.value(forHTTPHeaderField: "Retry-After"),
                   let sec = Double(retryHeader) {
                    retryAfter = sec
                }
                if (200...299).contains(http.statusCode),
                   let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    resultJson = json
                }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 4.5)
        return LiveUsageFetchResult(json: resultJson, statusCode: statusCode, retryAfter: retryAfter)
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
