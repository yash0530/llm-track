import Cocoa
import Foundation

@main
struct LLMTrackApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--dump") || CommandLine.arguments.contains("--test") {
            let claude = ClaudeCollector().collect()
            let agy = AGYCollector().collect()
            let kiro = KiroCollector().collect()
            let qwen = QwenCollector().collect()

            print("=== LLM TRACK TELEMETRY ===")
            print("Claude: running=\(claude.process.isRunning), pid=\(claude.process.pid ?? 0), 5h=\(claude.fiveHourRemainingPct ?? 0)% rem, 7d=\(claude.sevenDayRemainingPct ?? 0)% rem, credits=$\(claude.remainingDollars ?? 0)")
            print("AGY: running=\(agy.process.isRunning), model=\(agy.model), tokens=\(agy.contextTokensFormatted ?? "0"), context=\(agy.contextRemainingPct ?? 0)% rem, steps=\(agy.sessionSteps ?? 0), acct=\(agy.account ?? "none")")
            print("Kiro: running=\(kiro.process.isRunning), pid=\(kiro.process.pid ?? 0), model=\(kiro.model), context=\(kiro.contextRemainingPct ?? 0)% rem, acct=\(kiro.account ?? "none")")
            print("Qwen: serverRunning=\(qwen.isServerRunning), model=\(qwen.modelName), disk=\(qwen.diskSize)")
            print("===========================")
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
