//
//  MatchesFeedTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Matches feed")
struct MatchesFeedTests {
    /// Wednesday, October 21 2026, 17:07 UTC.
    let now = utcDate(2026, 10, 21, 17, 7)
    let madrid = Make.team("86", abbreviation: "RMA", short: "Real Madrid")
    let sevilla = Make.team("243", abbreviation: "SEV", short: "Sevilla")
    let getafe = Make.team("2922", abbreviation: "GET", short: "Getafe")
    let valencia = Make.team("94", abbreviation: "VAL", short: "Valencia")
    let arsenal = Make.team("359", league: "eng.1", abbreviation: "ARS", short: "Arsenal")
    let chelsea = Make.team("363", league: "eng.1", abbreviation: "CHE", short: "Chelsea")
    let roma = Make.team("104", league: "ita.1", abbreviation: "ROM", short: "Roma")
    let lazio = Make.team("110", league: "ita.1", abbreviation: "LAZ", short: "Lazio")

    let tv = WatchOptions(source: .rights, verified: true, services: ["DAZN", "Movistar", "Sky", "Fubo"].map {
        Make.broadcaster($0)
    })

    private var snapshot: MatchSnapshot {
        Make.snapshot([
            Make.match("old", home: madrid, away: getafe, at: utcDate(2026, 10, 17, 19), state: .post, score: (3, 0)),
            Make.match("sun", home: getafe, away: valencia, at: utcDate(2026, 10, 18, 19), state: .post, score: (1, 0),
                       events: [Make.goal("Mayoral", "50'", team: getafe)]),
            Make.match("sunFav", home: madrid, away: valencia, at: utcDate(2026, 10, 18, 21), state: .post,
                       score: (2, 1), detail: "FT",
                       events: [Make.goal("Mbappé", "10'", team: madrid, kind: .penalty),
                                Make.goal("Hugo Duro", "30'", team: valencia, side: .away),
                                Make.goal("Bellingham", "88'", team: madrid)]),
            Make.match("tue", home: arsenal, away: chelsea, at: utcDate(2026, 10, 20, 19), state: .post, score: (0, 0)),
            Make.match("live", home: sevilla, away: getafe, at: utcDate(2026, 10, 21, 16), state: .in, score: (1, 0),
                       status: "STATUS_SECOND_HALF", detail: "67'", clock: "67'",
                       events: [Make.goal("Lukébakio", "20'", team: sevilla)]),
            Make.match("tonight", home: madrid, away: sevilla, at: utcDate(2026, 10, 21, 21)),
            Make.match("thu", home: roma, away: lazio, at: utcDate(2026, 10, 22, 19)),
            Make.match("ppd", home: valencia, away: getafe, at: utcDate(2026, 10, 23, 19), state: .post,
                       status: "STATUS_POSTPONED", detail: "Postponed", completed: false),
            Make.match("far", home: madrid, away: getafe, at: utcDate(2026, 10, 31, 19)),
        ])
    }

    private func sections(_ filter: MatchFilter, leagues: [String]? = nil) -> [DaySection] {
        let tv = tv
        return Derivations.daySections(snapshot: snapshot, settings: Make.settings(following: [madrid], leagues: leagues),
                                       filter: filter, display: Make.display(now), watch: { _ in tv })
    }

    @Test func upcomingDaysAscendThenResultsNewestFirst() {
        let all = sections(.all)
        #expect(all.map(\.label) == [
            "TODAY · WED OCT 21", "TOMORROW · THU OCT 22", "FRI OCT 23",
            "YESTERDAY · TUE OCT 20", "SUN OCT 18",
        ])
        #expect(all.map(\.isPast) == [false, false, false, true, true])
        #expect(all.map(\.isFirstPast) == [false, false, false, true, false])
        #expect(all[0].liveCount == 1)
        #expect(all[1].liveCount == 0)
        #expect(all[4].rows.map(\.id) == ["sun", "sunFav"])
    }

    @Test func windowDropsDaysOutsideThePollingRange() {
        let ids = sections(.all).flatMap(\.rows).map(\.id)
        #expect(!ids.contains("old"))
        #expect(!ids.contains("far"))
    }

    @Test func mineAndLeagueFilters() {
        #expect(sections(.mine).flatMap(\.rows).map(\.id) == ["tonight", "sunFav"])
        #expect(sections(.league("ita.1")).flatMap(\.rows).map(\.id) == ["thu"])
    }

    @Test func disabledLeaguesAreHidden() {
        let ids = sections(.all, leagues: ["esp.1"]).flatMap(\.rows).map(\.id)
        #expect(!ids.contains("tue"))
        #expect(!ids.contains("thu"))
    }

    @Test func rowsCarryStatusChannelsAndScorers() throws {
        let rows = Dictionary(uniqueKeysWithValues: sections(.all).flatMap(\.rows).map { ($0.id, $0) })

        let tonight = try #require(rows["tonight"])
        #expect(tonight.status == "9:00 PM")
        #expect(tonight.isFollowed)
        #expect(tonight.channels == ["DAZN", "Movistar", "Sky"])
        #expect(tonight.scorers == nil)

        let live = try #require(rows["live"])
        #expect(live.isLive)
        #expect(live.status == "67'")
        #expect(!live.isFollowed)
        #expect(live.channels.isEmpty)
        #expect(live.scorers == "Lukébakio 20'")

        let followedResult = try #require(rows["sunFav"])
        #expect(followedResult.status == "FT")
        #expect(followedResult.scorers == "Mbappé 10' (P) · Hugo Duro 30' · Bellingham 88'")

        // Other finished matches don't list scorers.
        #expect(rows["sun"]?.scorers == nil)
        #expect(rows["ppd"]?.status == "PPD")
    }

    @Test func leagueBadgeOnlyInMixedFilters() {
        let all = sections(.all).flatMap(\.rows).map(\.showLeague)
        let mine = sections(.mine).flatMap(\.rows).map(\.showLeague)
        let spain = sections(.league("esp.1")).flatMap(\.rows).map(\.showLeague)
        #expect(!all.contains(false))
        #expect(!mine.contains(false))
        #expect(!spain.isEmpty && !spain.contains(true))
    }
}

