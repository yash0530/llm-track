import SwiftUI

public struct MenuBarTileView: View {
    @ObservedObject var store: LLMTrackStore

    public init(store: LLMTrackStore) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 5) {
            // Anchor Symbol (Solid, static, no jitter)
            Image(systemName: "cpu")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))

            // 4 Static Status Dots (Claude, AGY, Kiro, Local Qwen)
            HStack(spacing: 3.5) {
                // Claude (Red if exhausted, purple if running, muted if idle)
                Circle()
                    .fill(claudeDotColor)
                    .frame(width: 4.8, height: 4.8)

                // AGY (Cyan if running)
                Circle()
                    .fill(store.telemetry.agy.process.isRunning ? Color.cyan : Color.primary.opacity(0.20))
                    .frame(width: 4.8, height: 4.8)

                // Kiro (Green if running)
                Circle()
                    .fill(store.telemetry.kiro.process.isRunning ? Color.green : Color.primary.opacity(0.20))
                    .frame(width: 4.8, height: 4.8)

                // Local Qwen (Orange if server running)
                Circle()
                    .fill(store.telemetry.qwen.isServerRunning ? Color.orange : Color.primary.opacity(0.20))
                    .frame(width: 4.8, height: 4.8)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: 52, height: 22)
    }

    private var claudeDotColor: Color {
        if !store.telemetry.claude.process.isRunning {
            return Color.primary.opacity(0.20)
        }
        if let rem = store.telemetry.claude.fiveHourRemainingPct, rem <= 0 {
            return Color.red // Warning: Exhausted!
        }
        return Color.purple
    }
}
