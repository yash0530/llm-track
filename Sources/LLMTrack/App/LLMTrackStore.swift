import Foundation
import SwiftUI
import Combine

public enum QwenTransitionState: Sendable, Equatable {
    case idle
    case turningOn
    case turningOff
}

@MainActor
public final class LLMTrackStore: ObservableObject {
    @Published public var telemetry: LLMOverallTelemetry
    @Published public var isRefreshing: Bool = false
    @Published public var qwenTransitionState: QwenTransitionState = .idle

    private let claudeCollector = ClaudeCollector()
    private let agyCollector = AGYCollector()
    private let kiroCollector = KiroCollector()
    private let qwenCollector = QwenCollector()

    private var timer: AnyCancellable?

    public init() {
        // Fast synchronous initial collect so telemetry is fully populated on load with zero glitch
        let claude = claudeCollector.collect(forceLive: false)
        let agy = agyCollector.collect()
        let kiro = kiroCollector.collect()
        let qwen = qwenCollector.collect()

        self.telemetry = LLMOverallTelemetry(
            claude: claude,
            agy: agy,
            kiro: kiro,
            qwen: qwen,
            lastUpdated: Date()
        )

        startTimer()
    }

    public func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 8.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh(force: false)
            }
    }

    public func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task.detached(priority: .userInitiated) { [claudeCollector, agyCollector, kiroCollector, qwenCollector] in
            let claude = claudeCollector.collect(forceLive: force)
            let agy = agyCollector.collect()
            let kiro = kiroCollector.collect()
            let qwen = qwenCollector.collect()

            let updated = LLMOverallTelemetry(
                claude: claude,
                agy: agy,
                kiro: kiro,
                qwen: qwen,
                lastUpdated: Date()
            )

            await MainActor.run {
                self.telemetry = updated
                self.isRefreshing = false
            }
        }
    }

    public var qwenButtonTitle: String {
        switch qwenTransitionState {
        case .turningOn:
            return "Turning on..."
        case .turningOff:
            return "Turning off..."
        case .idle:
            return telemetry.qwen.isServerRunning ? "Off" : "On"
        }
    }

    public var qwenButtonColor: Color {
        switch qwenTransitionState {
        case .turningOn, .turningOff:
            return Color.secondary.opacity(0.70)
        case .idle:
            return telemetry.qwen.isServerRunning
                ? Color(red: 0.92, green: 0.35, blue: 0.32)
                : Color(red: 0.20, green: 0.84, blue: 0.45)
        }
    }

    public func toggleQwenServer() {
        guard qwenTransitionState == .idle else { return }

        let willStart = !telemetry.qwen.isServerRunning
        qwenTransitionState = willStart ? .turningOn : .turningOff

        Task.detached(priority: .userInitiated) { [weak self, qwenCollector] in
            if willStart {
                QwenCollector.startServerSync()
            } else {
                QwenCollector.stopServerSync()
            }

            // Verify with retries (polling every 500ms for up to 4s)
            var newStatus = qwenCollector.collect()
            let expectedRunning = willStart
            for _ in 0..<8 {
                if newStatus.isServerRunning == expectedRunning {
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                newStatus = qwenCollector.collect()
            }

            let finalStatus = newStatus
            await MainActor.run { [weak self] in
                self?.telemetry.qwen = finalStatus
                self?.qwenTransitionState = .idle
            }
        }
    }
}