@Suite("Tables")
struct TablesDerivationTests {
    let arsenal = Make.team("359", league: "uefa.nations", abbreviation: "ENG", short: "England")

    private func entry(_ rank: Int, _ team: Team, zone: StandingZone? = nil) -> StandingEntry {
        StandingEntry(rank: rank, team: team, played: 1, wins: 0, draws: 0, losses: 0,
                      goalDifference: 0, points: 0, zone: zone)
    }

    @Test func groupsWithAFollowedTeamComeFirst() {
        let league = "uefa.nations"
        let groups = ["A", "B", "C", "D"].map { name in
            StandingGroup(name: "Group \(name)", entries: [entry(1, Make.team("t\(name)", league: league))])
        } + [StandingGroup(name: "Group E", entries: [entry(1, arsenal)])]
        let snapshot = Make.snapshot([], tables: [league: groups])
        let items = Derivations.tableGroups(league: league, snapshot: snapshot,
                                            settings: Make.settings(following: [arsenal]))
        #expect(items.map(\.name) == ["Group E", "Group A", "Group B", "Group C", "Group D"])
        #expect(items[0].containsFollowed)
        #expect(items[0].rows[0].isFollowed)
        #expect(!items[1].containsFollowed)
    }

    @Test func missingTableIsEmpty() {
        #expect(Derivations.tableGroups(league: "eng.1", snapshot: Make.snapshot([]), settings: AppSettings()).isEmpty)
    }

    @Test func zoneLegendListsEachZoneOnce() {
        let ucl = StandingZone(colorHex: "#81d6ac", description: "Champions League")
        let uel = StandingZone(colorHex: "#b2d7f9", description: "Europa League")
        let blank = StandingZone(colorHex: "#ff0000", description: "")
        let rows = [
            entry(1, Make.team("a"), zone: ucl), entry(2, Make.team("b"), zone: ucl),
            entry(3, Make.team("c"), zone: uel), entry(4, Make.team("d")), entry(5, Make.team("e"), zone: blank),
        ]
        let snapshot = Make.snapshot([], tables: ["esp.1": [StandingGroup(name: "", entries: rows)]])
        let groups = Derivations.tableGroups(league: "esp.1", snapshot: snapshot, settings: AppSettings())
        #expect(Derivations.zoneLegend(groups) == [ucl, uel])
    }

    @Test func pickerKeepsAnEnabledSelection() {
        let settings = Make.settings(following: [arsenal])
        #expect(Derivations.pickerLeague(selected: "ita.1", settings: settings, preferFollowed: true) == "ita.1")
    }

    @Test func pickerStartsAtTheFirstFollowedTeamsLeague() {
        let settings = Make.settings(following: [arsenal])
        #expect(Derivations.pickerLeague(selected: nil, settings: settings, preferFollowed: true) == "uefa.nations")
        #expect(Derivations.pickerLeague(selected: nil, settings: settings, preferFollowed: false) == "esp.1")
    }

    @Test func pickerSkipsDisabledLeagues() {
        let settings = Make.settings(following: [arsenal], leagues: ["ita.1", "eng.1"])
        #expect(Derivations.pickerLeague(selected: "esp.1", settings: settings, preferFollowed: true) == "ita.1")
        #expect(Derivations.pickerLeague(selected: nil, settings: settings, preferFollowed: true) == "ita.1")
    }
}

