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
    private static let lock = NSLock()

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

        // 3. Quota resolution: Priority 1 is Live OAuth Usage (and cached live quota)
        var appliedLiveQuota = false

        if let token = fetchKeychainToken() {
            var shouldFetch = false
            let now = Date()

            Self.lock.lock()
            if forceLive {
                // If user forced refresh, allow it as long as we're not hammering within 3 seconds
                if now.timeIntervalSince(Self.lastLiveFetchTime) >= 3.0 {
                    shouldFetch = true
                    Self.lastLiveFetchTime = now
                }
            } else if now >= Self.rateLimitBackoffUntil && now.timeIntervalSince(Self.lastLiveFetchTime) >= 60.0 {
                shouldFetch = true
                Self.lastLiveFetchTime = now
            }
            let cached = Self.cachedLiveUsage
            Self.lock.unlock()

            if shouldFetch {
                let fetchResult = fetchLiveOAuthUsage(token: token)
                if let liveUsage = fetchResult.json {
                    Self.lock.lock()
                    Self.cachedLiveUsage = liveUsage
                    Self.cachedLiveUsageDate = Date()
                    Self.rateLimitBackoffUntil = .distantPast
                    Self.lock.unlock()

                    applyLiveUsageJson(liveUsage, to: &status)
                    saveDiskCache(status: status)
                    appliedLiveQuota = true
                } else {
                    Self.lock.lock()
                    if fetchResult.statusCode == 429 {
                        let retrySec = fetchResult.retryAfter ?? 60.0
                        Self.rateLimitBackoffUntil = Date().addingTimeInterval(max(30.0, retrySec))
                    } else {
                        Self.rateLimitBackoffUntil = Date().addingTimeInterval(30.0)
                    }
                    Self.lock.unlock()

                    // Fallback to in-memory cached live usage or disk cache
                    if let cached = cached {
                        applyLiveUsageJson(cached, to: &status)
                        appliedLiveQuota = true
                    } else if let disk = loadDiskCache() {
                        applyDiskCache(disk, to: &status)
                        appliedLiveQuota = true
                    }
                }
            } else if let cached = cached {
                // Not due for network fetch: apply our in-memory live usage
                applyLiveUsageJson(cached, to: &status)
                appliedLiveQuota = true
            } else if let disk = loadDiskCache() {
                // Cold start: load persisted disk cache
                applyDiskCache(disk, to: &status)
                appliedLiveQuota = true
            }
        }

        // 4. Fallback to local files ONLY if no live/cached OAuth quota could be resolved
        if !appliedLiveQuota {
            // Check statusline rate limits if the file is fresh (< 30 minutes old)
            if Date().timeIntervalSince(statuslineModDate) < 1800,
               let slJson = statuslineData,
               let rateLimits = slJson["rate_limits"] as? [String: Any] {
                applyStatuslineRateLimits(rateLimits, to: &status)
            }

            // Fallback to ~/.claude.json cachedUsageUtilization if still missing
            if status.fiveHourRemainingPct == nil {
                let claudeConfigURL = home.appendingPathComponent(".claude.json")
                if let configData = try? Data(contentsOf: claudeConfigURL),
                   let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
                   let cachedUsage = configJson["cachedUsageUtilization"] as? [String: Any],
                   let utilization = cachedUsage["utilization"] as? [String: Any] {
                    applyLiveUsageJson(utilization, to: &status)
                }
            }
        }

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

        // 6. Dynamic relative reset countdown recalculation
        if let resetsAt = status.fiveHourResetsAt {
            if resetsAt.timeIntervalSince(Date()) <= 0 {
                // 5-hour window expired and refreshed!
                status.fiveHourUsedPct = 0.0
                status.fiveHourRemainingPct = 100.0
                status.resetTimeString = "Resetting"
            } else {
                status.resetTimeString = ClaudeStatus.formatRelativeCountdown(resetsAt)
            }
        }
        if let resetsAt = status.sevenDayResetsAt {
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

    private func saveDiskCache(status: ClaudeStatus) {
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
            updatedAt: Date()
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

        if let resetsAt = cache.fiveHourResetsAt {
            if resetsAt.timeIntervalSince(Date()) <= 0 {
                status.fiveHourUsedPct = 0.0
                status.fiveHourRemainingPct = 100.0
                status.resetTimeString = "Resetting"
            } else {
                status.resetTimeString = ClaudeStatus.formatRelativeCountdown(resetsAt)
            }
        }
        if let resetsAt = cache.sevenDayResetsAt {
            status.sevenDayResetsInString = ClaudeStatus.formatRelativeCountdown(resetsAt)
        }
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

    private func fetchKeychainToken() -> String? {
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
            return token
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
