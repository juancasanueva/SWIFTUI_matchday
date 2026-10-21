//
//  SettingsStoreTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("App settings")
struct AppSettingsTests {
    let arsenal = FavoriteTeam(leagueID: "eng.1", teamID: "359", name: "Arsenal",
                               shortName: "Arsenal", abbreviation: "ARS")
    let madrid = FavoriteTeam(leagueID: "esp.1", teamID: "86", name: "Real Madrid",
                              shortName: "Real Madrid", abbreviation: "RMA")

    @Test func defaultsMatchTheOriginalPlugin() {
        let settings = AppSettings()
        #expect(settings.favorites.isEmpty)
        #expect(settings.leagues == League.all.map(\.id))
        #expect(settings.country == AppSettings.automaticCountry)
        #expect(settings.spanish)
        #expect(settings.notifyKickoff)
        #expect(settings.kickoffLead == 15)
        #expect(settings.notifyGoals)
        #expect(settings.notifyFinal)
        #expect(settings.barScore)
        #expect(settings.appearance == .system)
    }

    static let leadCases: [(Int, Int)] = [(0, 1), (-5, 1), (1, 1), (45, 45), (120, 120), (500, 120)]

    @Test(arguments: leadCases)
    func kickoffLeadIsClamped(input: Int, expected: Int) {
        var settings = AppSettings()
        settings.kickoffLead = input
        #expect(settings.kickoffLead == expected)
    }

    @Test func leaguesDropUnknownIDsAndNeverEndUpEmpty() {
        var settings = AppSettings()
        settings.setLeagues(["eng.1", "nope", "esp.1"])
        #expect(settings.leagues == ["eng.1", "esp.1"])
        settings.setLeagues(["nope"])
        #expect(settings.leagues == League.all.map(\.id))
    }

    @Test func enablingAndDisablingLeaguesKeepsCatalogOrder() {
        var settings = AppSettings()
        settings.setLeagues(["eng.1", "esp.1"])
        let enabledItaly = settings.setLeague("ita.1", enabled: true)
        #expect(enabledItaly)
        #expect(settings.leagues == ["esp.1", "ita.1", "eng.1"])
        #expect(settings.isLeagueEnabled("ita.1"))

        let disabledSpain = settings.setLeague("esp.1", enabled: false)
        #expect(disabledSpain)
        #expect(settings.leagues == ["ita.1", "eng.1"])
        #expect(!settings.isLeagueEnabled("esp.1"))
    }

    @Test func theLastEnabledLeagueStaysOnAndUnknownLeaguesAreIgnored() {
        var settings = AppSettings()
        settings.setLeagues(["usa.1"])
        let disabledLast = settings.setLeague("usa.1", enabled: false)
        #expect(!disabledLast)
        #expect(settings.leagues == ["usa.1"])
        let enabledUnknown = settings.setLeague("nope", enabled: true)
        #expect(!enabledUnknown)
        #expect(settings.leagues == ["usa.1"])
    }

    @Test func toggleFollowAddsThenRemovesByLeagueAndID() {
        var settings = AppSettings()
        settings.toggleFollow(arsenal)
        settings.toggleFollow(madrid)
        #expect(settings.favorites == [arsenal, madrid])
        #expect(settings.isFollowing(leagueID: "eng.1", teamID: "359"))
        // Same ESPN id in another league is a different favorite.
        #expect(!settings.isFollowing(leagueID: "uefa.champions", teamID: "359"))

        settings.toggleFollow(arsenal)
        #expect(settings.favorites == [madrid])
        #expect(!settings.isFollowing(leagueID: "eng.1", teamID: "359"))
    }

    @Test func legacySettingsWithoutLeaguesSeenEnableLeaguesAddedLater() {
        // A config from before `leaguesSeen` knew the original four leagues.
        var settings = AppSettings()
        settings.leaguesSeen = nil
        settings.setLeagues(["esp.1", "eng.1"])

        let migrated = settings.migrateNewLeagues()
        #expect(migrated)
        #expect(settings.leagues == ["esp.1", "eng.1", "uefa.champions", "uefa.nations"])
        #expect(settings.leaguesSeen == League.all.map(\.id))

        // Turning a new league off afterwards sticks.
        settings.setLeagues(["esp.1"])
        let migratedAgain = settings.migrateNewLeagues()
        #expect(!migratedAgain)
        #expect(settings.leagues == ["esp.1"])
    }

    @Test func onlyLeaguesMissingFromSeenAreAdded() {
        var settings = AppSettings()
        settings.leaguesSeen = ["esp.1", "ita.1", "eng.1", "usa.1", "uefa.champions"]
        settings.setLeagues(["ita.1"])
        let migrated = settings.migrateNewLeagues()
        #expect(migrated)
        #expect(settings.leagues == ["ita.1", "uefa.nations"])
    }

