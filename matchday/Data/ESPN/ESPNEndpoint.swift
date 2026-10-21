//
//  ESPNEndpoint.swift
//  matchday
//

import Foundation

/// Every ESPN request Matchday makes, with its URL and cache key
/// (the same keys as the original plugin's `Store`).
nonisolated enum ESPNEndpoint: Hashable, Sendable {
    /// Scoreboard of one day; `day` is `yyyyMMdd` in the local calendar.
    case scoreboard(league: String, day: String)
    case standings(league: String)
    case teams(league: String)
    /// A team's schedule; `fixture: true` lists upcoming fixtures.
    case schedule(league: String, teamID: String, fixture: Bool)

    static let siteAPI = "https://site.api.espn.com/apis/site/v2/sports/soccer"
    static let standingsAPI = "https://site.api.espn.com/apis/v2/sports/soccer"

    var url: URL {
        let raw: String
        switch self {
        case let .scoreboard(league, day):
            raw = "\(Self.siteAPI)/\(league)/scoreboard?dates=\(day)"
        case let .standings(league):
            raw = "\(Self.standingsAPI)/\(league)/standings"
        case let .teams(league):
            raw = "\(Self.siteAPI)/\(league)/teams"
        case let .schedule(league, teamID, fixture):
            raw = "\(Self.siteAPI)/\(league)/teams/\(teamID)/schedule" + (fixture ? "?fixture=true" : "")
        }
        // Built from fixed parts and ESPN identifiers, so this is always a valid URL.
        return URL(string: raw)!
    }

    var cacheKey: String {
        switch self {
        case let .scoreboard(league, day): "sb:\(league):\(day)"
        case let .standings(league): "table:\(league)"
        case let .teams(league): "teams:\(league)"
        case let .schedule(league, teamID, fixture): "\(fixture ? "fix" : "sched"):\(league):\(teamID)"
        }
    }

    var leagueID: String {
        switch self {
        case let .scoreboard(league, _), let .standings(league), let .teams(league),
             let .schedule(league, _, _):
            league
        }
    }

    /// `yyyyMMdd` for `date` in `calendar`'s time zone.
    static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
