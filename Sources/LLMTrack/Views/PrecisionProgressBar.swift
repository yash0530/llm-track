import SwiftUI

public struct PrecisionProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme

    public let label: String
    public let remainingPercent: Double
    /// False when usage is unknown (e.g. window reset but no fresh data yet): renders "—" and an empty bar.
    public let isKnown: Bool
    public let resetText: String?
    public let baseTint: Color
    public let trailingTint: Color?

    private static let exhaustedColor = Color(red: 0.96, green: 0.36, blue: 0.34)
    private static let lowTextColor = Color(red: 0.98, green: 0.64, blue: 0.18)
    private static let lowGradientStart = Color(red: 0.96, green: 0.50, blue: 0.14)
    private static let lowGradientEnd = Color(red: 1.00, green: 0.70, blue: 0.24)

    public init(
        label: String,
        remainingPercent: Double?,
        resetText: String? = nil,
        baseTint: Color = .blue,
        trailingTint: Color? = nil
    ) {
        self.label = label
        self.isKnown = remainingPercent != nil
        self.remainingPercent = max(0, min(100, remainingPercent ?? 0))
        self.resetText = resetText
        self.baseTint = baseTint
        self.trailingTint = trailingTint
    }

    private var isExhausted: Bool {
        isKnown && remainingPercent <= 0.001
    }

    private var isLow: Bool {
        isKnown && !isExhausted && remainingPercent < 20.0
    }

    private var percentTextColor: Color {
        if !isKnown {
            return Color.secondary.opacity(0.55)
        }
        if isExhausted {
            return Self.exhaustedColor
        } else if isLow {
            return Self.lowTextColor
        }
        return Color.primary.opacity(0.92)
    }

    private var trackFill: Color {
        if isExhausted {
            return Self.exhaustedColor.opacity(colorScheme == .dark ? 0.16 : 0.12)
        }
        return colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.085)
    }

    private var trackStroke: Color {
        if isExhausted {
            return Self.exhaustedColor.opacity(0.28)
        }
        return Color.primary.opacity(0.06)
    }

    private var barGradient: LinearGradient {
        if isLow {
            return LinearGradient(
                colors: [Self.lowGradientStart, Self.lowGradientEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [baseTint, trailingTint ?? baseTint],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var glowColor: Color {
        isLow ? Self.lowGradientEnd : (trailingTint ?? baseTint)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4.5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.85))

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text(isKnown ? String(format: "%.0f%% left", remainingPercent) : "— left")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(percentTextColor)

                    if let reset = resetText, !reset.isEmpty {
                        Text("·")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.35))

                        Text(reset)
                            .font(.system(size: 10.5, weight: .regular))
                            .monospacedDigit()
                            .foregroundColor(.secondary.opacity(0.72))
                            .lineLimit(1)
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackFill)
                        .overlay(
                            Capsule()
                                .strokeBorder(trackStroke, lineWidth: 0.5)
                        )
                        .frame(height: 5.5)

                    if isKnown && remainingPercent > 0.001 {
                        Capsule()
                            .fill(barGradient)
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.30), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            )
                            .shadow(
                                color: colorScheme == .dark ? glowColor.opacity(0.35) : .clear,
                                radius: 3,
                                x: 0,
                                y: 0
                            )
                            .frame(width: max(5.5, geo.size.width * CGFloat(remainingPercent / 100.0)), height: 5.5)
                            .animation(.easeInOut(duration: 0.35), value: remainingPercent)
                    }
                }
            }
            .frame(height: 5.5)
        }
    }
}
