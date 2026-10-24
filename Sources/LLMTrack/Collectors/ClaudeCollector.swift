import Foundation

public final class ClaudeCollector: @unchecked Sendable {
    private static var lastLiveFetchTime: Date = .distantPast
    private static var cachedLiveUsage: [String: Any]? = nil
    private static let lock = NSLock()

    public init() {}

    public func collect(forceLive: Bool = false) -> ClaudeStatus {
        var status = ClaudeStatus()

        // 1. Process telemetry
        let matches = ProcessHelper.findProcesses(matching: ["claude "])
        let primaryProcess = matches.first { $0.command.hasPrefix("claude ") || $0.command.contains("/claude ") } ?? matches.first

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

        // 2. Parse model accurately from settings.json or default
        status.model = detectModel(home: home)

        // 3. Read cached utilization from ~/.claude.json (provides five_hour, seven_day, and iguana_necktie / extra credits)
        let claudeConfigURL = home.appendingPathComponent(".claude.json")
        if let configData = try? Data(contentsOf: claudeConfigURL),
           let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
           let cachedUsage = configJson["cachedUsageUtilization"] as? [String: Any],
           let utilization = cachedUsage["utilization"] as? [String: Any] {
            applyLiveUsageJson(utilization, to: &status)
        }

        // 4. Read active statusline_state.json if available (written on every Claude turn)
        let statuslineURL = home.appendingPathComponent(".claude/statusline_state.json")
        if let slData = try? Data(contentsOf: statuslineURL),
           let slJson = try? JSONSerialization.jsonObject(with: slData) as? [String: Any] {
            if let modelObj = slJson["model"] as? [String: Any],
               let name = modelObj["display_name"] as? String, !name.isEmpty {
                status.model = formatModelName(name)
            }
            if let rateLimits = slJson["rate_limits"] as? [String: Any] {
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
        }

        // 5. Query live OAuth usage endpoint with throttling (> 60s) unless forceLive is true
        if let token = fetchKeychainToken() {
            var shouldFetch = forceLive
            Self.lock.lock()
            if forceLive || Date().timeIntervalSince(Self.lastLiveFetchTime) > 60.0 {
                shouldFetch = true
                Self.lastLiveFetchTime = Date()
            }
            let cached = Self.cachedLiveUsage
            Self.lock.unlock()

            if shouldFetch {
                if let liveUsage = fetchLiveOAuthUsage(token: token) {
                    Self.lock.lock()
                    Self.cachedLiveUsage = liveUsage
                    Self.lock.unlock()
                    applyLiveUsageJson(liveUsage, to: &status)
                }
            } else if let cached = cached {
                applyLiveUsageJson(cached, to: &status)
            }
        }

        // 6. Check if latest assistant turn in transcripts was an active rate limit block
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

        // Set default formatted relative reset strings if still not set
        if status.resetTimeString == nil, let resetsAt = status.fiveHourResetsAt {
            status.resetTimeString = ClaudeStatus.formatRelativeCountdown(resetsAt)
        }
        if status.sevenDayResetsInString == nil, let resetsAt = status.sevenDayResetsAt {
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

        guard let fileHandle = try? FileHandle(forReadingFrom: latestFile) else { return nil }
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        let readLength = min(fileSize, 65536)
        fileHandle.seek(toFileOffset: fileSize - readLength)
        let data = fileHandle.readDataToEndOfFile()

        guard let tailText = String(data: data, encoding: .utf8) else { return nil }
        let lines = tailText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Find the newest assistant turn: if it is a rate limit block, return exhaustion
        for line in lines.reversed().prefix(20) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let type = json["type"] as? String
            if type == "assistant" {
                let isApiError = json["isApiErrorMessage"] as? Bool ?? false
                let err = json["error"] as? String
                let status = json["apiErrorStatus"] as? Int
                if isApiError && (err == "rate_limit" || status == 429) {
                    return ExhaustionResult(resetText: "Resets soon", resetsAt: nil)
                }
                // If newest assistant response was normal, session is working
                return nil
            }
        }

        return nil
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

    private func fetchLiveOAuthUsage(token: String) -> [String: Any]? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.310", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode),
               let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = json
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.8)
        return result
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
