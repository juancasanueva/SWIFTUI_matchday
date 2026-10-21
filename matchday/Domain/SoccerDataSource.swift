//
//  SoccerDataSource.swift
//  matchday
//

import Foundation

/// Port for fetching soccer data. The ESPN adapter lives in `Data/ESPN`.
nonisolated protocol SoccerDataSource: Sendable {
    /// Matches of a league on one local calendar day.
    func scoreboard(league: String, date: Date) async throws -> [Match]
    func standings(league: String) async throws -> [StandingGroup]
    func teams(league: String) async throws -> [Team]
    /// A team's season schedule; `fixture: true` returns upcoming fixtures.
    func schedule(league: String, teamID: String, fixture: Bool) async throws -> [Match]
}
