//
//  MenuBarLabel.swift
//  matchday
//
//  The status item: ball icon, matchday dot and live score text (the bar
//  button, live button and dot in Panel.qml).
//
//  `MenuBarExtra` renders its label as a template image plus text, so SwiftUI
//  colors and overlays are dropped. A colored dot therefore needs a composed,
//  non-template `NSImage`; it is drawn lazily so the ball still follows the
//  menu bar's light or dark appearance. Pulsing swaps the dot's opacity on a
//  timer because label animations are not rendered.
//

import AppKit
import SwiftUI

/// Reads the bar state from the store.
struct MenuBarLabelContainer: View {
    let store: MatchdayStore

    var body: some View {
        MenuBarLabel(bar: store.bar)
    }
}

struct MenuBarLabel: View {
    let bar: BarState

    @State private var pulseDimmed = false

    /// Live text replaces the dot, as in the original bar.
    private var dot: MenuBarIcon.Dot? {
        guard bar.showDot, bar.liveText == nil else { return nil }
        return bar.isLive ? .live : .soon
    }

    private var pulses: Bool {
        dot == .live && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(dot: dot, dimmed: bar.isDimmed,
                                             dotOpacity: pulses && pulseDimmed ? 0.35 : 1))
                .accessibilityLabel(accessibilityText)
            if let liveText = bar.liveText {
                Text(liveText)
                    .monospacedDigit()
            }
        }
        .help(bar.tooltip)
        .task(id: pulses) {
            pulseDimmed = false
            guard pulses else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                pulseDimmed.toggle()
            }
        }
    }

    private var accessibilityText: String {
        if bar.isLive { return "Matchday, a followed team is live" }
        if bar.showDot { return "Matchday, a followed team plays soon" }
        return "Matchday"
    }
}

/// Draws the menu bar icon.
enum MenuBarIcon {
    enum Dot {
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

#Preview("Bar states") {
    VStack(alignment: .leading, spacing: 12) {
        MenuBarLabel(bar: .empty)
        MenuBarLabel(bar: BarState(showDot: true, isLive: false, liveText: nil, tooltip: "", isDimmed: false))
        MenuBarLabel(bar: BarState(showDot: true, isLive: true, liveText: nil, tooltip: "", isDimmed: false))
        MenuBarLabel(bar: BarState(showDot: true, isLive: true, liveText: "BAR 2–1 GET  67'",
                                   tooltip: "", isDimmed: false))
    }
    .padding()
}
