import SwiftUI

public struct MenuBarTileView: View {
    @ObservedObject var store: LLMTrackStore
    @State private var isBreathing = false

    public init(store: LLMTrackStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 5) {
            // Anchor Symbol (Adapts to light & dark wallpapers via Color.primary)
            Image(systemName: "cpu")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))

            // 4 Micro-Status Dots: Claude, AGY, Kiro, Local Qwen
            HStack(spacing: 3.2) {
                // Claude
                statusDot(
                    isRunning: store.telemetry.claude.process.isRunning,
                    tint: .purple,
                    help: "Claude Code: \(store.telemetry.claude.process.isRunning ? "Running" : "Idle")"
                )

                // AGY
                statusDot(
                    isRunning: store.telemetry.agy.process.isRunning,
                    tint: .cyan,
                    help: "Antigravity: \(store.telemetry.agy.process.isRunning ? "Active" : "Idle")"
                )

                // Kiro
                statusDot(
                    isRunning: store.telemetry.kiro.process.isRunning,
                    tint: .green,
                    help: "Kiro: \(store.telemetry.kiro.process.isRunning ? "Active" : "Idle")"
                )

                // Local Qwen
                statusDot(
                    isRunning: store.telemetry.qwen.isServerRunning,
                    tint: .orange,
                    help: "Qwen Local: \(store.telemetry.qwen.isServerRunning ? "Server Active (:1234)" : "Stopped")"
                )
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        // Clean transparent background to let macOS render the native rounded selection highlight
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    @ViewBuilder
    private func statusDot(isRunning: Bool, tint: Color, help: String) -> some View {
        Circle()
            .fill(isRunning ? tint : Color.primary.opacity(0.22))
            .frame(width: 4.8, height: 4.8)
            .opacity(isRunning ? (isBreathing ? 1.0 : 0.65) : 0.4)
            .help(help)
    }
}
