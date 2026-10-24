import SwiftUI

public struct MenuBarTileView: View {
    @ObservedObject var store: LLMTrackStore

    public init(store: LLMTrackStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 5) {
            // Minimalist Chip / AI Icon
            Image(systemName: "cpu")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            // 4 Status Indicator Dots
            HStack(spacing: 3) {
                // Claude
                Circle()
                    .fill(store.telemetry.claude.process.isRunning ? Color.green : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
                    .help("Claude Code: \(store.telemetry.claude.process.isRunning ? "Running" : "Idle")")

                // AGY
                Circle()
                    .fill(store.telemetry.agy.process.isRunning ? Color.green : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
                    .help("Antigravity: \(store.telemetry.agy.process.isRunning ? "Running" : "Idle")")

                // Kiro
                Circle()
                    .fill(store.telemetry.kiro.process.isRunning ? Color.yellow : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
                    .help("Kiro: \(store.telemetry.kiro.process.isRunning ? "Running" : "Idle")")

                // Local Qwen
                Circle()
                    .fill(store.telemetry.qwen.isServerRunning ? Color.green : Color.white.opacity(0.25))
                    .frame(width: 5, height: 5)
                    .help("Qwen Local: \(store.telemetry.qwen.isServerRunning ? "Server Active" : "Stopped")")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
    }
}
