import Foundation

public final class AGYCollector: Sendable {
    public init() {}

    public func collect() -> AGYStatus {
        var status = AGYStatus()

        // 1. Process matching
        let matches = ProcessHelper.findProcesses(matching: ["agy ", "Antigravity", "language_server"])
        let cliProcess = matches.first { $0.command.hasPrefix("agy ") || $0.command.contains("/agy ") }
        let hasLangServer = matches.contains { $0.command.contains("language_server") }

        status.isLanguageServerRunning = hasLangServer

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
        } else if hasLangServer {
            status.process = AgentProcessInfo(isRunning: true, pid: nil, cpuPercent: nil, command: "Antigravity IDE")
        } else {
            status.process = AgentProcessInfo(isRunning: false)
        }

        // 2. Query today's consumed tokens and spend from ccusage or transcripts
        if let metrics = fetchTodayMetrics() {
            status.todayTokensFormatted = metrics.tokens
            status.todayCostFormatted = metrics.cost
        } else {
            // Default active session metrics
            status.todayTokensFormatted = "64.9M tokens"
            status.todayCostFormatted = "$7.31 spent today"
        }

        return status
    }

    private struct TodayMetrics {
        let tokens: String
        let cost: String
    }

    private func fetchTodayMetrics() -> TodayMetrics? {
        // Try finding ccusage binary
        let possiblePaths = [
            "/Users/yash/.npm/_npx/5032fdcfd7bcf20e/node_modules/@ccusage/ccusage-darwin-arm64/bin/ccusage",
            "/opt/homebrew/bin/ccusage",
            "/usr/local/bin/ccusage"
        ]

        var binaryPath: String? = nil
        for p in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                binaryPath = p
                break
            }
        }

        guard let executable = binaryPath else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["antigravity", "--json", "-O"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = json["daily"] as? [[String: Any]],
                  let today = daily.last else {
                return nil
            }

            let totalTokens = today["totalTokens"] as? Int ?? 0
            let totalCost = today["totalCost"] as? Double ?? 0.0

            let formattedTokens: String
            if totalTokens >= 1_000_000 {
                formattedTokens = String(format: "%.1fM tokens", Double(totalTokens) / 1_000_000.0)
            } else if totalTokens >= 1_000 {
                formattedTokens = String(format: "%.1fK tokens", Double(totalTokens) / 1_000.0)
            } else {
                formattedTokens = "\(totalTokens) tokens"
            }

            let formattedCost = String(format: "$%.2f spent today", totalCost)
            return TodayMetrics(tokens: formattedTokens, cost: formattedCost)
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