    @Test func decodingFillsMissingKeysWithDefaults() throws {
        let json = #"{"favorites":[],"country":"GB","kickoffLead":500}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.country == "GB")
        #expect(settings.kickoffLead == 120)
        #expect(settings.leagues == League.all.map(\.id))
        #expect(settings.spanish)
        #expect(settings.leaguesSeen == nil)
        #expect(settings.appearance == .system)
    }

    @Test func appearanceDecodesFromItsRawValue() throws {
        let json = #"{"appearance":"dark"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.appearance == .dark)
    }

    @Test func appearanceModesListSystemFirstWithTitles() {
        #expect(AppearanceMode.allCases == [.system, .light, .dark])
        #expect(AppearanceMode.allCases.map(\.title) == ["System", "Light", "Dark"])
    }
}

@Suite("UserDefaults settings store")
struct UserDefaultsSettingsStoreTests {
    let arsenal = FavoriteTeam(leagueID: "eng.1", teamID: "359", name: "Arsenal",
                               shortName: "Arsenal", abbreviation: "ARS")

    private func makeDefaults() -> UserDefaults {
        let suite = "matchday-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func emptyDefaultsLoadTheDefaultSettings() {
        let store = UserDefaultsSettingsStore(defaults: makeDefaults())
        #expect(store.load() == AppSettings())
    }

    @Test func savedSettingsRoundTrip() {
        let defaults = makeDefaults()
        var settings = AppSettings()
        settings.toggleFollow(arsenal)
        settings.country = "ES"
        settings.spanish = false
        settings.kickoffLead = 30
        settings.barScore = false
        settings.appearance = .light
        UserDefaultsSettingsStore(defaults: defaults).save(settings)

        // A fresh store over the same defaults sees the same settings (a relaunch).
        let loaded = UserDefaultsSettingsStore(defaults: defaults).load()
        #expect(loaded == settings)
        #expect(loaded.favorites == [arsenal])
        #expect(loaded.appearance == .light)
    }

    @Test func settingsAreStoredAsJSONUnderOneKey() throws {
        let defaults = makeDefaults()
        UserDefaultsSettingsStore(defaults: defaults).save(AppSettings())
        let data = try #require(defaults.data(forKey: UserDefaultsSettingsStore.key))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["kickoffLead"] as? Int == 15)
    }

    @Test func toggleFollowPersists() {
        let defaults = makeDefaults()
        let store = UserDefaultsSettingsStore(defaults: defaults)
        #expect(store.toggleFollow(arsenal).favorites == [arsenal])
        #expect(UserDefaultsSettingsStore(defaults: defaults).load().favorites == [arsenal])
        #expect(store.toggleFollow(arsenal).favorites.isEmpty)
        #expect(UserDefaultsSettingsStore(defaults: defaults).load().favorites.isEmpty)
    }

    @Test func loadMigratesAndPersistsNewLeagues() throws {
        let defaults = makeDefaults()
        let legacy = #"{"favorites":[],"leagues":["esp.1"]}"#
        defaults.set(Data(legacy.utf8), forKey: UserDefaultsSettingsStore.key)

        let loaded = UserDefaultsSettingsStore(defaults: defaults).load()
        #expect(loaded.leagues == ["esp.1", "uefa.champions", "uefa.nations"])
        let raw = try #require(defaults.data(forKey: UserDefaultsSettingsStore.key))
        let persisted = try JSONDecoder().decode(AppSettings.self, from: raw)
        #expect(persisted.leaguesSeen == League.all.map(\.id))
    }

    @Test func corruptDataFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: UserDefaultsSettingsStore.key)
        #expect(UserDefaultsSettingsStore(defaults: defaults).load() == AppSettings())
    }
}

@Suite("Country resolution")
struct CountryResolverTests {
    private func resolver(region: String?, zone: String = "Europe/Madrid") -> CountryResolver {
        CountryResolver(regionCode: region, timeZone: TimeZone(identifier: zone)!,
                        locale: Locale(identifier: "en_US"))
    }

    @Test func automaticUsesTheSystemRegion() {
        #expect(resolver(region: "ES").countryCode(for: AppSettings.automaticCountry) == "ES")
        #expect(resolver(region: nil).countryCode(for: AppSettings.automaticCountry) == nil)
    }

    @Test func explicitCodeWins() {
        #expect(resolver(region: "ES").countryCode(for: "gb") == "GB")
    }

    @Test func automaticLabelShowsCityAndCountry() {
        #expect(resolver(region: "ES").automaticLabel == "Madrid, Spain")
        #expect(resolver(region: "US", zone: "America/New_York").automaticLabel == "New York, United States")
        #expect(resolver(region: nil).automaticLabel == "Madrid, unknown")
    }

    @Test func countryNameIsLocalized() {
        #expect(resolver(region: "ES").countryName(for: "GB") == "United Kingdom")
        #expect(resolver(region: "ES").countryName(for: "ZZZ") == "ZZZ")
    }
}
