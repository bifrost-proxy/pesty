import AppKit
import SwiftUI

struct ThemeColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(opacity)
        )
    }
}

struct ThemePalette: Sendable {
    let panelTint: ThemeColor
    let cardBody: ThemeColor
    let cardBorder: ThemeColor
    let selection: ThemeColor
    let textPrimary: ThemeColor
    let textSecondary: ThemeColor
    let textTertiary: ThemeColor
    let fieldBackground: ThemeColor
    let pillBackground: ThemeColor
    let pillSelected: ThemeColor
}

enum Theme {
    static let cardWidth: CGFloat = 215
    static let cardSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 16
    static let cardCorner: CGFloat = 13
    static let headerHeight: CGFloat = 54

    static let headerText = Color.white
    static let headerSubText = Color.white.opacity(0.78)

    static func palette(for colorScheme: ColorScheme) -> ThemePalette {
        switch colorScheme {
        case .light:
            return ThemePalette(
                panelTint: color(0xF4F5F7, opacity: 0.72),
                cardBody: color(0xF8F8FA, opacity: 0.98),
                cardBorder: color(0x000000, opacity: 0.12),
                selection: color(0x1677E8),
                textPrimary: color(0x202124),
                textSecondary: color(0x5F6368),
                textTertiary: color(0x888B90),
                fieldBackground: color(0x000000, opacity: 0.06),
                pillBackground: color(0x000000, opacity: 0.07),
                pillSelected: color(0x000000, opacity: 0.12)
            )
        case .dark:
            return ThemePalette(
                panelTint: color(0x000000, opacity: 0.34),
                cardBody: color(0x1C1C1F),
                cardBorder: color(0xFFFFFF, opacity: 0.07),
                selection: color(0x338CFF),
                textPrimary: color(0xF4F4F5),
                textSecondary: color(0xA3A3A8),
                textTertiary: color(0x707075),
                fieldBackground: color(0xFFFFFF, opacity: 0.09),
                pillBackground: color(0xFFFFFF, opacity: 0.10),
                pillSelected: color(0xFFFFFF, opacity: 0.18)
            )
        @unknown default:
            return palette(for: .light)
        }
    }

    private static func color(_ rgb: UInt32, opacity: Double = 1) -> ThemeColor {
        ThemeColor(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Date {
    var clipRelative: String {
        let secs = -timeIntervalSinceNow
        switch secs {
        case ..<5:        return L10n.now
        case ..<60:       return "\(Int(secs))s"
        case ..<3600:     return "\(Int(secs / 60))m"
        case ..<86_400:   return "\(Int(secs / 3600))h"
        case ..<604_800:  return "\(Int(secs / 86_400))d"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: self)
        }
    }

    var clipRelativeLong: String {
        let secs = -timeIntervalSinceNow
        if secs < 8 { return L10n.justNow }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = Locale(identifier: L10n.localeIdentifier)
        return f.localizedString(for: self, relativeTo: Date())
    }
}
