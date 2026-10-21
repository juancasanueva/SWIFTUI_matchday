//
//  RefreshPolicyTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Refresh policy")
struct RefreshPolicyTests {
    let now = utcDate(2026, 10, 18, 16)

    private func match(state: MatchState, kickoffOffset: TimeInterval, completed: Bool = false) -> Match {
        let team = Team(id: "1", leagueID: "eng.1", name: "A", shortName: "A", abbreviation: "A")
        let side = MatchSide(team: team, score: nil, winner: false, form: "", record: "")
        return Match(id: "m", leagueID: "eng.1", kickoff: now.addingTimeInterval(kickoffOffset), state: state,
                     statusName: "", shortDetail: "", displayClock: "", completed: completed,
                     home: side, away: side, keyEvents: [], tvNames: [],
                     espnURL: URL(string: "https://www.espn.com")!, venue: "", city: "", week: nil)
    }

    @Test func liveMatchIsHot() {
        #expect(RefreshPolicy.isHot([match(state: .in, kickoffOffset: -1800)], now: now))
    }

    static let preMatchCases: [(TimeInterval, Bool)] = [
        (1140, true),     // kicks off within 20 minutes
        (1260, false),    // too far ahead
        (-1800, true),    // should have started, still "pre"
        (-3660, false),   // more than an hour past kickoff
    ]

    static let scoreboardCases: [(Int, Bool, TimeInterval)] = [
        (-3, false, 21_600), (-2, true, 21_600),
        (-1, false, 300), (0, true, 30), (1, true, 30), (1, false, 300),
        (2, true, 1800), (9, false, 1800),
    ]

    @Test(arguments: preMatchCases)
    func preMatchHotnessWindow(offset: TimeInterval, hot: Bool) {
        #expect(RefreshPolicy.isHot([match(state: .pre, kickoffOffset: offset)], now: now) == hot)
    }

    @Test func unsettledResultIsHotButFinalIsNot() {
        #expect(RefreshPolicy.isHot([match(state: .post, kickoffOffset: -7200, completed: false)], now: now))
        #expect(!RefreshPolicy.isHot([match(state: .post, kickoffOffset: -7200, completed: true)], now: now))
        #expect(!RefreshPolicy.isHot([], now: now))
    }

    @Test(arguments: scoreboardCases)
    func scoreboardTTLTiers(offset: Int, hot: Bool, ttl: TimeInterval) {
        #expect(RefreshPolicy.scoreboardTTL(dayOffset: offset, hot: hot) == ttl)
    }

    @Test func otherTTLs() {
        #expect(RefreshPolicy.standingsTTL(leagueIsLive: true) == 600)
        #expect(RefreshPolicy.standingsTTL(leagueIsLive: false) == 3600)
        #expect(RefreshPolicy.teamsTTL == 86_400)
        #expect(RefreshPolicy.scheduleTTL == 3 * 3600)
        #expect(RefreshPolicy.failureBackoff == 60)
        #expect(RefreshPolicy.dayOffsets == -3...9)
    }
}

@Suite("Data status")
struct DataStatusTests {
    let now = utcDate(2026, 10, 18, 16)

    @Test func offlineWhenNothingAndErrors() {
        #expect(DataStatus.derive(hasMatches: false, hasErrors: true, lastSuccess: nil, now: now) == .offline)
    }

    @Test func loadingWhenNothingYet() {
        #expect(DataStatus.derive(hasMatches: false, hasErrors: false, lastSuccess: nil, now: now) == .loading)
    }

    @Test func staleWhenErrorsAndNoRecentSuccess() {
        let old = now.addingTimeInterval(-301)
        #expect(DataStatus.derive(hasMatches: true, hasErrors: true, lastSuccess: old, now: now) == .stale)
        #expect(DataStatus.derive(hasMatches: true, hasErrors: true, lastSuccess: nil, now: now) == .stale)
    }

    @Test func okOtherwise() {
        let recent = now.addingTimeInterval(-120)
        #expect(DataStatus.derive(hasMatches: true, hasErrors: true, lastSuccess: recent, now: now) == .ok)
        #expect(DataStatus.derive(hasMatches: true, hasErrors: false, lastSuccess: nil, now: now) == .ok)
    }
}
