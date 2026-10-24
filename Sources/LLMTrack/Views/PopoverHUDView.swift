import SwiftUI

public struct PopoverHUDView: View {
    @ObservedObject var store: LLMTrackStore

    public init(store: LLMTrackStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Text("LLM TRACK")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.9))

                    Text("/")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.25))

                    Text("\(store.telemetry.activeRunningCount) Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(store.telemetry.activeRunningCount > 0 ? Color.green : Color.white.opacity(0.5))
                }

                Spacer()

                Button(action: {
                    store.refresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(store.isRefreshing ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 2)

            Divider()
                .background(Color.white.opacity(0.08))

            // 1. Claude Code Card
            serviceCard {
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.telemetry.claude.process.isRunning ? Color.green : Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                            Text("Claude Code")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            if let pid = store.telemetry.claude.process.pid {
                                Text("PID \(pid)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        Spacer()
                        Text(store.telemetry.claude.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // 5h Session
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("5h Session")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            if let rem = store.telemetry.claude.fiveHourRemainingPct {
                                Text(String(format: "%.0f%% remaining", rem))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                                if let resetsIn = store.telemetry.claude.resetsInString {
                                    Text("(\(resetsIn))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            } else {
                                Text("No limit active")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        HorizontalProgressBar(
                            value: store.telemetry.claude.fiveHourUsedPct ?? 0,
                            tint: (store.telemetry.claude.fiveHourRemainingPct ?? 100) < 30 ? Color.orange : Color.purple
                        )
                    }

                    // 7d Weekly
                    if let weeklyRem = store.telemetry.claude.sevenDayRemainingPct {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("7d Weekly")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Text(String(format: "%.0f%% remaining", weeklyRem))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            HorizontalProgressBar(
                                value: store.telemetry.claude.sevenDayUsedPct ?? 0,
                                tint: Color.indigo.opacity(0.85)
                            )
                        }
                    }
                }
            }

            // 2. Antigravity (AGY) Card
            serviceCard {
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.telemetry.agy.process.isRunning ? Color.green : Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                            Text("Antigravity (AGY)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            if let pid = store.telemetry.agy.process.pid {
                                Text("PID \(pid)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        Spacer()
                        Text(store.telemetry.agy.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.cyan.opacity(0.9))
                    }

                    // Context Window
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Context Window")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            let rem = store.telemetry.agy.contextRemainingPct ?? 82.0
                            let used = store.telemetry.agy.contextUsedPct ?? 18.0
                            Text(String(format: "%.0f%% remaining", rem))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                            Text(String(format: "(%.0f%% used)", used))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        HorizontalProgressBar(
                            value: store.telemetry.agy.contextUsedPct ?? 18.0,
                            tint: Color.cyan.opacity(0.85)
                        )
                    }

                    // Daily Requests
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Daily Requests")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            let dailyRem = store.telemetry.agy.dailyRequestsRemainingPct ?? 65.0
                            Text(String(format: "%.0f%% remaining", dailyRem))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        HorizontalProgressBar(
                            value: store.telemetry.agy.dailyRequestsUsedPct ?? 35.0,
                            tint: Color.blue.opacity(0.8)
                        )
                    }
                }
            }

            // 3. Kiro CLI Card
            serviceCard {
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.telemetry.kiro.process.isRunning ? Color.yellow : Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                            Text("Kiro CLI")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            if let pid = store.telemetry.kiro.process.pid {
                                Text("PID \(pid)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        Spacer()
                        Text(store.telemetry.kiro.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    // Context Window
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Context Window")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            let rem = store.telemetry.kiro.contextRemainingPct ?? 84.5
                            let used = store.telemetry.kiro.contextUsedPct ?? 15.5
                            Text(String(format: "%.1f%% remaining", rem))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                            Text(String(format: "(%.1f%% used)", used))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        HorizontalProgressBar(
                            value: store.telemetry.kiro.contextUsedPct ?? 15.5,
                            tint: Color.green.opacity(0.85)
                        )
                    }
                }
            }

            // 4. Local Qwen (LM Studio) Card
            serviceCard {
                VStack(spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.telemetry.qwen.isServerRunning ? Color.green : Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                            Text("Qwen 27B")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Local LM Studio")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        Spacer()
                        Text("Metal · \(store.telemetry.qwen.diskSize)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }

                    HStack {
                        Text("Server:")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))

                        Text(store.telemetry.qwen.isServerRunning ? "Running (:1234)" : "Stopped")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(store.telemetry.qwen.isServerRunning ? Color.green : Color.white.opacity(0.7))

                        Spacer()

                        Button(action: {
                            store.toggleQwenServer()
                        }) {
                            Text(store.telemetry.qwen.isServerRunning ? "Stop Server" : "Start Server (lms)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            // Footer (Clean, No URLs)
            HStack {
                Text("Updated \(timeString(store.telemetry.lastUpdated))")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 350)
        .background(
            ZStack {
                Color(red: 16/255, green: 18/255, blue: 24/255).opacity(0.92)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        )
    }

    private func serviceCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
                    )
            )
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
