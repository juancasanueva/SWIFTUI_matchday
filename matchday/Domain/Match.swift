//
//  Match.swift
//  matchday
//

import Foundation

/// ESPN's coarse match state.
nonisolated enum MatchState: String, Sendable, Hashable {
    case pre, `in`, post
}

/// One side of a match.
nonisolated struct MatchSide: Hashable, Sendable {
    let team: Team
    /// Score as ESPN displays it; `nil` before kickoff.
    let score: String?
    let winner: Bool
    /// Recent form string such as `WDLLW`.
    let form: String
    /// Season record such as `1-3-3`.
    let record: String

    /// Numeric score, when ESPN sent one.
    var goals: Int? { score.flatMap { Int($0) } }
}

/// A notable in-match event: goals and red cards.
nonisolated struct KeyEvent: Hashable, Sendable {
    nonisolated enum Kind: Sendable, Hashable {
        case goal, ownGoal, penalty, redCard
    }

    nonisolated enum Side: Sendable, Hashable {
        case home, away, unknown
    }

    let kind: Kind
    /// Minute as displayed, e.g. `45'+2'`.
    let minute: String
    let player: String
    /// ESPN id of the team the event is credited to.
    let teamID: String
    let side: Side

    var isGoal: Bool { kind != .redCard }
}

/// A normalized fixture or result (`norm_event` in the original plugin).
nonisolated struct Match: Identifiable, Hashable, Sendable {
    let id: String
    let leagueID: String
    /// Kickoff time; the Unix epoch when ESPN sent no usable date.
    let kickoff: Date
    let state: MatchState
    /// ESPN status type name, e.g. `STATUS_HALFTIME`.
    let statusName: String
    /// Short status text, e.g. `FT` or `45'`.
    let shortDetail: String
    let displayClock: String
    let completed: Bool
    let home: MatchSide
    let away: MatchSide
    let keyEvents: [KeyEvent]
    /// US TV/streaming names listed by ESPN.
    var tvNames: [String]
    let espnURL: URL
    let venue: String
    let city: String
    /// Matchweek / round number, when ESPN provides one.
    let week: Int?

    var isLive: Bool { state == .in }
    var isHalftime: Bool { statusName == "STATUS_HALFTIME" }
    var isPostponed: Bool { statusName == "STATUS_POSTPONED" }
    /// Finished and final (not merely "post" while ESPN settles the result).
    var isFinal: Bool { state == .post && completed }

    func involves(teamID: String) -> Bool {
        home.team.id == teamID || away.team.id == teamID
    }
}
