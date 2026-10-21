//
//  RefreshPolicy.swift
//  matchday
//
//  Tiered polling from the original plugin's `Engine.jobs` / `Engine.hot`.
//

import Foundation

nonisolated enum RefreshPolicy {
    /// Scoreboard days polled around today.
    static let daysBack = 3
    static let daysAhead = 9
    static var dayOffsets: ClosedRange<Int> { -daysBack...daysAhead }

    /// Back-off after a failed request before it is retried.
    static let failureBackoff: TimeInterval = 60
    static let teamsTTL: TimeInterval = 24 * 3600
    /// Followed teams' schedules and fixtures.
    static let scheduleTTL: TimeInterval = 3 * 3600

    /// How long a day scoreboard stays fresh. `hot` only matters for yesterday..tomorrow.
    static func scoreboardTTL(dayOffset: Int, hot: Bool) -> TimeInterval {
        if dayOffset < -1 { return 6 * 3600 }
        if dayOffset <= 1 { return hot ? 30 : 300 }
        return 1800
    }

    static func standingsTTL(leagueIsLive: Bool) -> TimeInterval {
        leagueIsLive ? 600 : 3600
    }

    /// A scoreboard is hot when something is happening or about to: a live match,
    /// a kickoff within 20 minutes (or up to an hour late), or an unsettled result.
    static func isHot(_ matches: [Match], now: Date) -> Bool {
        matches.contains { match in
            switch match.state {
            case .in:
                return true
            case .pre:
                let untilKickoff = match.kickoff.timeIntervalSince(now)
                return untilKickoff > -3600 && untilKickoff < 20 * 60
            case .post:
                return !match.completed
            }
        }
    }
}

/// Freshness of the data shown to the user (`status` in the original snapshot).
nonisolated enum DataStatus: String, Sendable, Hashable {
    case ok, loading, offline, stale

    /// Errors older than this without any success make the data stale.
    static let staleAfter: TimeInterval = 300

    static func derive(hasMatches: Bool, hasErrors: Bool, lastSuccess: Date?, now: Date) -> DataStatus {
        if !hasMatches { return hasErrors ? .offline : .loading }
        guard hasErrors else { return .ok }
        let sinceSuccess = lastSuccess.map { now.timeIntervalSince($0) } ?? .infinity
        return sinceSuccess > staleAfter ? .stale : .ok
    }
}
