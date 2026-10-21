//
//  Theme.swift
//  matchday
//
//  Colors and type of the panel (`root.fg`, `dim`, `faint`, `urgent`, `win`
//  in Panel.qml). Dark mode follows the original navy palette; light mode is
//  a legible equivalent. The accent is the system accent color.
//

import AppKit
import SwiftUI

enum Theme {
    // MARK: Colors

    static let backgroundRGB = (light: UInt32(0xF5F7FA), dark: UInt32(0x0D1724))
    static let foregroundRGB = (light: UInt32(0x1A2433), dark: UInt32(0xD9DFE8))
    static let background = adaptive(light: backgroundRGB.light, dark: backgroundRGB.dark)
    static let foreground = adaptive(light: foregroundRGB.light, dark: foregroundRGB.dark)
    static let dimOpacity = 0.58
    /// Secondary text.
    static let dim = foreground.opacity(dimOpacity)
    /// Hairlines and card borders.
    static let faint = foreground.opacity(0.14)
    /// Card and chip fill.
    static let fill = foreground.opacity(0.04)
    static let hover = foreground.opacity(0.08)
    /// Live matches, losses, red cards.
    static let urgent = adaptive(light: 0xD93636, dark: 0xF0524F)
    /// Wins, free services, confirmed listings.
    static let win = adaptive(light: 0x2E9E4F, dark: 0x3FBF5F)
    static let accent = Color.accentColor

    // MARK: Metrics

    static let cornerRadius: CGFloat = 8
    static let panelWidth: CGFloat = 540
    static let panelHeight: CGFloat = 720

    // MARK: Type

    /// System font (SF Pro) with tabular digits so scores, times and table columns line up.
    static func font(_ size: Size, weight: Font.Weight = .regular) -> Font {
        .system(size: size.rawValue, weight: weight).monospacedDigit()
    }

    enum Size: CGFloat {
        case caption = 10.5
        case small = 11.5
        case body = 13
        case title = 14.5
        case heading = 17
        case display = 22
    }

    // MARK: Helpers

    /// A color that resolves per appearance.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(rgb: isDark(appearance) ? dark : light)
        })
    }

    enum Fallback {
        /// Secondary text color (zone colors).
        case dim
        /// Accent color (team colors).
        case accent
    }

    /// An ESPN color that still reads on the panel, else `fallback`
    /// (`readable` in Panel.qml: ESPN often says white or black). Resolved per
    /// appearance, since a color can vanish on one background only.
    static func readable(hex: String, fallback: Fallback) -> Color {
        let rgb = ColorContrast.rgb(hex: hex)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = isDark(appearance)
            let background = dark ? backgroundRGB.dark : backgroundRGB.light
            if let rgb, ColorContrast.isReadable(rgb, on: background) { return NSColor(rgb: rgb) }
            switch fallback {
            case .dim:
                return NSColor(rgb: dark ? foregroundRGB.dark : foregroundRGB.light, alpha: dimOpacity)
            case .accent:
                return .controlAccentColor
            }
        })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Color math shared by the views (`luminance` / `readable` in Panel.qml).
nonisolated enum ColorContrast {
    /// Colors closer than this in luminance to the background are unreadable.
    static let minimumDifference = 0.12

    /// `#rrggbb` (with or without `#`, surrounding spaces ignored); `nil` when malformed.
    static func rgb(hex: String) -> UInt32? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? trimmed.dropFirst() : Substring(trimmed)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }

    /// WCAG relative luminance, 0 (black) to 1 (white).
    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    static func isReadable(_ rgb: UInt32, on background: UInt32) -> Bool {
        abs(luminance(rgb) - luminance(background)) >= minimumDifference
    }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// `#rrggbb` (with or without `#`); `nil` for empty or malformed values.
    init?(hex: String) {
        guard let value = ColorContrast.rgb(hex: hex) else { return nil }
        self.init(nsColor: NSColor(rgb: value))
    }
}

extension League {
    var color: Color { Color(hex: colorHex) ?? Theme.accent }
}
