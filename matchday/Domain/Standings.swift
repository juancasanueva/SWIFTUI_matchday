//
//  Standings.swift
//  matchday
//

import Foundation

/// Qualification / relegation zone note attached to a table row.
nonisolated struct StandingZone: Hashable, Sendable {
    /// `#rrggbb` (may be empty).
    let colorHex: String
    let description: String
}

/// One row of a league table.
nonisolated struct StandingEntry: Hashable, Sendable {
    let rank: Int
    let team: Team
    let played: Int
    let wins: Int
    let draws: Int
    let losses: Int
    let goalDifference: Int
    let points: Int
    let zone: StandingZone?

    /// Goal difference with an explicit sign, as ESPN shows it (`+12`, `0`, `-3`).
    var goalDifferenceText: String {
        goalDifference > 0 ? "+\(goalDifference)" : "\(goalDifference)"
    }
}

/// A table, or one group of a grouped competition. `name` is empty for single tables.
nonisolated struct StandingGroup: Hashable, Sendable {
    let name: String
    let entries: [StandingEntry]
}
