//
//  MenuBarIcon.swift
//  matchday
//
//  The status item: ball icon, matchday dot and live score text (the bar
//  button, live button and dot in Panel.qml).
//
//  A colored dot needs a composed, non-template `NSImage`; it is drawn lazily
//  so the ball still follows the menu bar's light or dark appearance.
//

import AppKit

/// What the status item button shows for a bar state. Pure, so the decisions
/// are testable without a status bar.
nonisolated struct StatusItemLook: Equatable, Sendable {
    /// Opacity of the live dot on the pulse's off beat.
    static let pulseDimmedOpacity = 0.35

    let dot: MenuBarIcon.Dot?
    let isDimmed: Bool
    /// Live score text next to the icon, empty when there is none.
    let title: String
    let tooltip: String
    let accessibilityLabel: String
    /// The live dot pulses, unless Reduce Motion is on.
    let pulses: Bool

    init(bar: BarState, reduceMotion: Bool) {
        // Live text replaces the dot, as in the original bar.
        let dot: MenuBarIcon.Dot? = if bar.showDot, bar.liveText == nil {
            bar.isLive ? .live : .soon
        } else {
            nil
        }
        self.dot = dot
        isDimmed = bar.isDimmed
        title = bar.liveText ?? ""
        tooltip = bar.tooltip
        pulses = dot == .live && !reduceMotion
        // Built outside SwiftUI: in the language bundle the status item applies.
        accessibilityLabel = if bar.isLive {
            String(appLocalized: "Matchday, a followed team is live",
                   comment: "VoiceOver label of the menu bar icon while a followed team plays.")
        } else if bar.showDot {
            String(appLocalized: "Matchday, a followed team plays soon",
                   comment: "VoiceOver label of the menu bar icon when a followed team plays within 12 hours.")
        } else {
            AboutModel.appName
        }
    }

    func dotOpacity(pulseDimmed: Bool) -> Double {
        pulses && pulseDimmed ? Self.pulseDimmedOpacity : 1
    }
}

/// Draws the menu bar icon.
enum MenuBarIcon {
    nonisolated enum Dot: Equatable, Sendable {
        /// A followed team plays within 12 hours (accent).
        case soon
        /// A followed team is live (red).
        case live
    }

    static let size = NSSize(width: 20, height: 18)
    static let symbolPointSize: CGFloat = 14
    static let dotDiameter: CGFloat = 6

    /// The plain template symbol when there is nothing to color, else a composed image.
    static func image(dot: Dot?, dimmed: Bool, dotOpacity: Double) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "soccerball", accessibilityDescription: "Matchday")?
            .withSymbolConfiguration(configuration)
        else { return NSImage(size: size) }

        if dot == nil && !dimmed {
            symbol.isTemplate = true
            return symbol
        }

        let image = NSImage(size: size, flipped: false) { rect in
            // Resolved at draw time, against the menu bar's current appearance.
            let ink = NSColor.labelColor.withAlphaComponent(dimmed ? 0.55 : 1)
            let ball = tinted(symbol, with: ink)
            let origin = NSPoint(x: (rect.width - ball.size.width) / 2 - 1,
                                 y: (rect.height - ball.size.height) / 2)
            ball.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)

            if let dot {
                let color: NSColor = dot == .live ? .systemRed : .controlAccentColor
                let frame = NSRect(x: rect.maxX - dotDiameter, y: rect.maxY - dotDiameter - 1,
                                   width: dotDiameter, height: dotDiameter)
                color.withAlphaComponent(dotOpacity).setFill()
                NSBezierPath(ovalIn: frame).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Matchday"
        return image
    }

    /// `symbol` filled with `color`.
    private static func tinted(_ symbol: NSImage, with color: NSColor) -> NSImage {
        NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
