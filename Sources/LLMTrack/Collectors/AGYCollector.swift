import Foundation

public final class AGYCollector: @unchecked Sendable {
    private static var cachedStatus: AGYStatus? = nil
    private static let lock = NSLock()

    public init() {}

    public func collect() -> AGYStatus {
        var status = AGYStatus()

        // 1. Process matching
        let matches = ProcessHelper.findProcesses(matching: ["agy ", "Antigravity", "language_server"])
        let cliProcess = matches.first { $0.command.hasPrefix("agy ") || $0.command.contains("/agy ") }
        let hasLangServer = matches.contains { $0.command.contains("language_server") || $0.command.contains("Antigravity") }

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

        // 2. Extract plan tier from global storage if available
        if let tier = detectTierFromGlobalStorage() {
            status.planTier = tier
        } else {
            status.planTier = "Google AI Pro"
        }

        // 3. Query live language_server Connect-RPC endpoint
        if let liveQuota = fetchLiveQuotaSummary() {
            Self.lock.lock()
            Self.cachedStatus = liveQuota
            Self.lock.unlock()

            status.geminiWeeklyRemainingPct = liveQuota.geminiWeeklyRemainingPct
            status.geminiWeeklyResetString = liveQuota.geminiWeeklyResetString
            status.geminiFiveHourRemainingPct = liveQuota.geminiFiveHourRemainingPct
            status.geminiFiveHourResetString = liveQuota.geminiFiveHourResetString
            status.claudeGptWeeklyRemainingPct = liveQuota.claudeGptWeeklyRemainingPct
            status.claudeGptFiveHourRemainingPct = liveQuota.claudeGptFiveHourRemainingPct
        } else {
            // Fallback to cached quota if available
            Self.lock.lock()
            if let cached = Self.cachedStatus {
                status.geminiWeeklyRemainingPct = cached.geminiWeeklyRemainingPct
                status.geminiWeeklyResetString = cached.geminiWeeklyResetString
                status.geminiFiveHourRemainingPct = cached.geminiFiveHourRemainingPct
                status.geminiFiveHourResetString = cached.geminiFiveHourResetString
                status.claudeGptWeeklyRemainingPct = cached.claudeGptWeeklyRemainingPct
                status.claudeGptFiveHourRemainingPct = cached.claudeGptFiveHourRemainingPct
            }
            Self.lock.unlock()
        }

        return status
    }

