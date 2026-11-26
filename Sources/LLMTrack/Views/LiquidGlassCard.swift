import SwiftUI

public struct LiquidGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let isActive: Bool
    private let accentColor: Color
    private let cornerRadius: CGFloat
    private let content: Content

    public init(
        isActive: Bool = false,
        accentColor: Color = .clear,
        cornerRadius: CGFloat = 11,
        @ViewBuilder content: () -> Content
    ) {
        self.isActive = isActive
        self.accentColor = accentColor
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    private var baseFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isActive ? 0.075 : 0.055)
        } else {
            return Color.white.opacity(isActive ? 0.72 : 0.54)
        }
    }

    private var accentOpacity: Double {
        colorScheme == .dark ? 0.06 : 0.05
    }

    private var borderGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(isActive ? 0.22 : 0.15),
                    Color.white.opacity(0.07),
                    Color.white.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.90),
                    Color.black.opacity(0.06),
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9.5)
            .background(
                ZStack {
                    shape.fill(baseFill)

                    if isActive && accentColor != .clear {
                        shape.fill(
                            LinearGradient(
                                colors: [accentColor.opacity(accentOpacity), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
            )
            .overlay(
                shape.strokeBorder(borderGradient, lineWidth: 0.75)
            )
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.18) : Color.black.opacity(0.05),
                radius: colorScheme == .dark ? 3 : 2,
                x: 0,
                y: colorScheme == .dark ? 1.5 : 1
            )
    }
}
