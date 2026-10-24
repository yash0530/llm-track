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

        // 2. Google Account from ~/.gemini/google_accounts.json
        let home = FileManager.default.homeDirectoryForCurrentUser
        let accountsURL = home.appendingPathComponent(".gemini/google_accounts.json")
        if let data = try? Data(contentsOf: accountsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let active = json["active"] as? String {
            status.account = active
        }

        // 3. Extract 100% authentic live token telemetry from recent conversation transcript
        let brainURL = home.appendingPathComponent(".gemini/antigravity/brain")
        if let subdirs = try? FileManager.default.contentsOfDirectory(at: brainURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let sorted = subdirs.sorted { u1, u2 in
                let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }

            for dir in sorted.prefix(3) {
                let transcriptURL = dir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
                guard FileManager.default.fileExists(atPath: transcriptURL.path),
                      let fileContent = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
                    continue
                }

                let lines = fileContent.components(separatedBy: .newlines).filter { !$0.isEmpty }
                guard !lines.isEmpty else { continue }

                status.sessionSteps = lines.count

                // Inspect lines from the end to find the most recent token metrics
                for line in lines.reversed() {
                    guard let data = line.data(using: .utf8),
                          let stepJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }

                    let input = stepJson["input_tokens"] as? Int ?? 0
                    let cache = stepJson["cache_read_tokens"] as? Int ?? 0

                    if input > 0 || cache > 0 {
                        let totalTokens = input + cache
                        status.contextTokens = totalTokens
                        status.maxContextTokens = 1_000_000

                        let pctUsed = (Double(totalTokens) / 1_000_000.0) * 100.0
                        let roundedUsed = (pctUsed * 10).rounded() / 10
                        status.contextUsedPct = roundedUsed
                        status.contextRemainingPct = max(0, 100.0 - roundedUsed)
                        break
                    }
                }

                if status.contextTokens != nil {
                    break
                }
            }
        }

        return status
    }

    private func formatModelName(_ raw: String) -> String {
        if raw.contains("flash-high") {
            return "Gemini 3.8 Flash High"
        } else if raw.contains("flash-medium") {
            return "Gemini 3.8 Flash Med"
        } else if raw.contains("opus") {
            return "Claude Opus 4.6"
        } else if raw.contains("sonnet") {
            return "Claude Sonnet 4.6"
        } else {
            return raw
        }
    }
}
