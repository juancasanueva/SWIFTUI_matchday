//
//  NotificationPlannerTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Notification planner")
struct NotificationPlannerTests {
    let now = utcDate(2026, 10, 21, 18)
    let madrid = Make.team("86", short: "Real Madrid")
    let barca = Make.team("83", short: "Barcelona")
    let sevilla = Make.team("243", short: "Sevilla")
    let betis = Make.team("244", short: "Betis")

    private func settings(_ change: (inout AppSettings) -> Void = { _ in }) -> AppSettings {
        var settings = Make.settings(following: [madrid])
        change(&settings)
        return settings
    }

    private func plan(_ matches: [Match], settings: AppSettings? = nil,
                      memory: NotificationMemory = NotificationMemory(),
                      at time: Date? = nil,
                      watch: [Broadcaster] = []) -> NotificationPlan {
        NotificationPlanner.plan(
            matches: matches, settings: settings ?? self.settings(), memory: memory, now: time ?? now,
            watch: { _ in WatchOptions(source: .espn, verified: true, services: watch) })
    }

    /// Memory that has already seen `match` at `score` (the previous refresh).
    private func seen(_ match: Match, score: String, at time: Date? = nil) -> NotificationMemory {
        var memory = NotificationMemory()
        memory.scores[match.id] = NotificationMemory.Score(value: score, at: time ?? now)
        return memory
    }

    // MARK: Kickoff

