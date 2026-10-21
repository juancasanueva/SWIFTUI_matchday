//
//  AppSettings.swift
//  matchday
//
//  User preferences and followed teams (`DEFAULT_CONFIG` in the original plugin).
//

import Foundation

nonisolated struct AppSettings: Codable, Hashable, Sendable {
    /// `country` value meaning "use the system region".
    static let automaticCountry = "auto"
    static let kickoffLeadRange = 1...120
    /// Leagues every config knew before `leaguesSeen` existed.
    static let legacyLeagues = ["esp.1", "ita.1", "eng.1", "usa.1"]

    var favorites: [FavoriteTeam] = []
    /// Enabled league ids, in catalog order unless the user reordered them.
    private(set) var leagues: [String] = League.all.map(\.id)
    /// `auto`, or an ISO 3166 country code for where-to-watch.
    var country: String = AppSettings.automaticCountry
    /// Include Spanish-language broadcasts.
    var spanish = true
    var notifyKickoff = true
    /// Minutes before kickoff for the reminder, clamped to `kickoffLeadRange`.
    var kickoffLead = 15 {
        didSet { kickoffLead = Self.clampLead(kickoffLead) }
    }
    var notifyGoals = true
    var notifyFinal = true
    /// Live score text next to the menu bar icon.
    var barScore = true
    /// Light or dark panel, or the system appearance.
    var appearance: AppearanceMode = .system
    /// Catalog leagues this config has already been offered; `nil` for legacy configs.
    var leaguesSeen: [String]? = League.all.map(\.id)

    init() {}

    // MARK: Mutations

    /// Keeps known leagues only; an empty result means every league (`set_config`).
    mutating func setLeagues(_ ids: [String]) {
        let known = ids.filter { League.with(id: $0) != nil }
        leagues = known.isEmpty ? League.all.map(\.id) : known
    }

    func isLeagueEnabled(_ id: String) -> Bool {
        leagues.contains(id)
    }

    /// Turns one catalog league on or off, keeping catalog order. The last enabled
    /// league stays on. Returns whether anything changed.
    @discardableResult
    mutating func setLeague(_ id: String, enabled: Bool) -> Bool {
        guard League.with(id: id) != nil, isLeagueEnabled(id) != enabled else { return false }
        if !enabled && leagues.count == 1 { return false }
        var ids = Set(leagues)
        if enabled { ids.insert(id) } else { ids.remove(id) }
        leagues = League.all.map(\.id).filter(ids.contains)
        return true
    }

    func isFollowing(leagueID: String, teamID: String) -> Bool {
        favorites.contains { $0.leagueID == leagueID && $0.teamID == teamID }
    }

    /// Follows `team`, or unfollows it when it is already followed (matched by league + id).
    mutating func toggleFollow(_ team: FavoriteTeam) {
        if isFollowing(leagueID: team.leagueID, teamID: team.teamID) {
            favorites.removeAll { $0.leagueID == team.leagueID && $0.teamID == team.teamID }
        } else {
            favorites.append(team)
        }
    }

    /// Turns on leagues added to the catalog after this config was saved, once
    /// (`add_new_leagues`). Returns whether anything changed and needs saving.
    @discardableResult
    mutating func migrateNewLeagues(catalog: [String] = League.all.map(\.id)) -> Bool {
        let seen = leaguesSeen ?? Self.legacyLeagues
        let new = catalog.filter { !seen.contains($0) }
        if new.isEmpty && leaguesSeen != nil { return false }
        leagues += new.filter { !leagues.contains($0) }
        leaguesSeen = catalog
        return true
    }

    private static func clampLead(_ minutes: Int) -> Int {
        min(max(minutes, kickoffLeadRange.lowerBound), kickoffLeadRange.upperBound)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case favorites, leagues, country, spanish, notifyKickoff, kickoffLead,
             notifyGoals, notifyFinal, barScore, appearance, leaguesSeen
    }

    /// Missing keys keep their defaults so older saved settings still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        favorites = try container.decodeIfPresent([FavoriteTeam].self, forKey: .favorites) ?? defaults.favorites
        leagues = defaults.leagues
        if let saved = try container.decodeIfPresent([String].self, forKey: .leagues) {
            setLeagues(saved)
        }
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? defaults.country
        spanish = try container.decodeIfPresent(Bool.self, forKey: .spanish) ?? defaults.spanish
        notifyKickoff = try container.decodeIfPresent(Bool.self, forKey: .notifyKickoff) ?? defaults.notifyKickoff
        kickoffLead = Self.clampLead(try container.decodeIfPresent(Int.self, forKey: .kickoffLead) ?? defaults.kickoffLead)
        notifyGoals = try container.decodeIfPresent(Bool.self, forKey: .notifyGoals) ?? defaults.notifyGoals
        notifyFinal = try container.decodeIfPresent(Bool.self, forKey: .notifyFinal) ?? defaults.notifyFinal
        barScore = try container.decodeIfPresent(Bool.self, forKey: .barScore) ?? defaults.barScore
        appearance = (try? container.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? defaults.appearance
        leaguesSeen = try container.decodeIfPresent([String].self, forKey: .leaguesSeen)
    }
}

/// Port for persisting `AppSettings`. The UserDefaults adapter lives in `Data/Settings`.
nonisolated protocol SettingsStore: Sendable {
    /// Saved settings (migrated to the current league catalog), or defaults.
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

nonisolated extension SettingsStore {
    /// Loads, follows or unfollows `team`, saves, and returns the new settings.
    @discardableResult
    func toggleFollow(_ team: FavoriteTeam) -> AppSettings {
        var settings = load()
        settings.toggleFollow(team)
        save(settings)
        return settings
    }
}
