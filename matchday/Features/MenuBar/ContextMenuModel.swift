//
//  ContextMenuModel.swift
//  matchday
//
//  Pure content of the status item's right-click menu. The controller maps
//  these values onto `NSMenuItem`s and owns the AppKit side alone.
//

import Foundation

nonisolated struct ContextMenuItem: Sendable, Equatable {
    /// What the controller does when the item is chosen.
    nonisolated enum Action: Sendable, Equatable {
        case openAbout
        case checkForUpdates
        case refresh
        case quit
    }

    let title: String
    let action: Action
    /// Shortcut shown in the menu (with ⌘); empty for none.
    var keyEquivalent: String = ""
    var isEnabled = true
}

nonisolated enum ContextMenuEntry: Sendable, Equatable {
    case item(ContextMenuItem)
    case separator
}

nonisolated enum ContextMenuModel {
    /// About comes first, as in every macOS application menu, with the update
    /// command right behind it, and Quit last.
    static func entries(canCheckForUpdates: Bool) -> [ContextMenuEntry] {
        [
            .item(ContextMenuItem(title: "About Matchday", action: .openAbout)),
            .item(ContextMenuItem(title: "Check for Updates\u{2026}", action: .checkForUpdates,
                                  isEnabled: UpdateCommandEnablement.isEnabled(canCheckForUpdates: canCheckForUpdates))),
            .item(ContextMenuItem(title: "Refresh", action: .refresh)),
            .separator,
            .item(ContextMenuItem(title: "Quit Matchday", action: .quit, keyEquivalent: "q")),
        ]
    }
}
