import AppKit
import Foundation
import SwiftUI

@MainActor
enum AppearanceVerifier {
    private struct Result: Codable {
        let darkCardLuminance: Double
        let darkPrimaryContrast: Double
        let darkRenderedLuminance: Double
        let darkSecondaryContrast: Double
        let darkCardOpacity: Double
        let darkPanelOpacity: Double
        let lightCardLuminance: Double
        let lightPrimaryContrast: Double
        let lightRenderedLuminance: Double
        let lightSecondaryContrast: Double
        let lightCardOpacity: Double
        let lightPanelOpacity: Double
    }

    private struct VerificationFailure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        let light = Theme.palette(for: .light)
        let dark = Theme.palette(for: .dark)

        let lightCardLuminance = relativeLuminance(light.cardBody.nsColor)
        let darkCardLuminance = relativeLuminance(dark.cardBody.nsColor)
        let lightPrimaryContrast = contrast(
            foreground: light.textPrimary.nsColor,
            background: light.cardBody.nsColor
        )
        let lightSecondaryContrast = contrast(
            foreground: light.textSecondary.nsColor,
            background: light.cardBody.nsColor
        )
        let darkPrimaryContrast = contrast(
            foreground: dark.textPrimary.nsColor,
            background: dark.cardBody.nsColor
        )
        let darkSecondaryContrast = contrast(
            foreground: dark.textSecondary.nsColor,
            background: dark.cardBody.nsColor
        )

        guard lightCardLuminance > 0.80 else {
            throw VerificationFailure(description: "light card surface is not visibly light")
        }
        guard darkCardLuminance < 0.05 else {
            throw VerificationFailure(description: "dark card surface is not visibly dark")
        }
        guard lightPrimaryContrast >= 7, darkPrimaryContrast >= 7 else {
            throw VerificationFailure(description: "primary text contrast is below 7:1")
        }
        guard lightSecondaryContrast >= 4.5, darkSecondaryContrast >= 4.5 else {
            throw VerificationFailure(description: "secondary text contrast is below 4.5:1")
        }
        guard (0.12...0.30).contains(light.panelTint.opacity),
              (0.12...0.30).contains(dark.panelTint.opacity) else {
            throw VerificationFailure(
                description: "panel tint is too opaque or too transparent for system glass"
            )
        }
        guard (0.86...0.95).contains(light.cardBody.opacity),
              (0.86...0.95).contains(dark.cardBody.opacity),
              light.cardBody.opacity - light.panelTint.opacity >= 0.45,
              dark.cardBody.opacity - dark.panelTint.opacity >= 0.45 else {
            throw VerificationFailure(
                description: "card opacity does not remain stronger than the glass panel"
            )
        }

        let hostingView = NSHostingView(rootView: AppearanceProbeView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 48, height: 48)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView

        let lightRenderedLuminance = try renderedLuminance(
            of: hostingView,
            in: window,
            appearanceName: .aqua
        )
        let darkRenderedLuminance = try renderedLuminance(
            of: hostingView,
            in: window,
            appearanceName: .darkAqua
        )

        guard lightRenderedLuminance > 0.80,
              darkRenderedLuminance < 0.05,
              lightRenderedLuminance - darkRenderedLuminance > 0.70 else {
            throw VerificationFailure(
                description: "SwiftUI host did not follow the AppKit appearance change"
            )
        }

        let result = Result(
            darkCardLuminance: darkCardLuminance,
            darkPrimaryContrast: darkPrimaryContrast,
            darkRenderedLuminance: darkRenderedLuminance,
            darkSecondaryContrast: darkSecondaryContrast,
            darkCardOpacity: dark.cardBody.opacity,
            darkPanelOpacity: dark.panelTint.opacity,
            lightCardLuminance: lightCardLuminance,
            lightPrimaryContrast: lightPrimaryContrast,
            lightRenderedLuminance: lightRenderedLuminance,
            lightSecondaryContrast: lightSecondaryContrast,
            lightCardOpacity: light.cardBody.opacity,
            lightPanelOpacity: light.panelTint.opacity
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw VerificationFailure(description: "could not encode appearance result")
        }
        print("APPEARANCE_VERIFICATION_RESULT \(json)")
    }

    private static func renderedLuminance(
        of view: NSView,
        in window: NSWindow,
        appearanceName: NSAppearance.Name
    ) throws -> Double {
        guard let appearance = NSAppearance(named: appearanceName) else {
            throw VerificationFailure(description: "missing \(appearanceName.rawValue) appearance")
        }
        window.appearance = appearance
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()

        guard let match = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
              match == appearanceName else {
            throw VerificationFailure(
                description: "view did not inherit \(appearanceName.rawValue)"
            )
        }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw VerificationFailure(description: "could not allocate appearance bitmap")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let color = bitmap.colorAt(
            x: Int(view.bounds.midX),
            y: Int(view.bounds.midY)
        ) else {
            throw VerificationFailure(description: "could not sample appearance bitmap")
        }
        return relativeLuminance(color)
    }

    private static func contrast(foreground: NSColor, background: NSColor) -> Double {
        let foregroundLuminance = relativeLuminance(
            composite(foreground: foreground, background: background)
        )
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func composite(foreground: NSColor, background: NSColor) -> NSColor {
        guard let foreground = foreground.usingColorSpace(.sRGB),
              let background = background.usingColorSpace(.sRGB) else {
            return foreground
        }
        let alpha = foreground.alphaComponent
        return NSColor(
            srgbRed: foreground.redComponent * alpha
                + background.redComponent * (1 - alpha),
            green: foreground.greenComponent * alpha
                + background.greenComponent * (1 - alpha),
            blue: foreground.blueComponent * alpha
                + background.blueComponent * (1 - alpha),
            alpha: 1
        )
    }

    private static func relativeLuminance(_ color: NSColor) -> Double {
        guard let color = color.usingColorSpace(.sRGB) else { return 0 }
        let red = linearized(Double(color.redComponent))
        let green = linearized(Double(color.greenComponent))
        let blue = linearized(Double(color.blueComponent))
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func linearized(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }
}

private struct AppearanceProbeView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Theme.palette(for: colorScheme).cardBody.swiftUIColor
    }
}
