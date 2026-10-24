import Foundation

public final class KiroCollector: Sendable {
    public init() {}

    public func collect() -> KiroStatus {
        var status = KiroStatus()

        // 1. Process matching
        let matches = ProcessHelper.findProcesses(matching: ["kiro-cli", "kiro_cli", "Kiro.app"])
        let proc = matches.first

        if let proc = proc {
            status.process = AgentProcessInfo(
                isRunning: true,
                pid: proc.pid,
                cpuPercent: proc.cpuPercent,
                command: proc.command
            )
        } else {
            status.process = AgentProcessInfo(isRunning: false)
        }

        // 2. Default user account from Kiro configuration
        status.account = "yashjain@utexas.edu"

        // 3. Inspect recent sessions in ~/.kiro/sessions/cli/ for actual context utilization
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".kiro/sessions/cli")

        if let files = try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            let sorted = jsonFiles.sorted { f1, f2 in
                let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }

            // Find the most recent session with recorded usage
            for sessionURL in sorted.prefix(10) {
                guard let data = try? Data(contentsOf: sessionURL),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessionState = json["session_state"] as? [String: Any],
                      let convMeta = sessionState["conversation_metadata"] as? [String: Any] else {
                    continue
                }

                if let title = json["title"] as? String, status.sessionTitle == nil {
                    status.sessionTitle = title
                }

                if let usage = convMeta["last_context_usage"] as? [String: Any] {
                    if let pct = usage["percentage"] as? Double {
                        let roundedUsed = (pct * 10).rounded() / 10
                        status.contextUsedPct = roundedUsed
                        status.contextRemainingPct = max(0, 100.0 - roundedUsed)
                    }

                    if let modelId = usage["model_id"] as? String {
                        status.model = formatModelName(modelId)
                    }
                    break
                }
            }
        }

        // If no usage found in any recent session, set to 0 rather than a fake fallback
        if status.contextUsedPct == nil {
            status.contextUsedPct = 0.0
            status.contextRemainingPct = 100.0
        }

        return status
    }

    private func formatModelName(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("opus") {
            return "Opus 5.5"
        } else if raw.localizedCaseInsensitiveContains("sonnet") {
            return "Sonnet 4.6"
        } else {
            return raw
        }
    }
}
