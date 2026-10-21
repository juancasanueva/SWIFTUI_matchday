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
    @State private var launchAtLogin: LaunchAtLogin

    init() {
        let environment = AppEnvironment()
        environment.start()
        _store = State(initialValue: environment.store)
        _launchAtLogin = State(initialValue: environment.launchAtLogin)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
                .environment(launchAtLogin)
        } label: {
            MenuBarLabelContainer(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
