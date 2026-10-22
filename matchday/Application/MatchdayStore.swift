//
//  MatchdayStore.swift
//  matchday
//
//  App state for the menu bar and panel: the latest snapshot, the settings,
//  and everything derived from them (the original daemon loop plus the
//  computed properties of Panel.qml).
//

import Foundation
import Observation

/// One "Watching from" choice: `auto` or an ISO country code, with its label.
nonisolated struct CountryOption: Identifiable, Hashable, Sendable {
    let code: String
    let label: String

    var id: String { code }
}

@Observable
@MainActor
final class MatchdayStore {
    /// Polling interval of the refresh loop (`TICK`).
    nonisolated static let defaultTick: Duration = .seconds(5)

    private(set) var snapshot = MatchSnapshot()
    private(set) var settings: AppSettings
    /// Clock reading of the last refresh; derived texts are relative to it.
    private(set) var now: Date
    private var refreshesInFlight = 0

    @ObservationIgnored private let repository: MatchRepository
    @ObservationIgnored private let settingsStore: any SettingsStore
    @ObservationIgnored let whereToWatch: WhereToWatch
    /// Names countries in its own locale; `countries` renames them in the app's.
    @ObservationIgnored let countryResolver: CountryResolver
    @ObservationIgnored private let calendar: Calendar
    /// The system locale; `locale` is the one the app draws in.
    @ObservationIgnored private let systemLocale: Locale
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let tick: Duration
    @ObservationIgnored private let notifier: MatchNotifier?
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(
        repository: MatchRepository,
        settingsStore: any SettingsStore,
        whereToWatch: WhereToWatch,
        countryResolver: CountryResolver = .current,
        calendar: Calendar = .current,
        locale: Locale = .current,
        clock: @escaping @Sendable () -> Date = { Date() },
        tick: Duration = MatchdayStore.defaultTick,
        notifier: MatchNotifier? = nil
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.whereToWatch = whereToWatch
        self.countryResolver = countryResolver
        self.calendar = calendar
        self.systemLocale = locale
        self.clock = clock
        self.tick = tick
        self.notifier = notifier
        self.settings = settingsStore.load()
        self.now = clock()
    }

    var isRefreshing: Bool { refreshesInFlight > 0 }
    var isRunning: Bool { loop != nil }

    // MARK: Refreshing

    /// Starts the refresh loop: fetch what is due, then wait one tick.
    func start() {
        guard loop == nil else { return }
        let tick = tick
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: tick)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Fetches whatever is due for the enabled leagues and followed teams.
    func refresh() async {
        refreshesInFlight += 1
        defer { refreshesInFlight -= 1 }
        let current = settings
        let result = await repository.refreshDue(now: clock(), leagues: current.leagues,
                                                 favorites: current.favorites)
        snapshot = result
        now = clock()
        notifier?.process(matches: result.matches, settings: settings, now: now, watch: watchOptions(for:))
    }

    /// The Refresh command: expires every cached response, then refreshes.
    func refreshNow() async {
        await repository.forceRefresh(now: clock())
        await refresh()
    }

    // MARK: Settings

    func toggleFollow(_ team: Team) {
        toggleFollow(FavoriteTeam(team: team))
    }

    func toggleFollow(_ favorite: FavoriteTeam) {
        updateSettings { $0.toggleFollow(favorite) }
    }

    func isFollowing(_ team: Team) -> Bool {
        settings.isFollowing(leagueID: team.leagueID, teamID: team.id)
    }

