import Foundation

public final class ClaudeCollector: Sendable {
    public init() {}

    public func collect() -> ClaudeStatus {
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

        // 2. Parse model accurately from settings.json and project logs (Opus 5.5, Sonnet 4.5, etc.)
        status.model = detectModel(home: home)

        // 3. Check ground-truth session exhaustion directly from local project transcripts
        let exhaustionInfo = detectExhaustionFromLocalLogs(home: home)
        if let info = exhaustionInfo {
            status.fiveHourUsedPct = 100.0
            status.fiveHourRemainingPct = 0.0
            status.resetTimeString = info.resetText
            if let resetsAt = info.resetsAt {
                status.fiveHourResetsAt = resetsAt
            }
        }

        // 4. Read cached limits from ~/.claude.json (7-day weekly quota & remaining extra credits)
        let claudeConfigURL = home.appendingPathComponent(".claude.json")
        if let configData = try? Data(contentsOf: claudeConfigURL),
           let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
           let cachedUsage = configJson["cachedUsageUtilization"] as? [String: Any],
           let utilization = cachedUsage["utilization"] as? [String: Any] {

            // 7-day weekly quota
            if let sevenDay = utilization["seven_day"] as? [String: Any],
               let used = sevenDay["utilization"] as? Double {
                status.sevenDayUsedPct = used
                status.sevenDayRemainingPct = max(0, 100.0 - used)
            }

            // Extra usage credits balance (iguana_necktie)
            if let iguana = utilization["iguana_necktie"] as? [String: Any],
               let rem = iguana["remaining_dollars"] as? Double {
                status.remainingDollars = rem
            }

            // If local logs didn't catch exhaustion, check five_hour in config
            if status.fiveHourRemainingPct == nil,
               let fiveHour = utilization["five_hour"] as? [String: Any],
               let used = fiveHour["utilization"] as? Double {
                status.fiveHourUsedPct = used
                status.fiveHourRemainingPct = max(0, 100.0 - used)
                if let resetsAtString = fiveHour["resets_at"] as? String {
                    status.fiveHourResetsAt = parseISO8601(resetsAtString)
                }
            }
        }

        // 5. Check statusline_state.json if created by Claude Code statusline hook
        let statuslineURL = home.appendingPathComponent(".claude/statusline_state.json")
        if let slData = try? Data(contentsOf: statuslineURL),
           let slJson = try? JSONSerialization.jsonObject(with: slData) as? [String: Any] {
            if let modelObj = slJson["model"] as? [String: Any],
               let name = modelObj["display_name"] as? String, !name.isEmpty {
                status.model = formatModelName(name)
            }
            if let rateLimits = slJson["rate_limits"] as? [String: Any],
               let fiveHour = rateLimits["five_hour"] as? [String: Any],
               let usedPct = fiveHour["used_percentage"] as? Double {
                status.fiveHourUsedPct = usedPct
                status.fiveHourRemainingPct = max(0, 100.0 - usedPct)
            }
        }

        // 6. Best-effort live API query via Keychain token (does not block or fail if rate-limited)
        if let token = fetchKeychainToken() {
            if let liveResult = fetchLiveOAuthUsage(token: token) {
                if liveResult.isRateLimited {
                    status.fiveHourUsedPct = 100.0
                    status.fiveHourRemainingPct = 0.0
                } else if let liveUsage = liveResult.usage {
                    applyLiveUsageJson(liveUsage, to: &status)
                }
            }
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

    private func detectExhaustionFromLocalLogs(home: URL) -> ExhaustionResult? {
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

        // Look for: "You've hit your session limit · resets 4:40am (America/Los_Angeles)"
        if tailText.contains("You've hit your session limit") || tailText.contains("error type rate_limit, HTTP 429") {
            var resetText = "Resets soon"
            let resetsAt: Date? = nil

            if let range = tailText.range(of: "resets ") {
                let after = tailText[range.upperBound...]
                if let endParen = after.firstIndex(of: ")") {
                    let fullDetail = String(after[..<endParen])
                    // Example: "4:40am (America/Los_Angeles" -> clean to "Resets 4:40 AM"
                    let parts = fullDetail.components(separatedBy: "(")
                    let timePart = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !timePart.isEmpty {
                        resetText = "Resets \(timePart.uppercased())"
                    }
                }
            }

            return ExhaustionResult(resetText: resetText, resetsAt: resetsAt)
        }

        return nil
    }

    private func formatModelName(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("opus-5-5") || raw.localizedCaseInsensitiveContains("opus 5.5") {
            return "Opus 5.5"
        } else if raw.localizedCaseInsensitiveContains("opus") {
            return "Opus 5.5"
        } else if raw.localizedCaseInsensitiveContains("sonnet") {
            return "Sonnet 4.5"
        } else {
            return raw
        }
    }

    private func applyLiveUsageJson(_ utilization: [String: Any], to status: inout ClaudeStatus) {
        if let fiveHour = utilization["five_hour"] as? [String: Any],
           let used = fiveHour["utilization"] as? Double {
            status.fiveHourUsedPct = used
            status.fiveHourRemainingPct = max(0, 100.0 - used)
            if let resetsAtString = fiveHour["resets_at"] as? String {
                status.fiveHourResetsAt = parseISO8601(resetsAtString)
            }
        }

        if let sevenDay = utilization["seven_day"] as? [String: Any],
           let used = sevenDay["utilization"] as? Double {
            status.sevenDayUsedPct = used
            status.sevenDayRemainingPct = max(0, 100.0 - used)
        }

        if let iguana = utilization["iguana_necktie"] as? [String: Any],
           let rem = iguana["remaining_dollars"] as? Double {
            status.remainingDollars = rem
        }
    }

    private struct LiveFetchResult {
        let isRateLimited: Bool
        let usage: [String: Any]?
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

    private func fetchLiveOAuthUsage(token: String) -> LiveFetchResult? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var result: LiveFetchResult?

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 {
                    result = LiveFetchResult(isRateLimited: true, usage: nil)
                } else if (200...299).contains(http.statusCode),
                          let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    result = LiveFetchResult(isRateLimited: false, usage: json)
                }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.0)
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
