//
//  UpdateCheckPresentation.swift
//  matchday
//

import Foundation

/// "Last checked …" under the Updates card. `now` is injected so the label is
/// a pure function of its inputs; a bundle that never checked says so in words.
/// Both are in the app language of `locale`.
nonisolated struct UpdateCheckPresentation: Sendable, Hashable {
    let lastCheck: Date?
    let now: Date
    var locale: Locale = AppLocalization.shared.locale

    static func neverChecked(locale: Locale = AppLocalization.shared.locale) -> String {
        String(appLocalized: "Never checked", bundle: locale.appBundle, locale: locale,
               comment: "Updates card: the app has never looked for a new version.")
    }

    var label: String {
        guard let lastCheck else { return Self.neverChecked(locale: locale) }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = locale
        let relative = formatter.localizedString(for: lastCheck, relativeTo: now)
        return String(appLocalized: "Last checked \(relative)", bundle: locale.appBundle, locale: locale,
                      comment: "Updates card: when the app last looked for a new version, e.g. “2 hours ago”.")
    }
}