    @Test func kickoffReminderInsideTheLeadNamesTheChannels() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(9 * 60 + 40))
        let result = plan([match], watch: [Make.broadcaster("DAZN"), Make.broadcaster("Movistar"),
                                           Make.broadcaster("ESPN+"), Make.broadcaster("Fox")])
        #expect(result.notifications == [MatchNotification(
            id: "kick-1", title: "Real Madrid vs Barcelona in 10 min", body: "Watch on DAZN, Movistar, ESPN+",
            url: match.espnURL, team: madrid)])
        #expect(result.memory.kickoff["1"] == now)
    }

    @Test func kickoffReminderWithoutChannelsShowsTheLeague() {
        let match = Make.match("1", home: barca, away: madrid, at: now.addingTimeInterval(20))
        let result = plan([match])
        #expect(result.notifications.map(\.title) == ["Barcelona vs Real Madrid in 1 min"])
        #expect(result.notifications.map(\.body) == ["LaLiga"])
        #expect(result.notifications.first?.team == madrid)
    }

    static let outsideLead: [TimeInterval] = [-60, 15 * 60 + 1, 3 * 3600]

    @Test(arguments: outsideLead)
    func noKickoffReminderOutsideTheLead(offset: TimeInterval) {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(offset))
        let result = plan([match])
        #expect(result.notifications.isEmpty)
        #expect(result.memory.kickoff.isEmpty)
    }

    @Test func kickoffLeadFollowsTheSetting() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(40 * 60))
        #expect(plan([match]).notifications.isEmpty)
        let result = plan([match], settings: settings { $0.kickoffLead = 45 })
        #expect(result.notifications.map(\.title) == ["Real Madrid vs Barcelona in 40 min"])
    }

    @Test func kickoffReminderFiresOnce() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(600))
        let first = plan([match])
        let second = plan([match], memory: first.memory, at: now.addingTimeInterval(5))
        #expect(first.notifications.count == 1)
        #expect(second.notifications.isEmpty)
    }

    @Test func kickoffToggleOffStillMarksTheMatch() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(600))
        let result = plan([match], settings: settings { $0.notifyKickoff = false })
        #expect(result.notifications.isEmpty)
        // Turning reminders back on later does not fire a stale one.
        #expect(result.memory.kickoff["1"] == now)
    }

    @Test func unfollowedMatchesNeverNotify() {
        let kickoff = Make.match("1", home: sevilla, away: betis, at: now.addingTimeInterval(600))
        let live = Make.match("2", home: sevilla, away: barca, at: now.addingTimeInterval(-1800), state: .in,
                              score: (1, 0))
        let result = plan([kickoff, live], memory: seen(live, score: "0-0"))
        #expect(result.notifications.isEmpty)
        #expect(result.memory.kickoff.isEmpty)
    }

    // MARK: Goals

    @Test func firstSightingOfALiveMatchOnlyRecordsTheScore() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-3000), state: .in,
                               score: (2, 1))
        let result = plan([match])
        #expect(result.notifications.isEmpty)
        #expect(result.memory.scores["1"] == NotificationMemory.Score(value: "2-1", at: now))
    }

    @Test func followedTeamGoalIsAGoalAlertWithTheScorer() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-3000), state: .in,
                               score: (2, 1), events: [Make.goal("Vinícius", "12'", team: madrid),
                                                       Make.goal("Yamal", "30'", team: barca, side: .away),
                                                       Make.goal("Mbappé", "51'", team: madrid)])
        let result = plan([match], memory: seen(match, score: "1-1"))
        #expect(result.notifications == [MatchNotification(
            id: "goal-1", title: "GOAL! Real Madrid", body: "Real Madrid 2–1 Barcelona · Mbappé 51'",
            url: match.espnURL, team: madrid)])
        #expect(result.memory.scores["1"]?.value == "2-1")
    }

    @Test func opponentGoalIsAPlainGoalAlert() {
        let match = Make.match("1", home: barca, away: madrid, at: now.addingTimeInterval(-3000), state: .in,
                               score: (1, 0), events: [Make.goal("Lewandowski", "8'", team: barca)])
        let result = plan([match], memory: seen(match, score: "0-0"))
        #expect(result.notifications.map(\.title) == ["Goal · Barcelona"])
        #expect(result.notifications.map(\.body) == ["Barcelona 1–0 Real Madrid · Lewandowski 8'"])
        #expect(result.notifications.first?.team == barca)
    }

    @Test func ownGoalIsMarkedWhicheverTeamItIsCreditedTo() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-3000), state: .in,
                               score: (1, 0), events: [Make.goal("Koundé", "70'", team: barca, side: .away,
                                                                 kind: .ownGoal)])
        let result = plan([match], memory: seen(match, score: "0-0"))
        #expect(result.notifications.map(\.title) == ["GOAL! Real Madrid"])
        #expect(result.notifications.map(\.body) == ["Real Madrid 1–0 Barcelona · Koundé (OG) 70'"])
    }

    @Test func goalWithoutAKeyEventHasJustTheScore() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-3000), state: .in,
                               score: (0, 1))
        let result = plan([match], memory: seen(match, score: "0-0"))
        #expect(result.notifications.map(\.body) == ["Real Madrid 0–1 Barcelona"])
    }

    @Test func disallowedGoalIsSilentButRecorded() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-3000), state: .in,
                               score: (0, 0))
        let result = plan([match], memory: seen(match, score: "1-0"))
        #expect(result.notifications.isEmpty)
        #expect(result.memory.scores["1"]?.value == "0-0")
    }

    @Test func unchangedScoreKeepsItsFirstSeenTime() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-3000), state: .in,
                               score: (1, 0))
        let earlier = now.addingTimeInterval(-600)
        let result = plan([match], memory: seen(match, score: "1-0", at: earlier))
        #expect(result.notifications.isEmpty)
        #expect(result.memory.scores["1"]?.at == earlier)
    }

    @Test func goalsToggleOffSilencesGoals() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-3000), state: .in,
                               score: (1, 0))
        let result = plan([match], settings: settings { $0.notifyGoals = false }, memory: seen(match, score: "0-0"))
        #expect(result.notifications.isEmpty)
        #expect(result.memory.scores["1"]?.value == "1-0")
    }

    // MARK: Full time

    static let verdicts: [((Int, Int), String)] = [((3, 1), "Win"), ((0, 2), "Loss"), ((1, 1), "Draw")]

    @Test(arguments: verdicts)
    func fullTimeNamesTheResultForTheFollowedTeam(score: (Int, Int), verdict: String) {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-2 * 3600),
                               state: .post, score: score)
        let result = plan([match], memory: seen(match, score: "\(score.0)-\(score.1)"))
        #expect(result.notifications == [MatchNotification(
            id: "final-1", title: "Full time · \(verdict) for Real Madrid",
            body: "Real Madrid \(score.0)–\(score.1) Barcelona", url: match.espnURL, team: madrid)])
        #expect(result.memory.final["1"] == now)
    }

    @Test func fullTimeVerdictIsFromTheAwayFollowedTeam() {
        let match = Make.match("1", home: barca, away: madrid, at: now.addingTimeInterval(-2 * 3600),
                               state: .post, score: (0, 2))
        let result = plan([match], memory: seen(match, score: "0-2"))
        #expect(result.notifications.map(\.title) == ["Full time · Win for Real Madrid"])
    }

    @Test func oldResultsAreMarkedWithoutAnAlert() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-4 * 3600 - 1),
                               state: .post, score: (1, 0))
        let result = plan([match], memory: seen(match, score: "1-0"))
        #expect(result.notifications.isEmpty)
        #expect(result.memory.final["1"] == now)
    }

    @Test func fullTimeFiresOnceAndRespectsItsToggle() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-7000),
                               state: .post, score: (1, 0))
        let first = plan([match], memory: seen(match, score: "1-0"))
        #expect(first.notifications.count == 1)
        #expect(plan([match], memory: first.memory).notifications.isEmpty)
        let silent = plan([match], settings: settings { $0.notifyFinal = false }, memory: seen(match, score: "1-0"))
        #expect(silent.notifications.isEmpty)
        #expect(silent.memory.final["1"] == now)
    }

    @Test func unsettledResultIsNotFullTime() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-7000),
                               state: .post, score: (1, 0), completed: false)
        let result = plan([match], memory: seen(match, score: "1-0"))
        #expect(result.notifications.isEmpty)
        #expect(result.memory.final.isEmpty)
    }

    @Test func lateGoalAndFinalWhistleInOneRefresh() {
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-6000),
                               state: .post, score: (2, 1), events: [Make.goal("Bellingham", "90'+4'", team: madrid)])
        let result = plan([match], memory: seen(match, score: "1-1"))
        #expect(result.notifications.map(\.id) == ["goal-1", "final-1"])
    }

    // MARK: Memory

    @Test func memoryForgetsEntriesAfterSevenDays() {
        let old = now.addingTimeInterval(-7 * 86_400 - 1)
        let recent = now.addingTimeInterval(-6 * 86_400)
        var memory = NotificationMemory()
        memory.kickoff = ["old": old, "new": recent]
        memory.final = ["old": old, "new": recent]
        memory.scores = ["old": .init(value: "1-0", at: old), "new": .init(value: "2-0", at: recent)]
        let pruned = memory.pruned(now: now)
        #expect(Array(pruned.kickoff.keys) == ["new"])
        #expect(Array(pruned.final.keys) == ["new"])
        #expect(Array(pruned.scores.keys) == ["new"])
    }

    @Test func testNotificationMatchesTheOriginal() {
        let test = MatchNotification.test
        #expect(test.id == "test")
        #expect(test.title == "GOAL! Matchday")
        #expect(test.body == "Notifications are working · 90'+3'")
        #expect(test.url == nil)
    }
}
