//
//  PanelAppearance.swift
//  matchday
//
//  Maps the Appearance setting to the popover's `NSAppearance`. Only the
//  panel is themed; the status item keeps following the menu bar.
//

import AppKit

nonisolated enum PanelAppearance {
    /// `nil` makes the popover inherit the system appearance.
    static func appearance(for mode: AppearanceMode) -> NSAppearance? {
        switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
