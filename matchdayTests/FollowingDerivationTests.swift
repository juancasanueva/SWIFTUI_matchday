//
//  FollowingDerivationTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Display context")
struct DisplayContextTests {
    /// Wednesday, October 21 2026, 17:07 UTC.
    let display = Make.display(utcDate(2026, 10, 21, 17, 7))

    @Test func dayLabelsAreRelativeNearToday() {
        #expect(display.dayLabel(utcDate(2026, 10, 21, 23, 59)) == "Today")
        #expect(display.dayLabel(utcDate(2026, 10, 22, 0, 30)) == "Tomorrow")
        #expect(display.dayLabel(utcDate(2026, 10, 20, 12)) == "Yesterday")
        #expect(display.dayLabel(utcDate(2026, 10, 23, 19)) == "Fri, Oct 23")
        #expect(display.dayLabel(utcDate(2026, 10, 18, 19)) == "Sun, Oct 18")
    }

    @Test func sectionLabelsAddTheDateToRelativeDays() {
        #expect(display.sectionLabel(utcDate(2026, 10, 21, 21)) == "TODAY · WED, OCT 21")
        #expect(display.sectionLabel(utcDate(2026, 10, 22, 21)) == "TOMORROW · THU, OCT 22")
        #expect(display.sectionLabel(utcDate(2026, 10, 20, 21)) == "YESTERDAY · TUE, OCT 20")
        #expect(display.sectionLabel(utcDate(2026, 10, 23, 21)) == "FRI, OCT 23")
    }

    @Test func timeLabelUsesTheLocaleShortTime() {
        #expect(display.timeLabel(utcDate(2026, 10, 21, 21)) == "9:00 PM")
        #expect(display.timeLabel(utcDate(2026, 10, 21, 9, 5)) == "9:05 AM")
    }

    static let countdownCases: [(TimeInterval, String)] = [
        (0, "kicking off"),
        (-30, "kicking off"),
        (45, "in 45s"),
        (600, "in 10m"),
        (13_980, "in 3h 53m"),
        (11_100, "in 3h 05m"),
        (183_659, "in 2d 3h"),
    ]

    @Test(arguments: countdownCases)
    func countdown(seconds: TimeInterval, expected: String) {
        #expect(display.countdown(to: display.now.addingTimeInterval(seconds)) == expected)
    }

    static let ordinalCases: [(Int, String)] = [
        (1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (9, "9th"), (11, "11th"), (12, "12th"),
        (13, "13th"), (20, "20th"), (21, "21st"), (22, "22nd"), (23, "23rd"), (101, "101st"), (111, "111th"),
    ]

    @Test(arguments: ordinalCases)
    func ordinals(rank: Int, expected: String) {
        #expect(display.ordinal(rank) == expected)
    }

    /// Ordinals follow the app locale, not English suffixes.
    @Test(arguments: [("fr", "1er"), ("es", "1.º"), ("de", "1."), ("it", "1º"), ("ja", "第1")])
    func ordinalsFollowTheLocale(identifier: String, expected: String) {
        let display = DisplayContext(now: display.now, calendar: utcCalendar(), locale: Locale(identifier: identifier))
        #expect(display.ordinal(1) == expected)
    }

    /// The short date follows the locale's field order.
    @Test func shortDateFollowsTheLocale() {
        let german = DisplayContext(now: display.now, calendar: utcCalendar(), locale: Locale(identifier: "de_DE"))
        #expect(german.shortDate(utcDate(2026, 10, 23, 19)) == "Fr. 23. Okt.")
    }

    @Test func liveMinuteAndStatusText() {
        let home = Make.team("a"), away = Make.team("b")
        let kickoff = utcDate(2026, 10, 21, 21)
        let live = Make.match("1", home: home, away: away, at: kickoff, state: .in, score: (1, 0),
                              status: "STATUS_SECOND_HALF", detail: "67'", clock: "67'")
        let halftime = Make.match("2", home: home, away: away, at: kickoff, state: .in, score: (0, 0),
                                  status: "STATUS_HALFTIME", detail: "HT", clock: "45'")
        let noClock = Make.match("3", home: home, away: away, at: kickoff, state: .in, status: "STATUS_FIRST_HALF")
        let final = Make.match("4", home: home, away: away, at: kickoff, state: .post, score: (2, 1),
                               status: "STATUS_FULL_TIME", detail: "FT")
        let finalNoDetail = Make.match("5", home: home, away: away, at: kickoff, state: .post, score: (2, 1))
        let postponed = Make.match("6", home: home, away: away, at: kickoff, state: .post,
                                   status: "STATUS_POSTPONED", detail: "Postponed", completed: false)
        let scheduled = Make.match("7", home: home, away: away, at: kickoff)

        #expect(display.minute(live) == "67'")
        #expect(display.minute(halftime) == "HT")
        #expect(display.minute(noClock) == "LIVE")
        #expect(display.statusText(live) == "67'")
        #expect(display.statusText(final) == "FT")
        #expect(display.statusText(finalNoDetail) == "FT")
        #expect(display.statusText(postponed) == "PPD")
        #expect(display.statusText(scheduled) == "9:00 PM")
    }
}

@Suite("Following cards")
struct FollowingDerivationTests {
    let now = utcDate(2026, 10, 21, 17, 7)
    let madrid = Make.team("86", abbreviation: "RMA", short: "Real Madrid", color: "#ffffff")
    let sevilla = Make.team("243", abbreviation: "SEV", short: "Sevilla")
    let getafe = Make.team("2922", abbreviation: "GET", short: "Getafe")
    let valencia = Make.team("94", abbreviation: "VAL", short: "Valencia")
    let atletico = Make.team("1068", abbreviation: "ATM", short: "Atlético")
    let arsenal = Make.team("359", league: "eng.1", abbreviation: "ARS", short: "Arsenal")
    let chelsea = Make.team("363", league: "eng.1", abbreviation: "CHE", short: "Chelsea")
    let roma = Make.team("104", league: "ita.1", abbreviation: "ROM", short: "Roma")
    let lazio = Make.team("110", league: "ita.1", abbreviation: "LAZ", short: "Lazio")

