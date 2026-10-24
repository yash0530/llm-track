import SwiftUI

public struct StatusDot: View {
    public let isRunning: Bool

    public init(isRunning: Bool) {
        self.isRunning = isRunning
    }

    public var body: some View {
        Circle()
            .fill(isRunning ? Color(red: 0.20, green: 0.84, blue: 0.45) : Color.secondary.opacity(0.38))
            .frame(width: 5.5, height: 5.5)
            .shadow(color: isRunning ? Color.green.opacity(0.35) : Color.clear, radius: 1.5)
    }
}
