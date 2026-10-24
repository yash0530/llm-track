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

        // 2. Parse model from settings.json
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let model = json["model"] as? String {
            if model.localizedCaseInsensitiveContains("opus") {
                status.model = "Opus 4.5"
            } else if model.localizedCaseInsensitiveContains("sonnet") {
                status.model = "Sonnet 4.5"
            } else {
                status.model = model.capitalized
            }
        }

        // 3. Lifetime messages from stats-cache.json
        let statsURL = home.appendingPathComponent(".claude/stats-cache.json")
        if let data = try? Data(contentsOf: statsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let totalMsgs = json["totalMessages"] as? Int {
            status.lifetimeMessages = totalMsgs
        }

        // 4. Query live usage from Anthropic OAuth endpoint using macOS Keychain token
        var liveFetched = false
        if let token = fetchKeychainToken() {
            if let liveUsage = fetchLiveOAuthUsage(token: token) {
                liveFetched = true
                applyUsageJson(liveUsage, to: &status)
            }
        }

        // 5. Fallback to cached ~/.claude.json if live API was unreachable
        if !liveFetched {
            let claudeConfigURL = home.appendingPathComponent(".claude.json")
            if let configData = try? Data(contentsOf: claudeConfigURL),
               let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
               let cachedUsage = configJson["cachedUsageUtilization"] as? [String: Any],
               let utilization = cachedUsage["utilization"] as? [String: Any] {
                applyUsageJson(utilization, to: &status)
            }
        }

        status.lastUpdated = Date()
        return status
    }

    private func applyUsageJson(_ utilization: [String: Any], to status: inout ClaudeStatus) {
        // 5-hour rolling window
        if let fiveHour = utilization["five_hour"] as? [String: Any],
           let used = fiveHour["utilization"] as? Double {
            status.fiveHourUsedPct = used
            status.fiveHourRemainingPct = max(0, 100.0 - used)

            if let resetsAtString = fiveHour["resets_at"] as? String {
                status.fiveHourResetsAt = parseISO8601(resetsAtString)
            }
        }

        // 7-day weekly window
        if let sevenDay = utilization["seven_day"] as? [String: Any],
           let used = sevenDay["utilization"] as? Double {
            status.sevenDayUsedPct = used
            status.sevenDayRemainingPct = max(0, 100.0 - used)
        }

        // Extra usage / credits balance
        if let iguana = utilization["iguana_necktie"] as? [String: Any],
           let rem = iguana["remaining_dollars"] as? Double {
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
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = json
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.2)
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
