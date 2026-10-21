//
//  League.swift
//  matchday
//

import Foundation

/// A competition Matchday follows. The catalog mirrors the original plugin's `LEAGUES`.
nonisolated struct League: Identifiable, Hashable, Sendable {
    /// ESPN league slug, e.g. `esp.1`.
    let id: String
    let name: String
    let short: String
    let country: String
    /// Accent color as `#rrggbb`.
    let colorHex: String
    /// ESPN id used for the league crest.
    let logoID: String
    /// National-team competition (Nations League).
    let isNational: Bool

    init(
        id: String, name: String, short: String, country: String,
        colorHex: String, logoID: String, isNational: Bool = false
    ) {
        self.id = id
        self.name = name
        self.short = short
        self.country = country
        self.colorHex = colorHex
        self.logoID = logoID
        self.isNational = isNational
    }
}

nonisolated extension League {
    static let laLiga = League(id: "esp.1", name: "LaLiga", short: "LaLiga", country: "Spain",
                               colorHex: "#ff4b44", logoID: "15")
    static let serieA = League(id: "ita.1", name: "Serie A", short: "Serie A", country: "Italy",
                               colorHex: "#1aa0e8", logoID: "12")
    static let premierLeague = League(id: "eng.1", name: "Premier League", short: "Premier",
                                      country: "England", colorHex: "#a26bfa", logoID: "23")
    static let mls = League(id: "usa.1", name: "MLS", short: "MLS", country: "USA & Canada",
                            colorHex: "#36c46f", logoID: "19")
    static let championsLeague = League(id: "uefa.champions", name: "UEFA Champions League", short: "UCL",
                                        country: "Europe", colorHex: "#5865f2", logoID: "2")
    static let nationsLeague = League(id: "uefa.nations", name: "UEFA Nations League", short: "Nations",
                                      country: "Europe", colorHex: "#f2b705", logoID: "2395", isNational: true)

    /// Every supported league, in display order.
    static let all: [League] = [laLiga, serieA, premierLeague, mls, championsLeague, nationsLeague]

    static func with(id: String) -> League? {
        all.first { $0.id == id }
    }

    /// Crest image for this league.
    func crestURL(dark: Bool = false) -> URL {
        Crest.url(kind: .league, id: logoID, dark: dark)
    }
}
