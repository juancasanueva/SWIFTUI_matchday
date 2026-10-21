//
//  MatchdayApp.swift
//  matchday
//

import SwiftUI

/// Matchday lives only in the menu bar (`LSUIElement = YES`), so the single
/// scene is a `MenuBarExtra` that opens a window-style panel.
@main
struct MatchdayApp: App {
    @State private var store: MatchdayStore

    init() {
        let environment = AppEnvironment()
        environment.start()
        _store = State(initialValue: environment.store)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
        } label: {
            MenuBarLabelContainer(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
