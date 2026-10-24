import Foundation
import SwiftUI
import Combine

@MainActor
public final class LLMTrackStore: ObservableObject {
    @Published public var telemetry: LLMOverallTelemetry = LLMOverallTelemetry()
    @Published public var isRefreshing: Bool = false

    private let claudeCollector = ClaudeCollector()
    private let agyCollector = AGYCollector()
    private let kiroCollector = KiroCollector()
    private let qwenCollector = QwenCollector()

    private var timer: AnyCancellable?

    public init() {
        refresh()
        startTimer()
    }

    public func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    public func refresh() {
        isRefreshing = true

        Task.detached(priority: .userInitiated) { [claudeCollector, agyCollector, kiroCollector, qwenCollector] in
            let claude = claudeCollector.collect()
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
            self?.refresh()
        }
    }
}