@Suite("Header and menu bar")
struct HeaderAndBarTests {
    let now = utcDate(2026, 10, 21, 17, 7)
    let madrid = Make.team("86", abbreviation: "RMA", short: "Real Madrid")
    let sevilla = Make.team("243", abbreviation: "SEV", short: "Sevilla")
    let getafe = Make.team("2922", abbreviation: "GET", short: "Getafe")
    let valencia = Make.team("94", abbreviation: "VAL", short: "Valencia")
    let tv = WatchOptions(source: .rights, verified: true,
                          services: ["Movistar Plus+", "DAZN", "Sky"].map { Make.broadcaster($0) })

    private func state(_ snapshot: MatchSnapshot, following teams: [Team], barScore: Bool = true)
        -> (header: String, bar: BarState) {
        let settings = Make.settings(following: teams, barScore: barScore)
        let display = Make.display(now)
        let tv = tv
        let cards = Derivations.followingCards(snapshot: snapshot, settings: settings, display: display,
                                               watch: { _ in tv })
        let window = Derivations.windowMatches(snapshot: snapshot, settings: settings, display: display)
        return (Derivations.headerSummary(snapshot: snapshot, cards: cards, window: window, display: display),
                Derivations.barState(cards: cards, settings: settings, display: display))
    }

    private var tonight: Match { Make.match("t", home: madrid, away: sevilla, at: utcDate(2026, 10, 21, 21)) }
    private var liveDerby: Match {
        Make.match("l", home: madrid, away: getafe, at: utcDate(2026, 10, 21, 16), state: .in, score: (2, 1),
                   status: "STATUS_SECOND_HALF", detail: "67'", clock: "67'")
    }

    @Test func loadingAndOffline() {
        #expect(state(Make.snapshot([], status: .loading), following: []).header == "LOADING FIXTURES…")
        #expect(state(Make.snapshot([], status: .offline, error: "The Internet connection appears to be offline."),
                      following: []).header == "OFFLINE · THE INTERNET CONNECTION APPEARS TO BE OFFLINE.")
        #expect(state(Make.snapshot([], status: .offline), following: []).header == "OFFLINE · CAN'T REACH ESPN")
    }

    @Test func nextMatchOfFollowedTeams() {
        #expect(state(Make.snapshot([tonight]), following: [madrid]).header == "NEXT RMA V SEV · TODAY 9:00 PM")
    }

    @Test func liveCountsAndStale() {
        let otherLive = Make.match("o", home: valencia, away: sevilla, at: utcDate(2026, 10, 21, 16), state: .in,
                                   score: (0, 0))
        #expect(state(Make.snapshot([liveDerby]), following: [madrid]).header == "1 LIVE")
        #expect(state(Make.snapshot([otherLive, tonight]), following: [madrid]).header
                == "1 LIVE NOW  ·  NEXT RMA V SEV · TODAY 9:00 PM")
        #expect(state(Make.snapshot([otherLive], status: .stale), following: []).header == "1 LIVE NOW  ·  STALE")
    }

    @Test func nothingFollowedCountsTheWeek() {
        let results = [
            Make.match("a", home: valencia, away: sevilla, at: utcDate(2026, 10, 19, 19), state: .post, score: (0, 0)),
            Make.match("b", home: getafe, away: sevilla, at: utcDate(2026, 10, 24, 19)),
        ]
        #expect(state(Make.snapshot(results), following: []).header == "2 MATCHES THIS WEEK")
    }

    @Test func barWithoutFavoritesIsDimmed() {
        let bar = state(Make.snapshot([tonight]), following: []).bar
        #expect(bar.isDimmed)
        #expect(!bar.showDot)
        #expect(!bar.isLive)
        #expect(bar.liveText == nil)
        #expect(bar.tooltip == "Matchday — follow some teams")
    }

    @Test func dotWhenAFollowedTeamPlaysWithinTwelveHours() {
        let bar = state(Make.snapshot([tonight]), following: [madrid]).bar
        #expect(bar.showDot)
        #expect(!bar.isLive)
        #expect(!bar.isDimmed)
        #expect(bar.tooltip == "Real Madrid v Sevilla — Today 9:00 PM  ·  Movistar Plus+, DAZN")

        let later = Make.match("x", home: madrid, away: sevilla, at: now.addingTimeInterval(13 * 3600))
        #expect(!state(Make.snapshot([later]), following: [madrid]).bar.showDot)
    }

    @Test func liveFollowedMatchDrivesTheBarScore() {
        let bar = state(Make.snapshot([liveDerby]), following: [madrid]).bar
        #expect(bar.isLive)
        #expect(bar.showDot)
        #expect(bar.liveText == "RMA 2–1 GET  67'")
        #expect(bar.tooltip == "● Real Madrid 2–1 Getafe  67'")

        let quiet = state(Make.snapshot([liveDerby]), following: [madrid], barScore: false).bar
        #expect(quiet.isLive)
        #expect(quiet.liveText == nil)
    }
}
