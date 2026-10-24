import Foundation

public final class ClaudeCollector: Sendable {
    public init() {}

    public func collect() -> ClaudeStatus {
        var status = ClaudeStatus()

        // 1. Process telemetry
        let matches = ProcessHelper.findProcesses(matching: ["claude "])
        // Filter out daemon or helper if an actual CLI session is present
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

        // 2. Parse model from settings.json
        let home = FileManager.default.homeDirectoryForCurrentUser
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

        // 3. Parse ~/.claude.json for quotas
        let claudeConfigURL = home.appendingPathComponent(".claude.json")
        guard let configData = try? Data(contentsOf: claudeConfigURL),
              let configJson = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              let cachedUsage = configJson["cachedUsageUtilization"] as? [String: Any],
              let utilization = cachedUsage["utilization"] as? [String: Any] else {
            return status
        }

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

        // Extra usage / credits
        if let iguana = utilization["iguana_necktie"] as? [String: Any],
           let rem = iguana["remaining_dollars"] as? Double {
            status.remainingDollars = rem
        }

        status.lastUpdated = Date()
        return status
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