    /// Applies `change`, persists the result, and refreshes so new teams or leagues load.
    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        let refetch = updated.favorites != settings.favorites || updated.leagues != settings.leagues
        settings = updated
        settingsStore.save(updated)
        if refetch {
            Task { await refresh() }
        }
    }

    /// Minutes before kickoff for the reminder, clamped to `AppSettings.kickoffLeadRange`.
    func setKickoffLead(_ minutes: Int) {
        updateSettings { $0.kickoffLead = minutes }
    }

    func setAppearance(_ mode: AppearanceMode) {
        updateSettings { $0.appearance = mode }
    }

    /// Chooses the app language; `nil` follows the system language again.
    func setLanguage(_ language: AppLanguage?) {
        updateSettings { $0.language = language }
    }

    /// Turns a league on or off; the last enabled league stays on.
    func setLeague(_ id: String, enabled: Bool) {
        updateSettings { $0.setLeague(id, enabled: enabled) }
    }

    func canDisableLeague(_ id: String) -> Bool {
        settings.leagues != [id]
    }

    /// Sends a sample notification so the user can check the alert style
    /// (and grant permission the first time).
    func sendTestNotification() {
        notifier?.sendTest()
    }

    // MARK: Derived state

    /// The language the app draws in: the Settings choice, else the system's.
    var language: AppLanguage {
        settings.language ?? AppLanguage.matching(systemLocale)
    }

    /// Locale of the SwiftUI roots, the language bundle and every derived text.
    var locale: Locale {
        language.locale(preferring: systemLocale)
    }

    /// The `.lproj` bundle of `language`, for texts built outside SwiftUI.
    var bundle: Bundle {
        AppLocalization.bundle(for: language)
    }

    var display: DisplayContext {
        DisplayContext(now: now, calendar: calendar, locale: locale, bundle: bundle)
    }

    /// The country resolver naming countries in the app language.
    private var countries: CountryResolver {
        countryResolver.naming(in: locale)
    }

    /// ISO code used for where-to-watch, or `nil` when the system has no region.
    var countryCode: String? {
        countryResolver.countryCode(for: settings.country)
    }

    /// "Watching from …" text: "Madrid, Spain" when automatic, else the chosen country.
    var locationLabel: String {
        let setting = settings.country.trimmingCharacters(in: .whitespaces)
        if setting.isEmpty || setting == AppSettings.automaticCountry {
            return countries.automaticLabel
        }
        return countryCode.map(countries.countryName(for:)) ?? setting
    }

    /// "Watching from" choices: automatic, then the countries with rights data by
    /// name in the app language, plus a saved country outside the catalog (`countries`).
    var countryOptions: [CountryOption] {
        let countries = countries
        let automatic = CountryOption(
            code: AppSettings.automaticCountry,
            label: display.text("Automatic — \(countries.automaticLabel)",
                                comment: "Watching-from choice that follows the Mac's region. The argument is the detected place."))
        // Sorted in the app locale (the one naming the countries), not the process locale.
        let locale = countries.locale
        var options = whereToWatch.catalog.countryChoices
            .map { CountryOption(code: $0.code, label: countries.countryName(for: $0.code)) }
            .sorted {
                $0.label.compare($1.label, options: [.caseInsensitive, .numeric, .widthInsensitive],
                                 locale: locale) == .orderedAscending
            }
        let selected = selectedCountry
        if selected != AppSettings.automaticCountry && !options.contains(where: { $0.code == selected }) {
            options.append(CountryOption(code: selected, label: countries.countryName(for: selected)))
        }
        return [automatic] + options
    }

    /// The `countryOptions` code matching the saved setting.
    var selectedCountry: String {
        let setting = settings.country.trimmingCharacters(in: .whitespaces)
        if setting.isEmpty || setting == AppSettings.automaticCountry { return AppSettings.automaticCountry }
        return setting.uppercased()
    }

    func watchOptions(for match: Match) -> WatchOptions {
        whereToWatch.options(for: match, country: countryCode, spanish: settings.spanish)
    }

    var footnote: String {
        // `countryName(for:)` falls back to the raw code; only a real name is passed on.
        whereToWatch.footnote(countryCode: countryCode,
                              localizedName: countryCode.flatMap(countries.locale.localizedString(forRegionCode:)),
                              display: display)
    }

    var following: [FollowingCard] {
        Derivations.followingCards(snapshot: snapshot, settings: settings, display: display,
                                   watch: watchOptions(for:))
    }

    var windowMatches: [Match] {
        Derivations.windowMatches(snapshot: snapshot, settings: settings, display: display)
    }

    var liveElsewhere: [Match] {
        Derivations.liveElsewhere(snapshot: snapshot, settings: settings, display: display)
    }

    /// "LIVE ELSEWHERE" rows on the Following tab.
    var liveElsewhereRows: [MatchRowItem] {
        let settings = settings, display = display
        return liveElsewhere.map {
            Derivations.row(for: $0, settings: settings, filter: .all, display: display, watch: watchOptions(for:))
        }
    }

    func daySections(filter: MatchFilter) -> [DaySection] {
        Derivations.daySections(snapshot: snapshot, settings: settings, filter: filter, display: display,
                                watch: watchOptions(for:))
    }

    func tableGroups(league: String) -> [TableGroupItem] {
        Derivations.tableGroups(league: league, snapshot: snapshot, settings: settings)
    }

    var header: String {
        Derivations.headerSummary(snapshot: snapshot, cards: following, window: windowMatches, display: display)
    }

    var bar: BarState {
        Derivations.barState(cards: following, settings: settings, display: display)
    }
}