    let tv = WatchOptions(source: .rights, verified: true,
                          services: [Make.broadcaster("Movistar Plus+"), Make.broadcaster("DAZN")])

    private func cards(_ snapshot: MatchSnapshot, following teams: [Team]) -> [FollowingCard] {
        let tv = tv
        return Derivations.followingCards(snapshot: snapshot, settings: Make.settings(following: teams),
                                          display: Make.display(now), watch: { _ in tv })
    }

    private var madridMatches: [Match] {
        [
            Make.match("v", home: valencia, away: madrid, at: utcDate(2026, 10, 14, 19), state: .post, score: (1, 1)),
            Make.match("g", home: madrid, away: getafe, at: utcDate(2026, 10, 18, 19), state: .post, score: (2, 1)),
            Make.match("s", home: madrid, away: sevilla, at: utcDate(2026, 10, 21, 21),
                       venue: "Santiago Bernabéu", city: "Madrid"),
            Make.match("a", home: atletico, away: madrid, at: utcDate(2026, 10, 25, 16)),
        ]
    }

    private var madridTable: [String: [StandingGroup]] {
        let entry = StandingEntry(rank: 9, team: madrid, played: 2, wins: 2, draws: 0, losses: 0,
                                  goalDifference: 3, points: 6, zone: nil)
        return ["esp.1": [StandingGroup(name: "", entries: [entry])]]
    }

