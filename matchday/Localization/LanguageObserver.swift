//
//  LanguageObserver.swift
//  matchday
//
//  Follows the store's effective language for the parts of the app SwiftUI
//  does not redraw: the language bundle, the status item, the About window title.
//

import Foundation
import Observation

/// Calls `onChange` with the store's language and locale now, then after every
/// change to either. Other settings changes (appearance, leagues) are skipped.
/// Stops when released.
final class LanguageObserver {
    private let store: MatchdayStore
    private let onChange: (AppLanguage, Locale) -> Void
    private var current: (language: AppLanguage, locale: Locale)?

    init(store: MatchdayStore, onChange: @escaping (AppLanguage, Locale) -> Void) {
        self.store = store
        self.onChange = onChange
        observe()
    }

    private func observe() {
        let (language, locale) = withObservationTracking {
            (store.language, store.locale)
        } onChange: { [weak self] in
            // Called before the change lands; read the new value on the next turn.
            Task { @MainActor in self?.observe() }
        }
        // Any settings change re-arms this; only an actual switch is reported.
        guard current?.language != language || current?.locale != locale else { return }
        current = (language, locale)
        onChange(language, locale)
    }
}
