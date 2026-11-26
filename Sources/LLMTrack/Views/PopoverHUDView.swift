import SwiftUI

public struct PopoverHUDView: View {
    @ObservedObject var store: LLMTrackStore
    @State private var spinDegrees: Double = 0.0
    @State private var isHoveringRefresh: Bool = false
    @State private var isHoveringQuit: Bool = false
    @State private var isHoveringQwen: Bool = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let emerald = Color(red: 0.20, green: 0.85, blue: 0.48)
    private static let claudeAccent = Color(red: 0.68, green: 0.42, blue: 0.98)
    private static let agyAccent = Color(red: 0.22, green: 0.60, blue: 1.00)
    private static let kiroAccent = Color(red: 0.98, green: 0.54, blue: 0.16)

    public init(store: LLMTrackStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header Bar
            HStack(spacing: 7) {
                Image(systemName: "cpu")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.78))

                Text("LLM Track")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.94))

                activeStatusPill

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        spinDegrees += 360
                    }
                    store.refresh(force: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(store.isRefreshing ? .primary : .secondary.opacity(isHoveringRefresh ? 0.95 : 0.80))
                        .rotationEffect(.degrees(spinDegrees))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(isHoveringRefresh ? 0.11 : 0.04))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(isHoveringRefresh ? 0.14 : 0.0), lineWidth: 0.5)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHoveringRefresh = hovering
                    }
                }
                .help("Refresh telemetry")
                .disabled(store.isRefreshing)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 1)

            // 1. Claude Code Card
            LiquidGlassCard(isActive: store.telemetry.claude.process.isRunning, accentColor: Self.claudeAccent) {
                VStack(spacing: 7.5) {
                    cardHeader(
                        title: "Claude Code",
                        isRunning: store.telemetry.claude.process.isRunning,
                        badgeText: store.telemetry.claude.staleLabel
                    )

                    // Session Limit (5-Hour) -> Resets in Xh Ym
                    PrecisionProgressBar(
                        label: "Session",
                        remainingPercent: store.telemetry.claude.fiveHourRemainingPct,
                        resetText: store.telemetry.claude.resetsInString,
                        baseTint: Color(red: 0.62, green: 0.36, blue: 0.96),
                        trailingTint: Color(red: 0.80, green: 0.54, blue: 1.00)
                    )

                    // Weekly Limit -> Resets in Xd Yh
                    PrecisionProgressBar(
                        label: "Weekly",
                        remainingPercent: store.telemetry.claude.sevenDayRemainingPct,
                        resetText: store.telemetry.claude.weeklyResetsInString,
                        baseTint: Color(red: 0.38, green: 0.42, blue: 0.96),
                        trailingTint: Color(red: 0.56, green: 0.62, blue: 1.00)
                    )

                    // Extra credits line
                    if let credits = store.telemetry.claude.remainingDollars {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.65))
                            Text(String(format: "$%.2f credits remaining", credits))
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(.secondary.opacity(0.80))
                            Spacer()
                        }
                        .padding(.top, 1)
                    }
                }
            }

            // 2. Antigravity Card (Consistent ordering: 5-Hour above Weekly)
            LiquidGlassCard(isActive: store.telemetry.agy.process.isRunning, accentColor: Self.agyAccent) {
                VStack(spacing: 7.5) {
                    cardHeader(
                        title: "Antigravity",
                        isRunning: store.telemetry.agy.process.isRunning
                    )

                    // 5-Hour Limit Bar -> Resets in Xh Ym
                    PrecisionProgressBar(
                        label: "5-Hour",
                        remainingPercent: store.telemetry.agy.geminiFiveHourRemainingPct,
                        resetText: store.telemetry.agy.geminiFiveHourResetString,
                        baseTint: Color(red: 0.20, green: 0.54, blue: 0.98),
                        trailingTint: Color(red: 0.38, green: 0.74, blue: 1.00)
                    )

                    // Weekly Limit Bar -> Resets in Xd Yh
                    PrecisionProgressBar(
                        label: "Weekly",
                        remainingPercent: store.telemetry.agy.geminiWeeklyRemainingPct,
                        resetText: store.telemetry.agy.geminiWeeklyResetString,
                        baseTint: Color(red: 0.12, green: 0.70, blue: 0.92),
                        trailingTint: Color(red: 0.28, green: 0.86, blue: 0.98)
                    )
                }
            }

            // 3. Kiro CLI Card
            LiquidGlassCard(isActive: store.telemetry.kiro.process.isRunning, accentColor: Self.kiroAccent) {
                VStack(spacing: 7.5) {
                    cardHeader(
                        title: "Kiro CLI",
                        isRunning: store.telemetry.kiro.process.isRunning
                    )

                    // Monthly Bar
                    PrecisionProgressBar(
                        label: "Monthly",
                        remainingPercent: store.telemetry.kiro.creditsRemainingPct,
                        resetText: store.telemetry.kiro.resetsOnString,
                        baseTint: Color(red: 0.96, green: 0.48, blue: 0.14),
                        trailingTint: Color(red: 1.00, green: 0.68, blue: 0.26)
                    )
                }
            }

            // 4. Qwen 3.8 27B Card (With On/Off toggle using llm-serve)
            LiquidGlassCard(isActive: store.telemetry.qwen.isServerRunning, accentColor: Self.emerald) {
                HStack(spacing: 6) {
                    StatusDot(isRunning: store.telemetry.qwen.isServerRunning)
                    Text("Qwen 3.8 27B")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.94))

                    Spacer()

                    qwenToggleButton
                }
            }

            // Footer
            HStack {
                Text("Checked · \(Self.timeFormatter.string(from: store.telemetry.lastUpdated))")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundColor(.secondary.opacity(0.60))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary.opacity(isHoveringQuit ? 0.95 : 0.65))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(isHoveringQuit ? 0.08 : 0.0))
                )
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHoveringQuit = hovering
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 344)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var activeStatusPill: some View {
        let count = store.telemetry.activeRunningCount
        let isAnyActive = count > 0

        HStack(spacing: 4) {
            Circle()
                .fill(isAnyActive ? Self.emerald : Color.secondary.opacity(0.45))
                .frame(width: 5, height: 5)

            Text(isAnyActive ? "\(count) Active" : "Idle")
                .font(.system(size: 10, weight: isAnyActive ? .semibold : .medium))
                .foregroundColor(isAnyActive ? Self.emerald : .secondary.opacity(0.70))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(isAnyActive ? Self.emerald.opacity(0.14) : Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule()
                .strokeBorder(isAnyActive ? Self.emerald.opacity(0.28) : Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func cardHeader(title: String, isRunning: Bool, badgeText: String? = nil) -> some View {
        HStack(spacing: 6) {
            StatusDot(isRunning: isRunning)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.primary.opacity(0.94))
                .layoutPriority(1)
            Spacer(minLength: 6)
            if let badgeText = badgeText {
                HStack(spacing: 3.5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(badgeText)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.orange.opacity(0.95))
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.14))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.orange.opacity(0.30), lineWidth: 0.5)
                )
            }
        }
    }

    @ViewBuilder
    private var qwenToggleButton: some View {
        let isTransitioning = store.qwenTransitionState != .idle

        Button(action: {
            store.toggleQwenServer()
        }) {
            HStack(spacing: 4) {
                if isTransitioning {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 9.5, weight: .bold))
                }
                Text(store.qwenButtonTitle)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(isTransitioning ? .secondary.opacity(0.85) : store.qwenButtonColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        isTransitioning
                            ? Color.primary.opacity(0.08)
                            : store.qwenButtonColor.opacity(isHoveringQwen ? 0.22 : 0.14)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isTransitioning
                            ? Color.primary.opacity(0.14)
                            : store.qwenButtonColor.opacity(isHoveringQwen ? 0.45 : 0.28),
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHoveringQwen = hovering
            }
        }
        .disabled(isTransitioning)
    }
}
