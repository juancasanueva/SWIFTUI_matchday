//
//  MatchdayStoreTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

/// Settings kept in memory, so store tests never touch UserDefaults.
final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings
    private(set) var saveCount = 0

    init(_ settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    func load() -> AppSettings {
        lock.withLock { settings }
    }

    func save(_ settings: AppSettings) {
        lock.withLock {
            self.settings = settings
            saveCount += 1
        }
    }
}

@MainActor
@Suite("Matchday store")
struct MatchdayStoreTests {
    /// 16:00 UTC on the fixture day: the Arsenal match in `scoreboard.json` is at halftime.
    let now = utcDate(2026, 10, 18, 16)
    let arsenal = Team(id: "359", leagueID: "eng.1", name: "Arsenal", shortName: "Arsenal", abbreviation: "ARS")
    let fixtures: [String: Data]

    init() throws {
        fixtures = [
            "scoreboard": try Fixture.data("scoreboard"),
            "schedule": try Fixture.data("schedule"),
            "standings": try Fixture.data("standings"),
            "teams": try Fixture.data("teams"),
        ]
    }

    private func makeTransport() -> FakeTransport {
        let fixtures = fixtures
        return FakeTransport { url in
            let text = url.absoluteString
            if text.contains("/scoreboard") {
                return text.hasSuffix("dates=20261018") ? .data(fixtures["scoreboard"]!) : .json(#"{"events":[]}"#)
            }
            if text.contains("/schedule") { return .data(fixtures["schedule"]!) }
            if text.contains("/standings") { return .data(fixtures["standings"]!) }
            if text.hasSuffix("/teams") { return .data(fixtures["teams"]!) }
            return .status(404, "")
        }
    }

    private func makeStore(_ transport: FakeTransport, settings: InMemorySettingsStore,
                           tick: Duration = .seconds(5), notifier: MatchNotifier? = nil,
                           countryLocale: Locale = Locale(identifier: "en_US"),
                           locale: Locale = Locale(identifier: "en_US")) throws -> MatchdayStore {
        let repository = MatchRepository(client: ESPNClient(transport: transport, calendar: utcCalendar()),
                                         cache: HTTPCache(directory: temporaryDirectory()),
                                         calendar: utcCalendar())
        let now = now
        return MatchdayStore(
            repository: repository,
            settingsStore: settings,
            whereToWatch: WhereToWatch(catalog: try BroadcasterCatalog.bundled()),
            countryResolver: CountryResolver(regionCode: "US", timeZone: TimeZone(identifier: "UTC")!,
                                             locale: countryLocale),
            calendar: utcCalendar(),
            locale: locale,
            clock: { now },
            tick: tick,
            notifier: notifier
        )
    }

    @Test func startsWithSavedSettingsAndLoadingState() throws {
        var saved = AppSettings()
        saved.toggleFollow(FavoriteTeam(team: arsenal))
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore(saved))
        #expect(store.settings.favorites.map(\.teamID) == ["359"])
        #expect(store.snapshot.status == .loading)
        #expect(!store.isRefreshing)
        #expect(store.header == "LOADING FIXTURES…")
    }

    @Test func refreshFetchesEnabledLeaguesAndFavorites() async throws {
        var saved = AppSettings()
        saved.setLeagues(["eng.1"])
        saved.toggleFollow(FavoriteTeam(team: arsenal))
        let transport = makeTransport()
        let store = try makeStore(transport, settings: InMemorySettingsStore(saved))

        await store.refresh()
        let urls = await transport.requestedURLs
        #expect(urls.count == 17)
        #expect(urls.allSatisfy { $0.contains("/eng.1/") })
        #expect(urls.contains { $0.hasSuffix("/teams/359/schedule?fixture=true") })
        #expect(store.snapshot.status == .ok)
        #expect(!store.isRefreshing)
        #expect(store.following.first?.live != nil)
        #expect(store.bar.isLive)
    }

    @Test func toggleFollowPersistsAndUpdatesDerivedState() async throws {
        let settings = InMemorySettingsStore()
        let store = try makeStore(makeTransport(), settings: settings)
        store.toggleFollow(arsenal)
        #expect(store.settings.isFollowing(leagueID: "eng.1", teamID: "359"))
        #expect(settings.load().favorites.map(\.teamID) == ["359"])
        #expect(store.following.map(\.favorite.teamID) == ["359"])

        store.toggleFollow(arsenal)
        #expect(store.settings.favorites.isEmpty)
        #expect(settings.load().favorites.isEmpty)
    }

