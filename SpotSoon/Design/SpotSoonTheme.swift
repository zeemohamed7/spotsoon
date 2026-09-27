import SwiftUI
import UIKit

/// SpotSoon's semantic palette. Every token resolves from the current system
/// appearance, so views share one implementation in Light and Dark Mode.
enum SpotSoonTheme {
    static func color(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}

extension Color {
    static let spotBackground = SpotSoonTheme.color(
        light: .white,
        dark: SpotSoonTheme.rgb(14, 15, 22)
    )
    static let spotGroupedBackground = SpotSoonTheme.color(
        light: .systemGroupedBackground,
        dark: SpotSoonTheme.rgb(12, 14, 21)
    )
    static let spotSurface = SpotSoonTheme.color(
        light: .white,
        dark: SpotSoonTheme.rgb(24, 27, 36)
    )
    static let spotSurfaceElevated = SpotSoonTheme.color(
        light: .secondarySystemGroupedBackground,
        dark: SpotSoonTheme.rgb(32, 35, 48)
    )
    static let spotTextPrimary = SpotSoonTheme.color(
        light: SpotSoonTheme.rgb(18, 23, 43),
        dark: SpotSoonTheme.rgb(245, 246, 250)
    )
    static let spotTextSecondary = SpotSoonTheme.color(
        light: .secondaryLabel,
        dark: SpotSoonTheme.rgb(154, 161, 181)
    )
    static let spotTextMuted = SpotSoonTheme.color(
        light: .tertiaryLabel,
        dark: SpotSoonTheme.rgb(105, 113, 137)
    )
    static let spotBorder = SpotSoonTheme.color(
        light: UIColor.black.withAlphaComponent(0.06),
        dark: SpotSoonTheme.rgb(45, 49, 64)
    )
    static let spotAccent = SpotSoonTheme.color(
        light: SpotSoonTheme.rgb(87, 79, 245),
        dark: SpotSoonTheme.rgb(103, 99, 246)
    )
    static let spotAccentStrong = SpotSoonTheme.color(
        light: SpotSoonTheme.rgb(61, 54, 199),
        dark: SpotSoonTheme.rgb(183, 181, 255)
    )
    static let spotAccentForeground = Color.white
    static let spotAccentSoft = SpotSoonTheme.color(
        light: SpotSoonTheme.rgb(240, 240, 255),
        dark: SpotSoonTheme.rgb(35, 36, 67)
    )
    static let spotSuccess = SpotSoonTheme.color(
        light: SpotSoonTheme.rgb(24, 153, 100),
        dark: SpotSoonTheme.rgb(53, 210, 145)
    )
    static let spotWarning = SpotSoonTheme.color(
        light: SpotSoonTheme.rgb(202, 126, 0),
        dark: SpotSoonTheme.rgb(245, 190, 52)
    )
    static let spotError = SpotSoonTheme.color(
        light: .systemRed,
        dark: SpotSoonTheme.rgb(255, 103, 116)
    )
    static let spotDisabled = SpotSoonTheme.color(
        light: SpotSoonTheme.rgb(174, 177, 188),
        dark: SpotSoonTheme.rgb(73, 77, 94)
    )
    static let spotInputBackground = SpotSoonTheme.color(
        light: .secondarySystemGroupedBackground,
        dark: SpotSoonTheme.rgb(17, 20, 30)
    )
    static let spotOverlay = SpotSoonTheme.color(
        light: UIColor.black.withAlphaComponent(0.28),
        dark: UIColor.black.withAlphaComponent(0.62)
    )

}

struct SpotSoonLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 11 : 16)
                    .fill(Color.spotAccent.gradient)
                Circle()
                    .fill(Color.spotAccentForeground)
                    .padding(compact ? 8 : 12)
                Text("S")
                    .font(.system(size: compact ? 14 : 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.spotAccent)
            }
            .frame(width: compact ? 34 : 52, height: compact ? 34 : 52)
            if compact {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SPOTSOON")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color.spotAccent)
                    Text("Live Campus Map")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.spotTextPrimary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SpotSoon")
    }
}

struct SpotSoonPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.spotAccentForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                buttonColor(configuration: configuration),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .opacity(isEnabled ? 1 : 0.72)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func buttonColor(configuration: Configuration) -> Color {
        guard isEnabled else { return .spotDisabled }
        return .spotAccent.opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct SpotSoonCardModifier: ViewModifier {
    let radius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .background(
                elevated ? Color.spotSurfaceElevated : Color.spotSurface,
                in: RoundedRectangle(cornerRadius: radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.spotBorder, lineWidth: 1)
            }
    }
}

extension View {
    func spotCard(radius: CGFloat = 15, elevated: Bool = false) -> some View {
        modifier(SpotSoonCardModifier(radius: radius, elevated: elevated))
    }

    func spotScreenBackground(grouped: Bool = false) -> some View {
        background(
            (grouped ? Color.spotGroupedBackground : Color.spotBackground)
                .ignoresSafeArea()
        )
    }
}
