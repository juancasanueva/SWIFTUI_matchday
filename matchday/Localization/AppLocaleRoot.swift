//
//  AppLocaleRoot.swift
//  matchday
//
//  Wraps the content of each AppKit-hosted SwiftUI root (the panel, the About
//  window) in the app language, so SwiftUI literals switch with Settings.
//

import SwiftUI

/// Draws `content` in the store's effective language; a change in Settings
/// re-renders it at once. Requires `MatchdayStore` in the environment.
struct AppLocaleRoot<Content: View>: View {
    @Environment(MatchdayStore.self) private var store
    @ViewBuilder let content: Content

    var body: some View {
        content.environment(\.locale, store.locale)
    }
}
