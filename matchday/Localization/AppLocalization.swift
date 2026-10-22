//
//  AppLocalization.swift
//  matchday
//
//  The language bundle for strings built outside SwiftUI views (derivations,
//  notifications, the context menu, tooltips, window titles). SwiftUI literals
//  follow the `\.locale` environment instead (`AppLocaleRoot`); these strings
//  have no environment to read, so they resolve from the `.lproj` folder of the
//  language chosen in Settings, which takes effect without a relaunch.
//

import Foundation
import Synchronization

/// Holds the bundle and locale of the app language. `shared` is pointed at the
/// effective language by the status item on launch and on every change; tests
/// build their own so the process-wide one stays on the development language.
nonisolated final class AppLocalization: Sendable {
    static let shared = AppLocalization()

    private struct State {
        var bundle: Bundle
        var locale: Locale
    }

    private let base: Bundle
    /// Read from any isolation (derivations are `nonisolated`), written on the main actor.
    private let state: Mutex<State>

    /// Starts on the development language until `apply` says otherwise, so the
    /// unit-test host (which never applies one) reads English on any Mac.
    ///
    /// - Parameter base: The bundle carrying the `.lproj` folders.
    init(base: Bundle = .main) {
        self.base = base
        state = Mutex(State(bundle: Self.bundle(for: .english, in: base), locale: AppLanguage.english.locale))
    }

    /// The bundle localized strings resolve from: the language's `.lproj`, else English's.
    var bundle: Bundle {
        state.withLock { $0.bundle }
    }

    /// The locale interpolated values (numbers, dates) are formatted in.
    var locale: Locale {
        state.withLock { $0.locale }
    }

    /// Points strings at `language`, formatting values in `locale`
    /// (`AppLanguage.locale(preferring:)`).
    func apply(_ language: AppLanguage, locale: Locale) {
        let bundle = Self.bundle(for: language, in: base)
        state.withLock { $0 = State(bundle: bundle, locale: locale) }
    }

    /// The `.lproj` bundle of a language, else the development language's
    /// (`en.lproj`), else `base`. Not `base` first: its lookups follow the system
    /// languages, so a Spanish Mac would read Spanish for a language not shipped yet.
    static func bundle(for language: AppLanguage, in base: Bundle = .main) -> Bundle {
        lproj(language, in: base) ?? lproj(.english, in: base) ?? base
    }

    private static func lproj(_ language: AppLanguage, in base: Bundle) -> Bundle? {
        base.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

nonisolated extension Locale {
    /// The language bundle of the app language this locale stands for. In a
    /// SwiftUI view, `\.locale` is the app locale (`AppLocaleRoot`), so a string
    /// built in the view resolves in the same language as its literals.
    var appBundle: Bundle {
        AppLocalization.bundle(for: .matching(self))
    }
}

nonisolated extension String {
    /// A literal resolved in the app language, arguments included:
    /// `String(appLocalized: "in \(minutes)m")`. Xcode extracts the literal into
    /// `Localizable.xcstrings` like `String(localized:)`.
    init(appLocalized value: String.LocalizationValue, table: String? = nil,
         bundle: Bundle = AppLocalization.shared.bundle, locale: Locale = AppLocalization.shared.locale,
         comment: StaticString? = nil) {
        self.init(localized: value, table: table, bundle: bundle, locale: locale, comment: comment)
    }

    /// A stored resource resolved in the app language, arguments included. The
    /// resource is looked up by its default value, so declare it from a literal
    /// (`LocalizedStringResource("Goal!")`), not with a separate key.
    init(appLocalized resource: LocalizedStringResource,
         bundle: Bundle = AppLocalization.shared.bundle, locale: Locale = AppLocalization.shared.locale) {
        self.init(localized: resource.defaultValue, table: resource.table, bundle: bundle, locale: locale)
    }

    /// A key only known at runtime, resolved in the app language. Xcode cannot
    /// extract these, so each must be added to `Localizable.xcstrings` by hand;
    /// a key missing from the catalog falls back to itself.
    init(appLocalizedKey key: String, table: String? = nil, bundle: Bundle = AppLocalization.shared.bundle) {
        self = bundle.localizedString(forKey: key, value: key, table: table)
    }
}
