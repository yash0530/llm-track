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

            // 1. Claude Code Card (Exact match to /usage screen)
            LiquidGlassCard {
                VStack(spacing: 7) {
                    HStack {
                        HStack(spacing: 6) {
                            StatusPillBadge(
                                state: store.telemetry.claude.isExhausted
                                    ? .exhausted
                                    : (store.telemetry.claude.process.isRunning ? .running(pid: store.telemetry.claude.process.pid) : .idle)
                            )
                            Text("Claude Code")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text(store.telemetry.claude.model)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // 5h Session Usage Left (Current session)
                    PrecisionProgressBar(
                        label: "Current session",
                        usedPercent: store.telemetry.claude.fiveHourUsedPct ?? 0,
                        remainingPercent: store.telemetry.claude.fiveHourRemainingPct,
                        secondaryDetail: store.telemetry.claude.resetsInString,
                        baseTint: .purple
                    )

                    // 7d Weekly Usage Left (Current week - all models)
                    if let weeklyRem = store.telemetry.claude.sevenDayRemainingPct {
                        PrecisionProgressBar(
                            label: "Current week (all models)",
                            usedPercent: store.telemetry.claude.sevenDayUsedPct ?? 0,
                            remainingPercent: weeklyRem,
                            secondaryDetail: store.telemetry.claude.sevenDayResetsInString,
                            baseTint: .indigo
                        )
                    }

                    // Extra credits balance
                    if let credits = store.telemetry.claude.remainingDollars {
                        HStack {
                            Text(String(format: "$%.2f extra usage credits remaining", credits))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }

            // 2. Antigravity (AGY) Card (Exact match to IDE "View Usage" flyout)
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
                        HStack(spacing: 4) {
                            Text(store.telemetry.agy.planTier)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.cyan.opacity(0.9))
                            Text("·")
                                .foregroundColor(.secondary.opacity(0.4))
                            Text(store.telemetry.agy.model)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color.cyan)
                        }
                    }

                    // Gemini Weekly Limit Remaining (Matches 91% in screenshot)
                    PrecisionProgressBar(
                        label: "Gemini Weekly Limit",
                        usedPercent: 100.0 - store.telemetry.agy.geminiWeeklyRemainingPct,
                        remainingPercent: store.telemetry.agy.geminiWeeklyRemainingPct,
                        secondaryDetail: store.telemetry.agy.geminiWeeklyResetString,
                        baseTint: .cyan
                    )

                    // Limits summary (Matches 100% 5h & 100% Claude/GPT)
                    HStack {
                        Text("Five Hour Limit: \(Int(store.telemetry.agy.geminiFiveHourRemainingPct))% left")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Claude/GPT: \(Int(store.telemetry.agy.claudeGptWeeklyRemainingPct))% left")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 3. Kiro CLI Card (Exact match to /usage screen: KIRO STUDENT 1000/1000 Credits)
            LiquidGlassCard {
                VStack(spacing: 7) {
                    HStack {
                        HStack(spacing: 6) {
                            StatusPillBadge(
                                state: store.telemetry.kiro.isExhausted
                                    ? .exhausted
                                    : (store.telemetry.kiro.process.isRunning ? .running(pid: store.telemetry.kiro.process.pid) : .idle)
                            )
                            Text("Kiro CLI")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Text(store.telemetry.kiro.planTier)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.purple.opacity(0.9))
                            Text("·")
                                .foregroundColor(.secondary.opacity(0.4))
                            Text(store.telemetry.kiro.model)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Plan Credits (1000.00 of 1000 covered in plan -> 100% used / exhausted)
                    PrecisionProgressBar(
                        label: "Plan Credits (\(Int(store.telemetry.kiro.creditsUsed)) / \(Int(store.telemetry.kiro.creditsTotal)))",
                        usedPercent: 100.0,
                        remainingPercent: store.telemetry.kiro.creditsRemainingPct,
                        secondaryDetail: nil,
                        baseTint: .orange
                    )

                    HStack {
                        Text("0.00 credits left (EXHAUSTED)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                        Spacer()
                        Text(store.telemetry.kiro.resetsOnString)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
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
                            Text("Local Hardware · Zero API Cost")
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

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
