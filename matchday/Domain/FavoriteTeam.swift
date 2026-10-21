//
//  FavoriteTeam.swift
//  matchday
//

import Foundation

/// A team the user follows. Persisted, so it is `Codable`.
nonisolated struct FavoriteTeam: Codable, Hashable, Sendable, Identifiable {
    let leagueID: String
    /// ESPN team id.
    let teamID: String
    let name: String
    let shortName: String
    let abbreviation: String

    /// Unique key: the same ESPN team can be followed in several leagues.
    var key: String { "\(leagueID):\(teamID)" }
    var id: String { key }

    init(leagueID: String, teamID: String, name: String, shortName: String, abbreviation: String) {
        self.leagueID = leagueID
        self.teamID = teamID
        self.name = name
        self.shortName = shortName
        self.abbreviation = abbreviation
    }

    init(team: Team) {
        self.init(leagueID: team.leagueID, teamID: team.id, name: team.name,
                  shortName: team.shortName, abbreviation: team.abbreviation)
    }
}
