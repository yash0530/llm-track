import SwiftUI

public struct PopoverHUDView: View {
    @ObservedObject var store: LLMTrackStore

    public init(store: LLMTrackStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 8.5) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Text("LLM TRACK")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.primary.opacity(0.9))

                    Text("/")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("\(store.telemetry.activeRunningCount) Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(store.telemetry.activeRunningCount > 0 ? Color.green : Color.secondary)
                }

                Spacer()

                Button(action: {
                    store.refresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 1)

            Divider()
                .opacity(0.12)

            // 1. Claude Code Card (Real-Time Live OAuth Rate Limits)
            LiquidGlassCard {
                VStack(spacing: 7) {
                    HStack {
                        HStack(spacing: 6) {
                            StatusPillBadge(
                                state: isClaudeExhausted
                                    ? .exhausted
                                    : (store.telemetry.claude.process.isRunning ? .running(pid: store.telemetry.claude.process.pid) : .idle)
                            )
                            Text("Claude Code")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text(store.telemetry.claude.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // 5h Session Usage Left (Accurately detects 0% exhausted)
                    PrecisionProgressBar(
                        label: "5h Session Limit",
                        usedPercent: store.telemetry.claude.fiveHourUsedPct ?? 0,
                        remainingPercent: store.telemetry.claude.fiveHourRemainingPct,
                        secondaryDetail: store.telemetry.claude.resetsInString,
                        baseTint: .purple
                    )

                    // 7d Weekly Usage Left
                    if let weeklyRem = store.telemetry.claude.sevenDayRemainingPct {
                        PrecisionProgressBar(
                            label: "7d Weekly Quota",
                            usedPercent: store.telemetry.claude.sevenDayUsedPct ?? 0,
                            remainingPercent: weeklyRem,
                            baseTint: .indigo
                        )
                    }

                    // Extra credits & Lifetime count
                    HStack {
                        if let credits = store.telemetry.claude.remainingDollars {
                            Text(String(format: "$%.2f credits available", credits))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let msgs = store.telemetry.claude.lifetimeMessages {
                            Text("\(msgs) lifetime msgs")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }
            }

            // 2. Antigravity (AGY) Card (Account & Plan Quota)
            LiquidGlassCard {
                VStack(spacing: 7) {
                    HStack {
                        HStack(spacing: 6) {
                            StatusPillBadge(
                                state: store.telemetry.agy.process.isRunning
                                    ? .running(pid: store.telemetry.agy.process.pid)
                                    : .idle
                            )
                            Text("Antigravity")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text(store.telemetry.agy.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.cyan)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account Quota")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Active / Unlimited Plan")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Current Session")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            if let steps = store.telemetry.agy.sessionSteps {
                                Text("\(steps) steps executed")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                    }

                    if let acct = store.telemetry.agy.account {
                        HStack {
                            Spacer()
                            Text(acct)
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }
                }
            }

            // 3. Kiro CLI Card
            LiquidGlassCard {
                VStack(spacing: 7) {
                    HStack {
                        HStack(spacing: 6) {
                            StatusPillBadge(
                                state: store.telemetry.kiro.process.isRunning
                                    ? .running(pid: store.telemetry.kiro.process.pid)
                                    : .idle
                            )
                            Text("Kiro CLI")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text(store.telemetry.kiro.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plan Quota")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("AWS Social / Individual")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        if let acct = store.telemetry.kiro.account {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("User")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(acct)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }

            // 4. Local Qwen (LM Studio) Card
            LiquidGlassCard {
                VStack(spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            StatusPillBadge(
                                state: store.telemetry.qwen.isServerRunning
                                    ? .serverActive(port: store.telemetry.qwen.serverPort)
                                    : .stopped
                            )
                            Text("Qwen 27B")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text("Metal · \(store.telemetry.qwen.diskSize)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Hardware Limit")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("100% Free / Unlimited")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        Button(action: {
                            store.toggleQwenServer()
                        }) {
                            Text(store.telemetry.qwen.isServerRunning ? "Stop Server" : "Start Server (lms)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            // Clean Footer
            HStack {
                Text("Live Telemetry · \(timeString(store.telemetry.lastUpdated))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 1)
        }
        .padding(11)
        .frame(width: 352)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(0.4)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.05),
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

    private var isClaudeExhausted: Bool {
        if let rem = store.telemetry.claude.fiveHourRemainingPct {
            return rem <= 0.0
        }
        return false
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
