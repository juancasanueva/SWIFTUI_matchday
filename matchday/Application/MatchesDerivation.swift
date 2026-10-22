//
//  MatchesDerivation.swift
//  matchday
//
//  The Matches and Tables tabs (`daySections`, `MatchRow`, the table groups
//  and zone legend in Panel.qml).
//

import Foundation

nonisolated enum MatchFilter: Hashable, Sendable {
    case all
    /// Matches of followed teams.
    case mine
    case league(String)

    func includes(_ match: Match, settings: AppSettings) -> Bool {
        switch self {
        case .all: true
        case .mine: Derivations.isFollowed(match, settings: settings)
        case .league(let id): match.leagueID == id
        }
    }

    /// Rows show their league only when the list mixes leagues.
    var showsLeague: Bool {
        if case .league = self { return false }
        return true
    }
}

nonisolated struct MatchRowItem: Identifiable, Hashable, Sendable {
    let match: Match
    let isFollowed: Bool
    /// Kickoff time, live minute, "FT" or "PPD".
    let status: String
    /// Up to three channels, before kickoff only.
    let channels: [String]
    /// "Player 12' · Player 80' (P)" for live or followed matches.
    let scorers: String?
    let showLeague: Bool

    var id: String { match.id }
    var isLive: Bool { match.isLive }
}

nonisolated struct DaySection: Identifiable, Hashable, Sendable {
    /// Start of the local day.
    let day: Date
    /// "TODAY · WED OCT 21", "FRI OCT 23".
    let label: String
    let liveCount: Int
    let isPast: Bool
    /// The first results section, where the "RESULTS" divider goes.
    let isFirstPast: Bool
    let rows: [MatchRowItem]

    var id: Date { day }
}

nonisolated struct TableRowItem: Identifiable, Hashable, Sendable {
    let entry: StandingEntry
    let isFollowed: Bool

    var id: String { entry.team.id }
}

nonisolated struct TableGroupItem: Identifiable, Hashable, Sendable {
    /// Group name; empty for single tables.
    let name: String
    let rows: [TableRowItem]

    var id: String { name }
    var containsFollowed: Bool { rows.contains(where: \.isFollowed) }
}

nonisolated extension Derivations {
    static let rowChannelLimit = 3

    // MARK: Matches

    /// Today and later days ascending, then past days newest first.
    static func daySections(
        snapshot: MatchSnapshot,
        settings: AppSettings,
        filter: MatchFilter,
        display: DisplayContext,
        watch: (Match) -> WatchOptions
    ) -> [DaySection] {
        let matches = windowMatches(snapshot: snapshot, settings: settings, display: display)
            .filter { filter.includes($0, settings: settings) }
        let byDay = Dictionary(grouping: matches) { display.calendar.startOfDay(for: $0.kickoff) }
        let upcoming = byDay.keys.filter { $0 >= display.today }.sorted()
        let past = byDay.keys.filter { $0 < display.today }.sorted(by: >)

        return (upcoming + past).enumerated().map { index, day in
            let items = byDay[day] ?? []
            let isPast = day < display.today
            return DaySection(
                day: day,
                label: display.sectionLabel(day),
                liveCount: items.filter(\.isLive).count,
                isPast: isPast,
                isFirstPast: isPast && index == upcoming.count,
                rows: items.map { row(for: $0, settings: settings, filter: filter, display: display, watch: watch) }
            )
        }
    }

    static func row(
        for match: Match,
        settings: AppSettings,
        filter: MatchFilter,
        display: DisplayContext,
        watch: (Match) -> WatchOptions
    ) -> MatchRowItem {
        let followed = isFollowed(match, settings: settings)
        var channels: [String] = []
        var scorers: String?
        if match.state == .pre {
            channels = watch(match).names(limit: rowChannelLimit)
        } else if followed || match.isLive {
            let goals = match.keyEvents.filter(\.isGoal).map { $0.label(locale: display.locale, bundle: display.bundle) }
            scorers = goals.isEmpty ? nil : goals.joined(separator: " · ")
        }
        return MatchRowItem(match: match, isFollowed: followed, status: display.statusText(match),
                            channels: channels, scorers: scorers, showLeague: filter.showsLeague)
    }

    // MARK: Tables

    /// League shown by the Tables or Teams picker: the selection while it is enabled,
    /// else the first followed team's league (Tables, `tableLeague`), else the first
    /// enabled league.
    static func pickerLeague(selected: String?, settings: AppSettings, preferFollowed: Bool) -> String {
        let enabled = settings.leagues
        if let selected, enabled.contains(selected) { return selected }
        if preferFollowed, let followed = settings.favorites.map(\.leagueID).first(where: enabled.contains) {
            return followed
        }
        return enabled.first ?? League.laLiga.id
    }

    /// A league's table groups, groups with a followed team first (Nations League has 14).
    static func tableGroups(league: String, snapshot: MatchSnapshot, settings: AppSettings) -> [TableGroupItem] {
        let groups = (snapshot.tables[league] ?? []).map { group in
            TableGroupItem(name: group.name, rows: group.entries.map { entry in
                TableRowItem(entry: entry, isFollowed: settings.isFollowing(leagueID: league, teamID: entry.team.id))
            })
        }
        return groups.filter(\.containsFollowed) + groups.filter { !$0.containsFollowed }
    }

    /// Each described zone once, in table order.
    static func zoneLegend(_ groups: [TableGroupItem]) -> [StandingZone] {
        var seen: Set<String> = []
        return groups.flatMap(\.rows).compactMap(\.entry.zone).filter { zone in
            !zone.description.isEmpty && seen.insert(zone.description).inserted
        }
    }
}
