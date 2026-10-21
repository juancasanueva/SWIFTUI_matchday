//
//  MatchFactory.swift
//  matchdayTests
//

import Foundation
@testable import matchday

/// Builders for domain values used by the derivation and store tests.
enum Make {
    static func team(_ id: String, league: String = "esp.1", abbreviation: String? = nil,
                     short: String? = nil, color: String = "") -> Team {
        Team(id: id, leagueID: league, name: (short ?? id) + " FC", shortName: short ?? id,
             abbreviation: abbreviation ?? id.uppercased(), colorHex: color)
    }

    static func favorite(_ team: Team) -> FavoriteTeam {
        FavoriteTeam(team: team)
    }

    static func goal(_ player: String, _ minute: String, team: Team, side: KeyEvent.Side = .home,
                     kind: KeyEvent.Kind = .goal) -> KeyEvent {
        KeyEvent(kind: kind, minute: minute, player: player, teamID: team.id, side: side)
    }

    static func match(
        _ id: String,
        home: Team,
        away: Team,
        at kickoff: Date,
        state: MatchState = .pre,
        score: (Int, Int)? = nil,
        status: String = "STATUS_SCHEDULED",
        detail: String = "",
        clock: String = "",
        completed: Bool? = nil,
        events: [KeyEvent] = [],
        tv: [String] = [],
        venue: String = "",
        city: String = ""
    ) -> Match {
        func side(_ team: Team, _ goals: Int?) -> MatchSide {
            MatchSide(team: team, score: goals.map(String.init), winner: false, form: "", record: "")
        }
        return Match(id: id, leagueID: home.leagueID, kickoff: kickoff, state: state, statusName: status,
                     shortDetail: detail, displayClock: clock, completed: completed ?? (state == .post),
                     home: side(home, score?.0), away: side(away, score?.1), keyEvents: events, tvNames: tv,
                     espnURL: URL(string: "https://www.espn.com/soccer/match/_/gameId/\(id)")!,
                     venue: venue, city: city, week: nil)
    }

    static func snapshot(_ matches: [Match], tables: [String: [StandingGroup]] = [:],
                         teams: [String: [Team]] = [:], status: DataStatus = .ok,
                         error: String? = nil) -> MatchSnapshot {
        MatchSnapshot(matches: matches.sorted { $0.kickoff < $1.kickoff }, tables: tables, teams: teams,
                      liveLeagueIDs: Set(matches.filter(\.isLive).map(\.leagueID)), status: status,
                      lastError: error, lastSuccess: nil)
    }

    static func settings(following teams: [Team], leagues: [String]? = nil, barScore: Bool = true) -> AppSettings {
        var settings = AppSettings()
        teams.forEach { settings.toggleFollow(FavoriteTeam(team: $0)) }
        if let leagues { settings.setLeagues(leagues) }
        settings.barScore = barScore
        return settings
    }

    static func broadcaster(_ name: String, language: String? = nil) -> Broadcaster {
        Broadcaster(id: name.lowercased(), name: name, url: nil, colorHex: "", kind: .tv, language: language)
    }

    static func display(_ now: Date) -> DisplayContext {
        DisplayContext(now: now, calendar: utcCalendar(), locale: Locale(identifier: "en_US"))
    }
}
