import SwiftUI

public struct PopoverHUDView: View {
    @ObservedObject var store: LLMTrackStore
    @State private var spinDegrees: Double = 0.0

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
                    withAnimation(.easeInOut(duration: 0.6)) {
                        spinDegrees += 360
                    }
                    store.refresh(force: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(store.isRefreshing ? .primary : .secondary.opacity(0.85))
                        .rotationEffect(.degrees(spinDegrees))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(store.isRefreshing)
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
                    }

                    // Session Limit (5-Hour) -> Resets in Xh Ym
                    PrecisionProgressBar(
                        label: "Session",
                        remainingPercent: store.telemetry.claude.fiveHourRemainingPct ?? 0,
                        resetText: store.telemetry.claude.resetsInString,
                        baseTint: Color(red: 0.65, green: 0.40, blue: 0.95)
                    )

                    // Weekly Limit -> Resets in Xd Yh
                    if let weeklyRem = store.telemetry.claude.sevenDayRemainingPct {
                        PrecisionProgressBar(
                            label: "Weekly",
                            remainingPercent: weeklyRem,
                            resetText: store.telemetry.claude.weeklyResetsInString,
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

            // 2. Antigravity Card (Consistent ordering: 5-Hour above Weekly)
            LiquidGlassCard {
                VStack(spacing: 5.5) {
                    HStack {
                        StatusDot(isRunning: store.telemetry.agy.process.isRunning)
                        Text("Antigravity")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.92))
                        Spacer()
                    }

                    // 5-Hour Limit Bar -> Resets in Xh Ym
                    PrecisionProgressBar(
                        label: "5-Hour",
                        remainingPercent: store.telemetry.agy.geminiFiveHourRemainingPct,
                        resetText: store.telemetry.agy.geminiFiveHourResetString,
                        baseTint: Color(red: 0.25, green: 0.60, blue: 1.00)
                    )

                    // Weekly Limit Bar -> Resets in Xd Yh
                    PrecisionProgressBar(
                        label: "Weekly",
                        remainingPercent: store.telemetry.agy.geminiWeeklyRemainingPct,
                        resetText: store.telemetry.agy.geminiWeeklyResetString,
                        baseTint: Color(red: 0.18, green: 0.75, blue: 0.95)
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

            // 4. Qwen 27B Card (With On/Off toggle using llm-serve)
            LiquidGlassCard {
                HStack {
                    StatusDot(isRunning: store.telemetry.qwen.isServerRunning)
                    Text("Qwen 27B")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.92))

                    Spacer()

                    Button(action: {
                        store.toggleQwenServer()
                    }) {
                        Text(store.telemetry.qwen.isServerRunning ? "Off" : "On")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(store.telemetry.qwen.isServerRunning ? Color(red: 0.92, green: 0.35, blue: 0.32) : Color(red: 0.20, green: 0.84, blue: 0.45))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
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
