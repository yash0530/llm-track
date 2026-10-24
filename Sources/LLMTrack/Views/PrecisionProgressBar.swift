import SwiftUI

public struct PrecisionProgressBar: View {
    public let label: String
    public let remainingPercent: Double
    public let resetText: String?
    public let baseTint: Color

    public init(
        label: String,
        remainingPercent: Double,
        resetText: String? = nil,
        baseTint: Color = .blue
    ) {
        self.label = label
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetText = resetText
        self.baseTint = baseTint
    }

    private var percentTextColor: Color {
        if remainingPercent <= 0.001 {
            return Color(red: 0.92, green: 0.32, blue: 0.28)
        } else if remainingPercent < 20.0 {
            return Color.orange
        }
        return Color.primary.opacity(0.90)
    }

    private var barGradient: LinearGradient {
        if remainingPercent <= 0.001 {
            return LinearGradient(
                colors: [Color.red.opacity(0.6), Color.red],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if remainingPercent < 20.0 {
            return LinearGradient(
                colors: [Color.orange.opacity(0.85), Color.orange],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [baseTint.opacity(0.75), baseTint],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.75))

                Spacer()

                HStack(spacing: 3.5) {
                    Text(String(format: "%.0f%% left", remainingPercent))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(percentTextColor)

                    if let reset = resetText, !reset.isEmpty {
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.35))

                        Text(reset)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.secondary.opacity(0.60))
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 3.5)

                    if remainingPercent > 0.001 {
                        Capsule()
                            .fill(barGradient)
                            .frame(width: max(3.5, geo.size.width * CGFloat(remainingPercent / 100.0)), height: 3.5)
                    }
                }
            }
            .frame(height: 3.5)
        }
    }
}
