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

private enum ClipDateFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
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
                panelTint: color(0xDDEBFF, opacity: 0.015),
                cardBody: color(0xF5F9FF, opacity: 0.84),
                cardBorder: color(0xFFFFFF, opacity: 0.72),
                selection: color(0x1677E8),
                textPrimary: color(0x202124),
                textSecondary: color(0x5F6368),
                textTertiary: color(0x888B90),
                fieldBackground: color(0xFFFFFF, opacity: 0.24),
                pillBackground: color(0xFFFFFF, opacity: 0.22),
                pillSelected: color(0xFFFFFF, opacity: 0.42)
            )
        case .dark:
            return ThemePalette(
                panelTint: color(0x071526, opacity: 0.025),
                cardBody: color(0x111A27, opacity: 0.86),
                cardBorder: color(0xFFFFFF, opacity: 0.18),
                selection: color(0x338CFF),
                textPrimary: color(0xF4F4F5),
                textSecondary: color(0xA3A3A8),
                textTertiary: color(0x707075),
                fieldBackground: color(0xFFFFFF, opacity: 0.09),
                pillBackground: color(0xFFFFFF, opacity: 0.09),
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
            return ClipDateFormatters.monthDay.string(from: self)
        }
    }

    var clipRelativeLong: String {
        let secs = -timeIntervalSinceNow
        if secs < 8 { return L10n.justNow }
        let formatter = ClipDateFormatters.relative
        formatter.locale = Locale(identifier: L10n.localeIdentifier)
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
