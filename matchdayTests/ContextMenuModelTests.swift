//
//  ContextMenuModelTests.swift
//  matchdayTests
//

import Testing
@testable import matchday

@Suite("Status item context menu")
struct ContextMenuModelTests {
    @Test func aboutFirstThenCheckForUpdatesThenRefreshThenQuit() {
        #expect(ContextMenuModel.entries(canCheckForUpdates: true) == [
            .item(ContextMenuItem(title: "About Matchday", action: .openAbout)),
            .item(ContextMenuItem(title: "Check for Updates\u{2026}", action: .checkForUpdates)),
            .item(ContextMenuItem(title: "Refresh", action: .refresh)),
            .separator,
            .item(ContextMenuItem(title: "Quit Matchday", action: .quit, keyEquivalent: "q")),
        ])
    }

    @Test func onlyQuitHasAShortcut() {
        let shortcuts = ContextMenuModel.entries(canCheckForUpdates: true).compactMap { entry -> String? in
            guard case let .item(item) = entry, !item.keyEquivalent.isEmpty else { return nil }
            return item.title
        }
        #expect(shortcuts == ["Quit Matchday"])
    }

    /// Only the update command follows the updater; it goes dark while a check runs.
    @Test(arguments: [true, false])
    func checkForUpdatesFollowsTheUpdater(canCheck: Bool) {
        let enabled = ContextMenuModel.entries(canCheckForUpdates: canCheck).compactMap { entry -> String? in
            guard case let .item(item) = entry, item.isEnabled else { return nil }
            return item.title
        }
        let expected = canCheck
            ? ["About Matchday", "Check for Updates\u{2026}", "Refresh", "Quit Matchday"]
            : ["About Matchday", "Refresh", "Quit Matchday"]
        #expect(enabled == expected)
    }
}
