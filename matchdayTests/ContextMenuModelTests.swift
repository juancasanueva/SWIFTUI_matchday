//
//  ContextMenuModelTests.swift
//  matchdayTests
//

import Testing
@testable import matchday

@Suite("Status item context menu")
struct ContextMenuModelTests {
    @Test func aboutFirstThenRefreshThenQuit() {
        #expect(ContextMenuModel.entries == [
            .item(ContextMenuItem(title: "About Matchday", action: .openAbout)),
            .item(ContextMenuItem(title: "Refresh", action: .refresh)),
            .separator,
            .item(ContextMenuItem(title: "Quit Matchday", action: .quit, keyEquivalent: "q")),
        ])
    }

    @Test func onlyQuitHasAShortcut() {
        let shortcuts = ContextMenuModel.entries.compactMap { entry -> String? in
            guard case let .item(item) = entry, !item.keyEquivalent.isEmpty else { return nil }
            return item.title
        }
        #expect(shortcuts == ["Quit Matchday"])
    }
}
