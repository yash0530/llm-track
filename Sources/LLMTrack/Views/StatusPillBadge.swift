import SwiftUI

public enum ServiceExecutionState: Equatable {
    case running(pid: Int?)
    case idle
    case serverActive(port: Int)
    case stopped
    case exhausted
}

public struct StatusPillBadge: View {
    public let state: ServiceExecutionState

    public init(state: ServiceExecutionState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 4.5, height: 4.5)

            Text(titleText)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.3)
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private var titleText: String {
        switch state {
        case .running(let pid):
            return pid != nil ? "RUNNING :\(pid!)" : "RUNNING"
        case .idle:
            return "IDLE"
        case .serverActive(let port):
            return ":\(port) ACTIVE"
        case .stopped:
            return "STOPPED"
        case .exhausted:
            return "EXHAUSTED"
        }
    }

    private var dotColor: Color {
        switch state {
        case .running, .serverActive: return .green
        case .idle: return .secondary
        case .stopped: return .secondary.opacity(0.4)
        case .exhausted: return .red
        }
    }

    private var textColor: Color {
        switch state {
        case .running, .serverActive: return .green
        case .idle: return .secondary
        case .stopped: return .secondary.opacity(0.8)
        case .exhausted: return .red
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .running, .serverActive: return Color.green.opacity(0.12)
        case .idle: return Color.primary.opacity(0.04)
        case .stopped: return Color.primary.opacity(0.03)
        case .exhausted: return Color.red.opacity(0.15)
        }
    }

    private var borderColor: Color {
        switch state {
        case .running, .serverActive: return Color.green.opacity(0.28)
        case .idle: return Color.primary.opacity(0.08)
        case .stopped: return Color.primary.opacity(0.06)
        case .exhausted: return Color.red.opacity(0.35)
        }
    }
}
