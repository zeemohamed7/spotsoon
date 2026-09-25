import SwiftUI

extension Color {
    static let spotPurple = Color(red: 0.34, green: 0.31, blue: 0.96)
    static let spotPurpleDark = Color(red: 0.24, green: 0.21, blue: 0.78)
    static let spotLavender = Color(red: 0.94, green: 0.94, blue: 1.0)
    static let spotInk = Color(red: 0.07, green: 0.09, blue: 0.17)
}

struct SpotSoonLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: "parkingsign.circle.fill")
                .font(.system(size: compact ? 18 : 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: compact ? 34 : 52, height: compact ? 34 : 52)
                .background(Color.spotPurple.gradient, in: RoundedRectangle(cornerRadius: compact ? 11 : 16))
            if compact {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SPOTSOON")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color.spotPurple)
                    Text("Live Campus Map")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.spotInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SpotSoon")
    }
}

struct SpotSoonPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Color.spotPurple.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