    @Test func settingsMutationsPersist() throws {
        let settings = InMemorySettingsStore()
        let store = try makeStore(makeTransport(), settings: settings)
        store.updateSettings { $0.kickoffLead = 500; $0.spanish = false }
        #expect(store.settings.kickoffLead == 120)
        #expect(settings.load().kickoffLead == 120)
        #expect(!settings.load().spanish)
    }

    @Test func kickoffLeadSetterClampsAndPersists() throws {
        let settings = InMemorySettingsStore()
        let store = try makeStore(makeTransport(), settings: settings)
        store.setKickoffLead(0)
        #expect(store.settings.kickoffLead == 1)
        store.setKickoffLead(45)
        #expect(settings.load().kickoffLead == 45)
    }

    @Test func appearanceSetterPersists() throws {
        let settings = InMemorySettingsStore()
        let store = try makeStore(makeTransport(), settings: settings)
        store.setAppearance(.dark)
        #expect(store.settings.appearance == .dark)
        #expect(settings.load().appearance == .dark)
        store.setAppearance(.system)
        #expect(settings.load().appearance == .system)
    }

    @Test func languageFollowsTheSystemUntilChosen() throws {
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore(),
                                  locale: Locale(identifier: "es_MX"))
        #expect(store.settings.language == nil)
        #expect(store.language == .spanish)
        // The system's regional formats survive while it speaks the app language.
        #expect(store.locale.identifier == "es_MX")
        #expect(store.display.locale.identifier == "es_MX")
    }

    @Test func anUnshippedSystemLanguageFallsBackToEnglish() throws {
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore(),
                                  locale: Locale(identifier: "nl_NL"))
        #expect(store.language == .english)
        #expect(store.locale.identifier == "en")
    }

    @Test func choosingALanguagePersistsAndSwitchesTheLocale() throws {
        let settings = InMemorySettingsStore()
        let store = try makeStore(makeTransport(), settings: settings)
        store.setLanguage(.japanese)
        #expect(store.settings.language == .japanese)
        #expect(settings.load().language == .japanese)
        #expect(store.language == .japanese)
        #expect(store.locale.identifier == "ja")
        #expect(store.display.locale.identifier == "ja")

        // A relaunch over the same settings keeps the choice.
        let relaunched = try makeStore(makeTransport(), settings: settings)
        #expect(relaunched.language == .japanese)

        store.setLanguage(nil)
        #expect(settings.load().language == nil)
        #expect(store.language == .english)
        #expect(store.locale.identifier == "en_US")
    }

    @Test func leagueSwitchesPersistAndKeepOneLeagueOn() throws {
        var saved = AppSettings()
        saved.setLeagues(["eng.1", "ita.1"])
        let settings = InMemorySettingsStore(saved)
        let store = try makeStore(makeTransport(), settings: settings)
        store.setLeague("ita.1", enabled: false)
        #expect(settings.load().leagues == ["eng.1"])
        #expect(!store.canDisableLeague("eng.1"))
        store.setLeague("eng.1", enabled: false)
        #expect(store.settings.leagues == ["eng.1"])
        store.setLeague("esp.1", enabled: true)
        #expect(settings.load().leagues == ["esp.1", "eng.1"])
        #expect(store.canDisableLeague("eng.1"))
    }

    @Test func countryOptionsStartWithAutomaticThenNamedCatalogCountries() throws {
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore())
        let options = store.countryOptions
        #expect(options.first == CountryOption(code: AppSettings.automaticCountry, label: "Automatic — United States"))
        #expect(options.dropFirst().map(\.code) == ["CA", "IE", "IT", "MX", "ES", "GB", "US"])
        #expect(options.last?.label == "United States")
    }

    @Test func countryOptionsSortInTheResolverLocale() throws {
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore(),
                                  countryLocale: Locale(identifier: "es_ES"))
        #expect(store.countryOptions.dropFirst().map(\.code) == ["CA", "ES", "US", "IE", "IT", "MX", "GB"])
    }

    @Test func aCountryOutsideTheCatalogStaysSelectable() throws {
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore())
        store.updateSettings { $0.country = "fr" }
        #expect(store.countryOptions.last == CountryOption(code: "FR", label: "France"))
        #expect(store.selectedCountry == "FR")
        store.updateSettings { $0.country = AppSettings.automaticCountry }
        #expect(store.selectedCountry == AppSettings.automaticCountry)
    }

    @Test func refreshNowRefetchesFreshData() async throws {
        var saved = AppSettings()
        saved.setLeagues(["eng.1"])
        let transport = makeTransport()
        let store = try makeStore(transport, settings: InMemorySettingsStore(saved))
        await store.refresh()
        await transport.resetRequests()

        await store.refresh()
        #expect(await transport.requestedURLs.isEmpty)
        await store.refreshNow()
        #expect(await transport.requestedURLs.count == 15)
    }

    @Test func watchOptionsUseTheResolvedCountry() async throws {
        var saved = AppSettings()
        saved.setLeagues(["eng.1"])
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore(saved))
        await store.refresh()
        let match = try #require(store.snapshot.matches.first)
        #expect(store.countryCode == "US")
        #expect(!store.watchOptions(for: match).services.isEmpty)

        store.updateSettings { $0.country = "GB" }
        #expect(store.countryCode == "GB")
        #expect(store.watchOptions(for: match).services.map(\.id) == ["skysports", "tnt"])
        #expect(store.footnote == "Where to watch shows 2026-27 rights holders for United Kingdom.")
    }

    @Test func locationLabelNamesTheWatchCountry() throws {
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore())
        // Automatic: the system region (the UTC test time zone has no city).
        #expect(store.locationLabel == "United States")
        store.updateSettings { $0.country = "ES" }
        #expect(store.locationLabel == "Spain")
    }

    @Test func liveElsewhereRowsShowOtherLiveMatches() async throws {
        var saved = AppSettings()
        saved.setLeagues(["eng.1"])
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore(saved))
        await store.refresh()
        let rows = store.liveElsewhereRows
        #expect(rows.map(\.id) == store.liveElsewhere.map(\.id))
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.isLive && !$0.isFollowed && $0.showLeague })
        #expect(rows.first?.status == "HT")
    }

    @Test func refreshNotifiesFollowedTeamsOnce() async throws {
        // Bournemouth beat Sunderland 2–1 at 13:00 UTC, three hours before `now`.
        let bournemouth = Team(id: "349", leagueID: "eng.1", name: "AFC Bournemouth", shortName: "Bournemouth",
                               abbreviation: "BOU")
        let saved = Make.settings(following: [bournemouth], leagues: ["eng.1"])
        let sender = RecordingSender()
        let memory = InMemoryNotificationMemoryStore()
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore(saved),
                                  notifier: MatchNotifier(sender: sender, memoryStore: memory))
        await store.refresh()
        await store.refresh()
        #expect(sender.notifications.map(\.title) == ["Full time · Win for Bournemouth"])
        #expect(sender.notifications.first?.body == "Bournemouth 2–1 Sunderland")
        #expect(sender.notifications.first?.url?.absoluteString.contains("401879263") == true)
        #expect(memory.load().final.keys.contains("401879263"))
    }

    @Test func sendTestNotificationUsesTheNotifier() throws {
        let sender = RecordingSender()
        let store = try makeStore(makeTransport(), settings: InMemorySettingsStore(),
                                  notifier: MatchNotifier(sender: sender, memoryStore: InMemoryNotificationMemoryStore()))
        store.sendTestNotification()
        #expect(sender.notifications == [.test])
    }

    @Test func refreshLoopRunsUntilStopped() async throws {
        var saved = AppSettings()
        saved.setLeagues(["eng.1"])
        let transport = makeTransport()
        let store = try makeStore(transport, settings: InMemorySettingsStore(saved), tick: .milliseconds(20))
        store.start()
        for _ in 0..<200 where store.snapshot.status != .ok {
            try await Task.sleep(for: .milliseconds(10))
        }
        store.stop()
        #expect(store.snapshot.status == .ok)
        #expect(!store.isRunning)
    }
}
