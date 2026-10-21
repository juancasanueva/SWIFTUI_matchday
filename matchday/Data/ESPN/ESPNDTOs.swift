//
//  ESPNDTOs.swift
//  matchday
//
//  Decodable mirrors of the ESPN site API payloads. Every field is optional:
//  ESPN omits keys freely and the mappers apply the original plugin's fallbacks.
//

import Foundation

// MARK: - Tolerant scalars

/// A value ESPN sends as a string, a number, or an object with `displayValue`
/// (schedule scores). Decodes to its display string; `null` decodes to `nil`.
nonisolated struct ESPNText: Decodable, Sendable, Hashable {
    let value: String?

    nonisolated private struct Wrapped: Decodable {
        let displayValue: String?
        let value: Double?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = ESPNText.format(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = String(bool)
        } else if let wrapped = try? container.decode(Wrapped.self) {
            value = wrapped.displayValue ?? wrapped.value.map(ESPNText.format)
        } else {
            value = nil
        }
    }

    /// Whole numbers print without a decimal point (`7.0` -> `7`).
    static func format(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 {
            return String(Int(number))
        }
        return String(number)
    }
}

// MARK: - Events (scoreboard and team schedule)

nonisolated struct ESPNEventsResponse: Decodable, Sendable {
    let events: [ESPNEvent]?
}

nonisolated struct ESPNEvent: Decodable, Sendable {
    let id: ESPNText?
    let date: String?
    let status: ESPNStatus?
    let competitions: [ESPNCompetition]?
    let links: [ESPNLink]?
    let week: ESPNWeek?
}

nonisolated struct ESPNWeek: Decodable, Sendable {
    let number: ESPNText?
}

nonisolated struct ESPNLink: Decodable, Sendable {
    let href: String?
}

nonisolated struct ESPNStatus: Decodable, Sendable {
    let displayClock: String?
    let type: ESPNStatusType?
}

nonisolated struct ESPNStatusType: Decodable, Sendable {
    let name: String?
    let state: String?
    let completed: Bool?
    let detail: String?
    let shortDetail: String?
}

nonisolated struct ESPNCompetition: Decodable, Sendable {
    let date: String?
    let status: ESPNStatus?
    let competitors: [ESPNCompetitor]?
    let details: [ESPNDetail]?
    let geoBroadcasts: [ESPNGeoBroadcast]?
    let broadcasts: [ESPNBroadcast]?
    let venue: ESPNVenue?
}

nonisolated struct ESPNCompetitor: Decodable, Sendable {
    let id: ESPNText?
    let homeAway: String?
    let winner: Bool?
    let form: String?
    let score: ESPNText?
    /// Scoreboards send `records`, schedules send `record`.
    let records: [ESPNRecord]?
    let record: [ESPNRecord]?
    let team: ESPNTeam?
}

nonisolated struct ESPNRecord: Decodable, Sendable {
    let summary: String?
    let displayValue: String?
}

nonisolated struct ESPNTeam: Decodable, Sendable {
    let id: ESPNText?
    let displayName: String?
    let name: String?
    let shortDisplayName: String?
    let abbreviation: String?
    let color: String?
}

nonisolated struct ESPNDetail: Decodable, Sendable {
    let clock: ESPNClock?
    let team: ESPNTeamRef?
    let scoringPlay: Bool?
    let redCard: Bool?
    let ownGoal: Bool?
    let penaltyKick: Bool?
    let athletesInvolved: [ESPNAthlete]?
}

nonisolated struct ESPNClock: Decodable, Sendable {
    let displayValue: String?
}

nonisolated struct ESPNTeamRef: Decodable, Sendable {
    let id: ESPNText?
}

nonisolated struct ESPNAthlete: Decodable, Sendable {
    let displayName: String?
    let shortName: String?
}

nonisolated struct ESPNMedia: Decodable, Sendable {
    let shortName: String?
}

nonisolated struct ESPNGeoBroadcast: Decodable, Sendable {
    let media: ESPNMedia?
}

nonisolated struct ESPNBroadcast: Decodable, Sendable {
    let names: [String]?
    let media: ESPNMedia?
    let region: String?
}

nonisolated struct ESPNVenue: Decodable, Sendable {
    let fullName: String?
    let address: ESPNAddress?
}

nonisolated struct ESPNAddress: Decodable, Sendable {
    let city: String?
}

// MARK: - Standings

/// The standings root. Grouped competitions list `children`; a bare table may
/// carry `standings` itself, in which case the root acts as its only child.
nonisolated struct ESPNStandingsResponse: Decodable, Sendable {
    let name: String?
    let children: [ESPNStandingsChild]?
    let standings: ESPNStandings?
}

nonisolated struct ESPNStandingsChild: Decodable, Sendable {
    let name: String?
    let standings: ESPNStandings?
}

nonisolated struct ESPNStandings: Decodable, Sendable {
    let entries: [ESPNStandingEntry]?
}

nonisolated struct ESPNStandingEntry: Decodable, Sendable {
    let team: ESPNTeam?
    let note: ESPNNote?
    let stats: [ESPNStat]?
}

nonisolated struct ESPNNote: Decodable, Sendable {
    let color: String?
    let description: String?
}

nonisolated struct ESPNStat: Decodable, Sendable {
    let name: String?
    let value: ESPNText?
    let displayValue: ESPNText?
}

// MARK: - Teams

nonisolated struct ESPNTeamsResponse: Decodable, Sendable {
    let sports: [Sport]?

    nonisolated struct Sport: Decodable, Sendable {
        let leagues: [LeagueEntry]?
    }

    nonisolated struct LeagueEntry: Decodable, Sendable {
        let teams: [TeamItem]?
    }

    nonisolated struct TeamItem: Decodable, Sendable {
        let team: ESPNTeam?
    }
}
