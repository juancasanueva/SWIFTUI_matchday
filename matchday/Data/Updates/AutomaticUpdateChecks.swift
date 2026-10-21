//
//  AutomaticUpdateChecks.swift
//  matchday
//

import Foundation

/// Whether Matchday may look for updates on its own. A missing key reads
/// `false`: checking is network traffic, so it stays off until the user asks.
nonisolated struct AutomaticUpdateChecks: @unchecked Sendable {
    static let key = "updates.automaticChecksEnabled"

    /// `UserDefaults` is thread-safe; tests inject a throwaway suite.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nonmutating` because the storage is the defaults domain, not this value.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
