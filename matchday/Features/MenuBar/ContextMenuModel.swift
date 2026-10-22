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
    /// command right behind it, and Quit last. Titles are in the app language
    /// of `bundle`; the menu is rebuilt on every right click.
    static func entries(canCheckForUpdates: Bool,
                        bundle: Bundle = AppLocalization.shared.bundle) -> [ContextMenuEntry] {
        func title(_ value: String.LocalizationValue, _ comment: StaticString) -> String {
            String(appLocalized: value, bundle: bundle, comment: comment)
        }
        return [
            .item(ContextMenuItem(title: title("About Matchday", "Menu item that opens the About window."),
                                  action: .openAbout)),
            .item(ContextMenuItem(title: title("Check for Updates\u{2026}", "Menu item and button that look for a new version."),
                                  action: .checkForUpdates,
                                  isEnabled: UpdateCommandEnablement.isEnabled(canCheckForUpdates: canCheckForUpdates))),
            .item(ContextMenuItem(title: title("Refresh", "Menu item and button that fetch fresh data now."),
                                  action: .refresh)),
            .separator,
            .item(ContextMenuItem(title: title("Quit Matchday", "Menu item that quits the app."),
                                  action: .quit, keyEquivalent: "q")),
        ]
    }
}
