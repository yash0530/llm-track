import SwiftUI

public struct HorizontalProgressBar: View {
    public let value: Double // 0.0 to 100.0 (used percentage)
    public let tint: Color

    public init(value: Double, tint: Color) {
        self.value = max(0, min(100, value))
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4.5)

                // Fill
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geo.size.width * CGFloat(value / 100.0)), height: 4.5)
            }
        }
        .frame(height: 4.5)
    }
}
