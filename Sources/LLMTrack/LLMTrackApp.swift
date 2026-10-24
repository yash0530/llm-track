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
            print("Claude: running=\(claude.process.isRunning), pid=\(claude.process.pid ?? 0), model=\(claude.model), 5h=\(claude.fiveHourRemainingPct ?? 0)% rem (\(claude.isExhausted ? "EXHAUSTED" : "OK")), resets=\(claude.resetsInString ?? "none"), 7d=\(claude.sevenDayRemainingPct ?? 0)% rem (\(claude.sevenDayResetsInString ?? "")), credits=$\(claude.remainingDollars ?? 0)")
            print("AGY: running=\(agy.process.isRunning), model=\(agy.model), plan=\(agy.planTier), geminiWeekly=\(agy.geminiWeeklyRemainingPct)% rem (\(agy.geminiWeeklyResetString)), gemini5h=\(agy.geminiFiveHourRemainingPct)% rem (\(agy.geminiFiveHourResetString)), claudeGptWeekly=\(agy.claudeGptWeeklyRemainingPct)% rem")
            print("Kiro: running=\(kiro.process.isRunning), pid=\(kiro.process.pid ?? 0), model=\(kiro.model), plan=\(kiro.planTier), credits=\(kiro.creditsUsed)/\(kiro.creditsTotal) (\(kiro.creditsRemainingPct)% rem, \(kiro.isExhausted ? "EXHAUSTED" : "OK")), resets=\(kiro.resetsOnString)")
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
