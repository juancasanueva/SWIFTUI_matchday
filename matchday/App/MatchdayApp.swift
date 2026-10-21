//
//  MatchdayApp.swift
//  matchday
//

import SwiftUI

/// Matchday lives only in the menu bar (`LSUIElement = YES`). `AppDelegate`
/// owns the status item and the popover with the panel.
@main
struct MatchdayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // An empty Settings scene is the only scene, so no window opens at launch.
        Settings {
            EmptyView()
        }
    }
}
