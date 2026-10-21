//
//  UpdateCheckPresentation.swift
//  matchday
//

import Foundation

/// "Last checked …" under the Updates card. `now` is injected so the label is
/// a pure function of its inputs; a bundle that never checked says so in words.
nonisolated struct UpdateCheckPresentation: Sendable, Hashable {
    static let neverChecked = "Never checked"

    let lastCheck: Date?
    let now: Date
    var locale: Locale = .current

    var label: String {
        guard let lastCheck else { return Self.neverChecked }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = locale
        return "Last checked \(formatter.localizedString(for: lastCheck, relativeTo: now))"
    }
}
