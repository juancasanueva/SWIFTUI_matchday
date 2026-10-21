//
//  Team.swift
//  matchday
//

import Foundation

/// A club or national team within a league.
nonisolated struct Team: Identifiable, Hashable, Sendable {
    /// ESPN team id (unique within ESPN, but always paired with a league here).
    let id: String
    let leagueID: String
    let name: String
    let shortName: String
    let abbreviation: String
    /// Team color as `#rrggbb`, or empty when ESPN has none.
    let colorHex: String

    init(id: String, leagueID: String, name: String, shortName: String,
         abbreviation: String, colorHex: String = "") {
        self.id = id
        self.leagueID = leagueID
        self.name = name
        self.shortName = shortName
        self.abbreviation = abbreviation
        self.colorHex = colorHex
    }

    /// Crest image for this team.
    func crestURL(dark: Bool = false) -> URL {
        Crest.url(kind: .team, id: id, dark: dark)
    }
}

/// ESPN crest CDN URLs (`LOGO_URL` in the original plugin).
nonisolated enum Crest {
    nonisolated enum Kind: Sendable {
        case team, league

        var folder: String {
            switch self {
            case .team: "teamlogos"
            case .league: "leaguelogos"
            }
        }
    }

    static func url(kind: Kind, id: String, dark: Bool) -> URL {
        let variant = dark ? "500-dark" : "500"
        let raw = "https://a.espncdn.com/combiner/i?img=/i/\(kind.folder)/soccer/\(variant)/\(id).png&w=128&h=128"
        // The string is built from fixed parts plus an ESPN id; fall back to the CDN root just in case.
        return URL(string: raw) ?? URL(string: "https://a.espncdn.com")!
    }
}
