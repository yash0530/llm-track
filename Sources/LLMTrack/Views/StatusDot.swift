import SwiftUI

public struct StatusDot: View {
    public let isRunning: Bool

    private static let activeGreen = Color(red: 0.20, green: 0.85, blue: 0.48)

    public init(isRunning: Bool) {
        self.isRunning = isRunning
    }

    public var body: some View {
        ZStack {
            if isRunning {
                Circle()
                    .fill(Self.activeGreen.opacity(0.24))
                    .frame(width: 10, height: 10)
            }

            Circle()
                .fill(isRunning ? Self.activeGreen : Color.primary.opacity(0.24))
                .frame(width: 6, height: 6)
        }
        .frame(width: 10, height: 10)
    }
}