    @Test func cardCollectsNextLastThenFormAndStanding() throws {
        let snapshot = Make.snapshot(madridMatches, tables: madridTable, teams: ["esp.1": [madrid]])
        let card = try #require(cards(snapshot, following: [madrid]).first)

        #expect(card.live == nil)
        #expect(card.next?.id == "s")
        #expect(card.after?.id == "a")
        #expect(card.last?.id == "g")
        #expect(card.colorHex == "#ffffff")
        #expect(card.form == [
            FormResult(matchID: "v", outcome: .draw, score: "1–1", opponent: "Valencia", isHome: false),
            FormResult(matchID: "g", outcome: .win, score: "2–1", opponent: "Getafe", isHome: true),
        ])
        #expect(card.lastResult?.summary() == "2–1 vs Getafe")
        #expect(card.form.first?.summary() == "1–1 at Valencia")
        #expect(card.standing?.text() == "9th · 6 pts · 2 played")
        #expect(card.kicker == "NEXT · TODAY · 9:00 PM")
        #expect(card.countdown == "in 3h 53m")
        #expect(card.venue == "Santiago Bernabéu, Madrid")
        #expect(card.watch == tv)
        #expect(card.thenText == "THEN at Atlético · Sun, Oct 25")
        #expect(card.liveEvents.isEmpty)
    }

    @Test func liveCardShowsMinuteAndKeyEvents() throws {
        let events = [
            Make.goal("Vinícius Júnior", "12'", team: madrid),
            Make.goal("Isco", "40'", team: sevilla, side: .away, kind: .penalty),
            KeyEvent(kind: .redCard, minute: "55'", player: "Rüdiger", teamID: madrid.id, side: .home),
        ]
        let live = Make.match("s", home: madrid, away: sevilla, at: utcDate(2026, 10, 21, 16), state: .in,
                              score: (1, 1), status: "STATUS_SECOND_HALF", detail: "67'", clock: "67'",
                              events: events, venue: "Santiago Bernabéu")
        let card = try #require(cards(Make.snapshot([live]), following: [madrid]).first)
        #expect(card.live?.id == "s")
        #expect(card.featured?.id == "s")
        #expect(card.kicker == "LIVE 67'")
        #expect(card.countdown == nil)
        #expect(card.venue == nil)
        #expect(card.liveEvents.map { $0.label() } == ["Vinícius Júnior 12'", "Isco 40' (P)", "Rüdiger 55'"])
    }

    @Test func formKeepsTheLastFiveResults() throws {
        let opponents = (0..<7).map { Make.team("o\($0)", short: "Opp \($0)") }
        let played = opponents.enumerated().map { index, opponent in
            Make.match("p\(index)", home: madrid, away: opponent, at: utcDate(2026, 10, 1 + index, 19),
                       state: .post, score: (index, 1))
        }
        let card = try #require(cards(Make.snapshot(played), following: [madrid]).first)
        #expect(card.form.map(\.matchID) == ["p2", "p3", "p4", "p5", "p6"])
        #expect(card.form.map(\.outcome) == [.win, .win, .win, .win, .win])
        #expect(card.next == nil)
        #expect(card.kicker == nil)
        #expect(card.thenText == nil)
    }

    @Test func postponedAndLongStaleFixturesAreNotNext() throws {
        let stale = Make.match("old", home: madrid, away: sevilla, at: now.addingTimeInterval(-4 * 3600))
        let postponed = Make.match("ppd", home: madrid, away: getafe, at: now.addingTimeInterval(3600),
                                   status: "STATUS_POSTPONED")
        let lateStart = Make.match("late", home: madrid, away: valencia, at: now.addingTimeInterval(-2 * 3600))
        let card = try #require(cards(Make.snapshot([stale, postponed, lateStart]), following: [madrid]).first)
        #expect(card.next?.id == "late")
        #expect(card.countdown == "kicking off")
        #expect(card.after == nil)
    }

    @Test func otherLeaguesOfTheSameTeamIDAreIgnored() throws {
        let cup = Make.team("86", league: "uefa.champions", abbreviation: "RMA", short: "Real Madrid")
        let ucl = Make.match("ucl", home: cup, away: Make.team("x", league: "uefa.champions"),
                             at: utcDate(2026, 10, 22, 19))
        let card = try #require(cards(Make.snapshot([ucl]), following: [madrid]).first)
        #expect(card.next == nil)
    }

    @Test func groupStandingNamesTheGroup() throws {
        let entry = StandingEntry(rank: 1, team: arsenal, played: 3, wins: 3, draws: 0, losses: 0,
                                  goalDifference: 5, points: 9, zone: nil)
        let tables = ["eng.1": [StandingGroup(name: "Eastern Conference", entries: [entry])]]
        let card = try #require(cards(Make.snapshot([], tables: tables), following: [arsenal]).first)
        #expect(card.standing?.text() == "1st in Eastern · 9 pts · 3 played")
    }

    @Test func liveFirstThenByKickoffThenNothingScheduledInFollowOrder() {
        let roma = roma
        let snapshot = Make.snapshot([
            Make.match("later", home: madrid, away: sevilla, at: utcDate(2026, 10, 24, 19)),
            Make.match("sooner", home: chelsea, away: Make.team("x", league: "eng.1"), at: utcDate(2026, 10, 22, 19)),
            Make.match("live", home: arsenal, away: Make.team("y", league: "eng.1"), at: utcDate(2026, 10, 21, 16),
                       state: .in, score: (0, 0)),
        ])
        let order = cards(snapshot, following: [roma, madrid, lazio, chelsea, arsenal]).map(\.favorite.teamID)
        #expect(order == [arsenal.id, chelsea.id, madrid.id, roma.id, lazio.id])
    }

    @Test func liveElsewhereSkipsFollowedMatchesAndDisabledLeagues() {
        let snapshot = Make.snapshot([
            Make.match("mine", home: madrid, away: sevilla, at: now, state: .in, score: (0, 0)),
            Make.match("other", home: getafe, away: valencia, at: now, state: .in, score: (1, 0)),
            Make.match("done", home: atletico, away: valencia, at: now, state: .post, score: (1, 0)),
            Make.match("italy", home: roma, away: lazio, at: now, state: .in, score: (0, 0)),
        ])
        let settings = Make.settings(following: [madrid], leagues: ["esp.1"])
        let others = Derivations.liveElsewhere(snapshot: snapshot, settings: settings, display: Make.display(now))
        #expect(others.map(\.id) == ["other"])
    }
}
