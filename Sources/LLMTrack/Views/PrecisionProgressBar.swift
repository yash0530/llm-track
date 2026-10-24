import SwiftUI

public struct PrecisionProgressBar: View {
    public let label: String
    public let usedPercent: Double
    public let remainingPercent: Double?
    public let secondaryDetail: String?
    public let baseTint: Color

    public init(
        label: String,
        usedPercent: Double,
        remainingPercent: Double? = nil,
        secondaryDetail: String? = nil,
        baseTint: Color = .blue
    ) {
        self.label = label
        self.usedPercent = max(0, min(100, usedPercent))
        self.remainingPercent = remainingPercent
        self.secondaryDetail = secondaryDetail
        self.baseTint = baseTint
    }

    private var isExhausted: Bool {
        if let rem = remainingPercent {
            return rem <= 0.0
        }
        return usedPercent >= 100.0
    }

    private var dynamicTint: Color {
        if isExhausted {
            return .red
        }
        if let rem = remainingPercent {
            if rem < 20.0 { return .orange }
        }
        return baseTint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    if isExhausted {
                        Text("0% left (EXHAUSTED)")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.red)
                    } else if let rem = remainingPercent {
                        Text(String(format: "%.0f%% left", rem))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    } else {
                        Text(String(format: "%.0f%% used", usedPercent))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    }

                    if let detail = secondaryDetail {
                        Text("(\(detail))")
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4.5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [dynamicTint.opacity(0.85), dynamicTint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * CGFloat(usedPercent / 100.0)), height: 4.5)
                }
            }
            .frame(height: 4.5)
        }
    }
}
