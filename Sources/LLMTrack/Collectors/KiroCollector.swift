import Foundation

public final class KiroCollector: Sendable {
    public init() {}

    public func collect() -> KiroStatus {
        var status = KiroStatus()

        // 1. Process matching
        let matches = ProcessHelper.findProcesses(matching: ["kiro-cli", "kiro_cli", "kiro-cli-term", "Kiro.app", "kiro "])
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

        // 2. Model from ~/.kiro/settings/cli.json
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home.appendingPathComponent(".kiro/settings/cli.json")
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let defaultModel = json["chat.defaultModel"] as? String {
            status.model = formatModelName(defaultModel)
        } else {
            status.model = "Opus 5.5 (Kiro)"
        }

        // 3. Inspect recent sessions in ~/.kiro/sessions/cli/ for session title
        let sessionsDir = home.appendingPathComponent(".kiro/sessions/cli")
        if let files = try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            let sorted = jsonFiles.sorted { f1, f2 in
                let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }

            if let latestSession = sorted.first,
               let data = try? Data(contentsOf: latestSession),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let title = json["title"] as? String, !title.isEmpty {
                    status.sessionTitle = title
                }
                if let sessionState = json["session_state"] as? [String: Any],
                   let rts = sessionState["rts_model_state"] as? [String: Any],
                   let modelInfo = rts["model_info"] as? [String: Any],
                   let modelName = modelInfo["model_name"] as? String {
                    status.model = formatModelName(modelName)
                }
            }
        }

        return status
    }

    private func formatModelName(_ raw: String) -> String {
        if raw.localizedCaseInsensitiveContains("opus") {
            return "Opus 5.5 (Kiro)"
        } else if raw.localizedCaseInsensitiveContains("sonnet") {
            return "Sonnet 4.6 (Kiro)"
        } else {
            return raw
        }
    }
}
