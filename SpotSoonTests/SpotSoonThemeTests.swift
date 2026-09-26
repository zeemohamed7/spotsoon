import SwiftUI
import UIKit
import XCTest
@testable import SpotSoon

final class SpotSoonThemeTests: XCTestCase {
    func testSemanticPaletteRespondsToSystemAppearance() {
        XCTAssertNotEqual(
            resolvedComponents(.spotBackground, style: .light),
            resolvedComponents(.spotBackground, style: .dark)
        )
        XCTAssertNotEqual(
            resolvedComponents(.spotTextPrimary, style: .light),
            resolvedComponents(.spotTextPrimary, style: .dark)
        )
        XCTAssertNotEqual(
            resolvedComponents(.spotSurface, style: .light),
            resolvedComponents(.spotSurface, style: .dark)
        )
    }

    func testPrimaryTextHasReadableContrastInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let text = resolvedUIColor(.spotTextPrimary, style: style)
            let background = resolvedUIColor(.spotBackground, style: style)
            XCTAssertGreaterThanOrEqual(
                contrastRatio(text, background),
                7,
                "Primary text should remain readable in \(style == .dark ? "Dark" : "Light") Mode"
            )
        }
    }

    private func resolvedComponents(_ color: Color, style: UIUserInterfaceStyle) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolvedUIColor(color, style: style).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }

    private func resolvedUIColor(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func contrastRatio(_ foreground: UIColor, _ background: UIColor) -> CGFloat {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}
