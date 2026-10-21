//
//  NotificationPlanner.swift
//  matchday
//
//  Decides which alerts a refresh produces for followed teams: the kickoff
//  reminder, goals and full time (`check_notifications` in the original).
//  Pure: the caller supplies the persisted memory and gets the next one back.
//

import Foundation

/// One alert to show. `id` is stable per match and kind, so a newer goal
/// replaces the previous goal alert of the same match.
nonisolated struct MatchNotification: Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    /// ESPN match page opened when the alert is clicked.
    let url: URL?
    /// Team whose crest illustrates the alert.
    let team: Team?

    /// The Settings "Test notification" alert.
    static let test = MatchNotification(id: "test", title: "GOAL! Matchday",
                                        body: "Notifications are working · 90'+3'", url: nil, team: nil)
}

/// What has already been announced (`notified.json`): kickoff reminders and
/// full times by match id, and the last score seen per match.
nonisolated struct NotificationMemory: Codable, Hashable, Sendable {
    nonisolated struct Score: Codable, Hashable, Sendable {
        /// `home-away`, e.g. `2-1`.
        let value: String
        /// When this score was first seen.
        let at: Date
    }

    /// Entries older than this are forgotten.
    static let retention: TimeInterval = 7 * 86_400

    var kickoff: [String: Date] = [:]
    var final: [String: Date] = [:]
    var scores: [String: Score] = [:]

    init() {}

    func pruned(now: Date) -> NotificationMemory {
        let cutoff = now.addingTimeInterval(-Self.retention)
        var memory = self
        memory.kickoff = kickoff.filter { $0.value > cutoff }
        memory.final = final.filter { $0.value > cutoff }
        memory.scores = scores.filter { $0.value.at > cutoff }
        return memory
    }
}

nonisolated struct NotificationPlan: Sendable {
    var notifications: [MatchNotification] = []
    var memory: NotificationMemory
    /// Whether `memory` differs from the input and needs saving.
    var changed = false
}

nonisolated enum NotificationPlanner {
    /// Full time is announced only for matches that kicked off this recently.
    static let fullTimeWindow: TimeInterval = 4 * 3600
    static let watchNameLimit = 3

    static func plan(
        matches: [Match],
        settings: AppSettings,
        memory: NotificationMemory,
        now: Date,
        watch: (Match) -> WatchOptions
    ) -> NotificationPlan {
        var plan = NotificationPlan(memory: memory)
        for match in matches {
            guard let followed = followedSide(of: match, settings: settings) else { continue }
            kickoff(match, followed: followed, settings: settings, now: now, watch: watch, into: &plan)
            goal(match, followed: followed, settings: settings, now: now, into: &plan)
            fullTime(match, followed: followed, settings: settings, now: now, into: &plan)
        }
        return plan
    }

    /// The followed side; home when both teams are followed.
    private static func followedSide(of match: Match, settings: AppSettings) -> MatchSide? {
        if settings.isFollowing(leagueID: match.leagueID, teamID: match.home.team.id) { return match.home }
        if settings.isFollowing(leagueID: match.leagueID, teamID: match.away.team.id) { return match.away }
        return nil
    }

    // MARK: Rules

    private static func kickoff(_ match: Match, followed: MatchSide, settings: AppSettings, now: Date,
                                watch: (Match) -> WatchOptions, into plan: inout NotificationPlan) {
        let remaining = match.kickoff.timeIntervalSince(now)
        let lead = TimeInterval(settings.kickoffLead * 60)
        guard match.state == .pre, remaining >= 0, remaining <= lead,
              plan.memory.kickoff[match.id] == nil else { return }
        plan.memory.kickoff[match.id] = now
        plan.changed = true
        guard settings.notifyKickoff else { return }

        let minutes = max(1, Int((remaining / 60).rounded()))
        let names = watch(match).names(limit: watchNameLimit)
        let body = names.isEmpty ? (League.with(id: match.leagueID)?.name ?? match.leagueID)
            : "Watch on " + names.joined(separator: ", ")
        plan.notifications.append(MatchNotification(
            id: "kick-\(match.id)",
            title: "\(match.home.team.shortName) vs \(match.away.team.shortName) in \(minutes) min",
            body: body, url: match.espnURL, team: followed.team))
    }

    private static func goal(_ match: Match, followed: MatchSide, settings: AppSettings, now: Date,
                             into plan: inout NotificationPlan) {
        guard match.state != .pre, match.home.score != nil else { return }
        let home = match.home.goals ?? 0, away = match.away.goals ?? 0
        let score = "\(match.home.score ?? "0")-\(match.away.score ?? "0")"
        let previous = plan.memory.scores[match.id]
        guard previous?.value != score else { return }
        plan.memory.scores[match.id] = NotificationMemory.Score(value: score, at: now)
        plan.changed = true

        // The first sighting only records the score: no alerts for goals scored before.
        guard let previous, settings.notifyGoals, let before = parse(previous.value),
              home > before.home || away > before.away else { return }
        let scorer = home > before.home ? match.home : match.away
        let ours = scorer.team.id == followed.team.id
        plan.notifications.append(MatchNotification(
            id: "goal-\(match.id)",
            title: (ours ? "GOAL! " : "Goal · ") + scorer.team.shortName,
            body: scoreLine(match) + scorerSuffix(match, scorer: scorer),
            url: match.espnURL, team: scorer.team))
    }

    private static func fullTime(_ match: Match, followed: MatchSide, settings: AppSettings, now: Date,
                                 into plan: inout NotificationPlan) {
        guard match.isFinal, plan.memory.final[match.id] == nil else { return }
        plan.memory.final[match.id] = now
        plan.changed = true
        guard settings.notifyFinal, now.timeIntervalSince(match.kickoff) < fullTimeWindow else { return }

        let opponent = followed.team.id == match.home.team.id ? match.away : match.home
        let mine = followed.goals ?? 0, theirs = opponent.goals ?? 0
        let verdict = mine > theirs ? "Win" : mine < theirs ? "Loss" : "Draw"
        plan.notifications.append(MatchNotification(
            id: "final-\(match.id)", title: "Full time · \(verdict) for \(followed.team.shortName)",
            body: scoreLine(match), url: match.espnURL, team: followed.team))
    }

    // MARK: Text

    /// "Real Madrid 2–1 Barcelona".
    static func scoreLine(_ match: Match) -> String {
        "\(match.home.team.shortName) \(match.home.score ?? "0")–\(match.away.score ?? "0") \(match.away.team.shortName)"
    }

    /// " · Mbappé 51'" for the latest goal by `scorer`. ESPN is not consistent
    /// about which team an own goal is credited to, so any own goal counts.
    private static func scorerSuffix(_ match: Match, scorer: MatchSide) -> String {
        let goal = match.keyEvents.last { event in
            switch event.kind {
            case .goal, .penalty: event.teamID == scorer.team.id
            case .ownGoal: true
            case .redCard: false
            }
        }
        guard let goal else { return "" }
        let player = goal.kind == .ownGoal ? "\(goal.player) (OG)" : goal.player
        return " · \(player) \(goal.minute)"
    }

    private static func parse(_ score: String) -> (home: Int, away: Int)? {
        let parts = score.split(separator: "-").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
}