    private func fetchLiveQuotaSummary() -> AGYStatus? {
        // Step 1: Find language_server PID and CSRF token from running processes
        let psProcess = Process()
        psProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
        psProcess.arguments = ["-A", "-o", "pid,command"]
        let psPipe = Pipe()
        psProcess.standardOutput = psPipe
        psProcess.standardError = Pipe()

        var pidString: String? = nil
        var csrfToken: String? = nil

        do {
            try psProcess.run()
            let data = psPipe.fileHandleForReading.readDataToEndOfFile()
            psProcess.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return nil }
            for line in output.components(separatedBy: "\n") {
                if line.contains("language_server") && line.contains("--csrf_token") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let firstSpace = trimmed.firstIndex(of: " ") {
                        pidString = String(trimmed[..<firstSpace])
                    }
                    if let csrfRange = line.range(of: "--csrf_token") {
                        let after = line[csrfRange.upperBound...].trimmingCharacters(in: .whitespaces)
                        if let token = after.components(separatedBy: " ").first {
                            csrfToken = token
                        }
                    }
                    break
                }
            }
        } catch {
            return nil
        }

        guard let pid = pidString, let csrf = csrfToken else { return nil }

        // Step 2: Find listening TCP ports for this PID
        let lsofProcess = Process()
        lsofProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsofProcess.arguments = ["-nP", "-a", "-p", pid, "-iTCP", "-sTCP:LISTEN"]
        let lsofPipe = Pipe()
        lsofProcess.standardOutput = lsofPipe
        lsofProcess.standardError = Pipe()

        var ports: [String] = []
        do {
            try lsofProcess.run()
            let lsofData = lsofPipe.fileHandleForReading.readDataToEndOfFile()
            lsofProcess.waitUntilExit()

            guard let lsofOutput = String(data: lsofData, encoding: .utf8) else { return nil }
            for line in lsofOutput.components(separatedBy: "\n") {
                if let colonIdx = line.range(of: ":")?.upperBound,
                   let listenIdx = line.range(of: " (LISTEN)")?.lowerBound,
                   colonIdx < listenIdx {
                    let portStr = String(line[colonIdx..<listenIdx]).trimmingCharacters(in: .whitespaces)
                    if !portStr.isEmpty && !ports.contains(portStr) {
                        ports.append(portStr)
                    }
                }
            }
        } catch {
            return nil
        }

        guard !ports.isEmpty else { return nil }

        // Step 3: Query each port until successful response
        for port in ports {
            let curlProcess = Process()
            curlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            curlProcess.arguments = [
                "-k", "-s", "-m", "2", "-X", "POST",
                "-H", "Content-Type: application/json",
                "-H", "x-codeium-csrf-token: \(csrf)",
                "-d", "{}",
                "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
            ]
            let curlPipe = Pipe()
            curlProcess.standardOutput = curlPipe
            curlProcess.standardError = Pipe()

            do {
                try curlProcess.run()
                let curlData = curlPipe.fileHandleForReading.readDataToEndOfFile()
                curlProcess.waitUntilExit()

                if curlProcess.terminationStatus == 0,
                   let json = try? JSONSerialization.jsonObject(with: curlData) as? [String: Any],
                   let responseObj = json["response"] as? [String: Any],
                   let groups = responseObj["groups"] as? [[String: Any]] {
                    return parseQuotaGroups(groups)
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func parseQuotaGroups(_ groups: [[String: Any]]) -> AGYStatus {
        var status = AGYStatus()

        for group in groups {
            let groupName = (group["displayName"] as? String) ?? ""
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }

            if groupName.localizedCaseInsensitiveContains("gemini") {
                for bucket in buckets {
                    let bucketId = (bucket["bucketId"] as? String) ?? ""
                    let window = (bucket["window"] as? String) ?? ""
                    let fraction = (bucket["remainingFraction"] as? NSNumber)?.doubleValue ?? 1.0
                    let resetTimeStr = bucket["resetTime"] as? String

                    let pct = max(0.0, min(100.0, fraction * 100.0))
                    let resetDesc = formatResetTime(resetTimeStr)

                    if bucketId.contains("5h") || window == "5h" {
                        status.geminiFiveHourRemainingPct = pct
                        if let desc = resetDesc {
                            status.geminiFiveHourResetString = desc
                        }
                    } else if bucketId.contains("weekly") || window == "weekly" {
                        status.geminiWeeklyRemainingPct = pct
                        if let desc = resetDesc {
                            status.geminiWeeklyResetString = desc
                        }
                    }
                }
            } else if groupName.localizedCaseInsensitiveContains("claude") || groupName.localizedCaseInsensitiveContains("gpt") {
                for bucket in buckets {
                    let bucketId = (bucket["bucketId"] as? String) ?? ""
                    let window = (bucket["window"] as? String) ?? ""
                    let fraction = (bucket["remainingFraction"] as? NSNumber)?.doubleValue ?? 1.0

                    let pct = max(0.0, min(100.0, fraction * 100.0))
                    if bucketId.contains("5h") || window == "5h" {
                        status.claudeGptFiveHourRemainingPct = pct
                    } else if bucketId.contains("weekly") || window == "weekly" {
                        status.claudeGptWeeklyRemainingPct = pct
                    }
                }
            }
        }

        return status
    }

    private func formatResetTime(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var targetDate = formatter.date(from: raw)
        if targetDate == nil {
            formatter.formatOptions = [.withInternetDateTime]
            targetDate = formatter.date(from: raw)
        }

        guard let date = targetDate else { return nil }
        return ClaudeStatus.formatRelativeCountdown(date)
    }

    private func detectTierFromGlobalStorage() -> String? {
        let dbPath = ("~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus';"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let base64Str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let rawData = Data(base64Encoded: base64Str),
                  let text = String(data: rawData, encoding: .ascii) else {
                return nil
            }

            if text.contains("g1-pro-tier") || text.contains("Google AI Pro") {
                return "Google AI Pro"
            } else if text.contains("Google AI Ultra") {
                return "Google AI Ultra"
            }
            return nil
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
