import SwiftUI

public struct PopoverHUDView: View {
    @ObservedObject var store: LLMTrackStore

    public init(store: LLMTrackStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Header Bar
            HStack {
                HStack(spacing: 5) {
                    Text("LLM TRACK")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.primary.opacity(0.85))

                    Text("·")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.40))

                    Text("\(store.telemetry.activeRunningCount) Active")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(store.telemetry.activeRunningCount > 0 ? Color(red: 0.20, green: 0.84, blue: 0.45) : Color.secondary.opacity(0.60))
                }

                Spacer()

                Button(action: {
                    store.refresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.75))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 1)

            Divider()
                .opacity(0.10)

            // 1. Claude Code Card
            LiquidGlassCard {
                VStack(spacing: 5.5) {
                    HStack {
                        StatusDot(isRunning: store.telemetry.claude.process.isRunning)
                        Text("Claude Code")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.92))
                        Spacer()
                        Text(store.telemetry.claude.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.70))
                    }

                    // Session Limit
                    PrecisionProgressBar(
                        label: "Session",
                        remainingPercent: store.telemetry.claude.fiveHourRemainingPct ?? 0,
                        resetText: store.telemetry.claude.resetsInString,
                        baseTint: Color(red: 0.65, green: 0.40, blue: 0.95)
                    )

                    // Weekly Limit
                    if let weeklyRem = store.telemetry.claude.sevenDayRemainingPct {
                        PrecisionProgressBar(
                            label: "Weekly",
                            remainingPercent: weeklyRem,
                            resetText: store.telemetry.claude.sevenDayResetsInString,
                            baseTint: Color(red: 0.38, green: 0.42, blue: 0.95)
                        )
                    }

                    // Extra credits line
                    if let credits = store.telemetry.claude.remainingDollars {
                        HStack {
                            Text(String(format: "$%.2f credits remaining", credits))
                                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(.secondary.opacity(0.75))
                            Spacer()
                        }
                        .padding(.top, 1)
                    }
                }
            }

            // 2. Antigravity Card
            LiquidGlassCard {
                VStack(spacing: 5.5) {
                    HStack {
                        StatusDot(isRunning: store.telemetry.agy.process.isRunning)
                        Text("Antigravity")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.92))
                        Spacer()
                        Text(store.telemetry.agy.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.70))
                    }

                    // Weekly Limit Bar
                    PrecisionProgressBar(
                        label: "Weekly",
                        remainingPercent: store.telemetry.agy.geminiWeeklyRemainingPct,
                        resetText: store.telemetry.agy.geminiWeeklyResetString,
                        baseTint: Color(red: 0.18, green: 0.75, blue: 0.95)
                    )

                    // 5-Hour Limit Bar
                    PrecisionProgressBar(
                        label: "5-Hour",
                        remainingPercent: store.telemetry.agy.geminiFiveHourRemainingPct,
                        resetText: nil,
                        baseTint: Color(red: 0.25, green: 0.60, blue: 1.00)
                    )
                }
            }

            // 3. Kiro CLI Card
            LiquidGlassCard {
                VStack(spacing: 5.5) {
                    HStack {
                        StatusDot(isRunning: store.telemetry.kiro.process.isRunning)
                        Text("Kiro CLI")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.92))
                        Spacer()
                        Text(store.telemetry.kiro.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.70))
                    }

                    // Monthly Bar
                    PrecisionProgressBar(
                        label: "Monthly",
                        remainingPercent: store.telemetry.kiro.creditsRemainingPct,
                        resetText: store.telemetry.kiro.resetsOnString,
                        baseTint: Color(red: 0.98, green: 0.55, blue: 0.15)
                    )
                }
            }

            // 4. Qwen 27B Card (Ultra-clean single row)
            LiquidGlassCard {
                HStack {
                    StatusDot(isRunning: store.telemetry.qwen.isServerRunning)
                    Text("Qwen 27B")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.92))
                    Spacer()
                }
                .padding(.vertical, 1)
            }

            // Footer
            HStack {
                Text("Live · \(timeString(store.telemetry.lastUpdated))")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary.opacity(0.50))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 9.5))
                .foregroundColor(.secondary.opacity(0.70))
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 2)
            .padding(.top, 1)
        }
        .padding(10)
        .frame(width: 336)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(0.35)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
        )
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
