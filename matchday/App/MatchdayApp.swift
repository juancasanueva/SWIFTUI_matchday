//
//  MatchdayApp.swift
//  matchday
//

import SwiftUI

/// Composition root. Matchday lives only in the menu bar (`LSUIElement = YES`),
/// so the single scene is a `MenuBarExtra` that opens a window-style panel.
@main
struct MatchdayApp: App {
    var body: some Scene {
        MenuBarExtra {
            PanelView()
        } label: {
            Image(systemName: "soccerball")
        }
        .menuBarExtraStyle(.window)
    }
}
