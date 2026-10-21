//
//  UserDefaultsSettingsStore.swift
//  matchday
//

import Foundation

/// `SettingsStore` adapter: the whole `AppSettings` as JSON under one UserDefaults key.
nonisolated struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    static let key = "matchday.settings"

    /// `UserDefaults` is thread-safe; tests inject a throwaway suite.
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.key),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        if settings.migrateNewLeagues() {
            save(settings)
        }
        return settings
    }

    func save(_ settings: AppSettings) {
        // Encoding plain values cannot fail in practice; keep the previous copy if it does.
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
