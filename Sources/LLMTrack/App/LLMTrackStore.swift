import Foundation
import SwiftUI
import Combine

@MainActor
public final class LLMTrackStore: ObservableObject {
    @Published public var telemetry: LLMOverallTelemetry = LLMOverallTelemetry()
    @Published public var isRefreshing: Bool = false
    @Published public var refreshAngle: Double = 0.0

    private let claudeCollector = ClaudeCollector()
    private let agyCollector = AGYCollector()
    private let kiroCollector = KiroCollector()
    private let qwenCollector = QwenCollector()

    private var timer: AnyCancellable?

    public init() {
        refresh(force: true)
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
        isRefreshing = true
        withAnimation(.easeInOut(duration: 0.6)) {
            refreshAngle += 360
        }

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

    public func toggleQwenServer() {
        if telemetry.qwen.isServerRunning {
            QwenCollector.stopServer()
        } else {
            QwenCollector.startServer()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refresh(force: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.refresh(force: true)
        }
    }
}
