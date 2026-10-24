import Foundation

public struct ProcessMatch: Sendable {
    public let pid: Int
    public let cpuPercent: Double
    public let command: String
}

public enum ProcessHelper {
    public static func findProcesses(matching patterns: [String]) -> [ProcessMatch] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,%cpu,command"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            // Read data before waitUntilExit to prevent OS pipe buffer deadlocks
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return [] }

            var results: [ProcessMatch] = []
            let lines = output.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("PID") else { continue }
                guard !trimmed.contains("grep") else { continue }

                // Check if any pattern matches
                let matchesPattern = patterns.contains { pattern in
                    trimmed.localizedCaseInsensitiveContains(pattern)
                }

                if matchesPattern {
                    let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                    if parts.count >= 3,
                       let pid = Int(parts[0]),
                       let cpu = Double(parts[1]) {
                        let command = String(parts[2])
                        // Exclude this helper or monitor processes
                        if !command.contains("LLMTrack") {
                            results.append(ProcessMatch(pid: pid, cpuPercent: cpu, command: command))
                        }
                    }
                }
            }
            return results
        } catch {
            return []
        }
    }
}
