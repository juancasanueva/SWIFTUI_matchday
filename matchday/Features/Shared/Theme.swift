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

    static let background = adaptive(light: 0xF5F7FA, dark: 0x0D1724)
    static let foreground = adaptive(light: 0x1A2433, dark: 0xD9DFE8)
    /// Secondary text.
    static let dim = foreground.opacity(0.58)
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
    static let panelWidth: CGFloat = 470
    static let panelHeight: CGFloat = 720

    // MARK: Type

    /// Monospaced system font, as in the original panel.
    static func font(_ size: Size, weight: Font.Weight = .regular) -> Font {
        .system(size: size.rawValue, weight: weight, design: .monospaced)
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
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
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
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(nsColor: NSColor(rgb: value))
    }
}

extension League {
    var color: Color { Color(hex: colorHex) ?? Theme.accent }
}
