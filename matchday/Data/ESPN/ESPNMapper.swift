//
//  ESPNMapper.swift
//  matchday
//
//  Ports `team_of`, `norm_event`, `norm_table` and `norm_teams` from the
//  original plugin, including their fallbacks.
//

import Foundation

nonisolated enum ESPNMapper {

    // MARK: Events

    /// Normalizes a scoreboard or team-schedule payload.
    static func matches(from data: Data, leagueID: String) throws -> [Match] {
        let response = try JSONDecoder().decode(ESPNEventsResponse.self, from: data)
        return (response.events ?? []).map { match(from: $0, leagueID: leagueID) }
    }

    static func match(from event: ESPNEvent, leagueID: String) -> Match {
        let competition = event.competitions?.first
        let status = competition?.status ?? event.status
        let type = status?.type
        let competitors = competition?.competitors ?? []
        let homeDTO = competitors.first { $0.homeAway == "home" } ?? competitors.first
        let awayDTO = competitors.first { $0.homeAway == "away" }
            ?? (competitors.count > 1 ? competitors[1] : nil)
        let home = side(from: homeDTO, leagueID: leagueID)
        let away = side(from: awayDTO, leagueID: leagueID)

        let id = event.id?.value ?? ""
        let date = nonEmpty(event.date) ?? nonEmpty(competition?.date)
        let venue = competition?.venue

        return Match(
            id: id,
            leagueID: leagueID,
            kickoff: ESPNDate.parse(date) ?? Date(timeIntervalSince1970: 0),
            state: MatchState(rawValue: type?.state ?? "") ?? .pre,
            statusName: type?.name ?? "",
            shortDetail: nonEmpty(type?.shortDetail) ?? type?.detail ?? "",
            displayClock: status?.displayClock ?? "",
            completed: type?.completed ?? false,
            home: home,
            away: away,
            keyEvents: keyEvents(from: competition?.details ?? [], homeID: home.team.id, awayID: away.team.id),
            tvNames: tvNames(from: competition),
            espnURL: matchURL(from: event.links ?? [], id: id),
            venue: venue?.fullName ?? "",
            city: venue?.address?.city ?? "",
            week: event.week?.number?.value.flatMap { Int($0) }
        )
    }

    static func side(from competitor: ESPNCompetitor?, leagueID: String) -> MatchSide {
        let dto = competitor?.team
        let records = competitor?.records ?? competitor?.record ?? []
        let record = records.first.map { nonEmpty($0.summary) ?? $0.displayValue ?? "" } ?? ""
        let team = Team(
            id: nonEmpty(dto?.id?.value) ?? competitor?.id?.value ?? "",
            leagueID: leagueID,
            name: nonEmpty(dto?.displayName) ?? dto?.name ?? "",
            shortName: nonEmpty(dto?.shortDisplayName) ?? dto?.displayName ?? "",
            abbreviation: dto?.abbreviation ?? "",
            colorHex: hexColor(dto?.color)
        )
        return MatchSide(
            team: team,
            score: nonEmpty(competitor?.score?.value),
            winner: competitor?.winner ?? false,
            form: competitor?.form ?? "",
            record: record
        )
    }

    /// Goals and red cards only; yellow cards and other plays are dropped.
    static func keyEvents(from details: [ESPNDetail], homeID: String, awayID: String) -> [KeyEvent] {
        details.compactMap { detail in
            let scoring = detail.scoringPlay ?? false
            let red = detail.redCard ?? false
            guard scoring || red else { return nil }

            let kind: KeyEvent.Kind
            if scoring {
                if detail.ownGoal ?? false {
                    kind = .ownGoal
                } else if detail.penaltyKick ?? false {
                    kind = .penalty
                } else {
                    kind = .goal
                }
            } else {
                kind = .redCard
            }

            let teamID = detail.team?.id?.value ?? ""
            let side: KeyEvent.Side = teamID.isEmpty ? .unknown
                : teamID == homeID ? .home
                : teamID == awayID ? .away
                : .unknown
            let athlete = detail.athletesInvolved?.first
            return KeyEvent(
                kind: kind,
                minute: detail.clock?.displayValue ?? "",
                player: nonEmpty(athlete?.shortName) ?? athlete?.displayName ?? "",
                teamID: teamID,
                side: side
            )
        }
    }

    /// TV names from `geoBroadcasts`, else from `broadcasts` (media entries count only for the US).
    static func tvNames(from competition: ESPNCompetition?) -> [String] {
        var names: [String] = []
        func add(_ name: String?) {
            if let name, !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        for geo in competition?.geoBroadcasts ?? [] {
            add(geo.media?.shortName)
        }
        if names.isEmpty {
            for broadcast in competition?.broadcasts ?? [] {
                if let listed = broadcast.names, !listed.isEmpty {
                    listed.forEach { add($0) }
                } else if (broadcast.region ?? "us") == "us" {
                    add(broadcast.media?.shortName)
                }
            }
        }
        return names
    }

    /// The first `/match/` link, else the canonical ESPN match page.
    static func matchURL(from links: [ESPNLink], id: String) -> URL {
        for link in links {
            if let href = link.href, href.contains("/match/"), let url = URL(string: href) {
                return url
            }
        }
        return URL(string: "https://www.espn.com/soccer/match/_/gameId/\(id)")
            ?? URL(string: "https://www.espn.com/soccer/")!
    }

    // MARK: Standings

    static func standings(from data: Data, leagueID: String) throws -> [StandingGroup] {
        let response = try JSONDecoder().decode(ESPNStandingsResponse.self, from: data)
        let children = response.children
            ?? [ESPNStandingsChild(name: response.name, standings: response.standings)]
        let grouped = children.count > 1

        return children.map { child in
            let entries = (child.standings?.entries ?? []).map { entry(from: $0, leagueID: leagueID) }
            // Unranked rows (rank 0) sort as 99, like the original.
            let sorted = entries.enumerated().sorted { lhs, rhs in
                let l = lhs.element.rank == 0 ? 99 : lhs.element.rank
                let r = rhs.element.rank == 0 ? 99 : rhs.element.rank
                return l == r ? lhs.offset < rhs.offset : l < r
            }.map(\.element)
            return StandingGroup(name: grouped ? (child.name ?? "") : "", entries: sorted)
        }
    }

    static func entry(from dto: ESPNStandingEntry, leagueID: String) -> StandingEntry {
        // displayValue wins over value, as in the original.
        var stats: [String: String] = [:]
        for stat in dto.stats ?? [] {
            guard let name = stat.name else { continue }
            stats[name] = stat.displayValue?.value ?? stat.value?.value ?? ""
        }
        func number(_ key: String) -> Int {
            guard let raw = stats[key], let value = Double(raw) else { return 0 }
            return Int(value)
        }
        let team = dto.team
        return StandingEntry(
            rank: number("rank"),
            team: Team(
                id: team?.id?.value ?? "",
                leagueID: leagueID,
                name: team?.displayName ?? "",
                shortName: nonEmpty(team?.shortDisplayName) ?? team?.displayName ?? "",
                abbreviation: team?.abbreviation ?? "",
                colorHex: hexColor(team?.color)
            ),
            played: number("gamesPlayed"),
            wins: number("wins"),
            draws: number("ties"),
            losses: number("losses"),
            goalDifference: number("pointDifferential"),
            points: number("points"),
            zone: dto.note.map { StandingZone(colorHex: $0.color ?? "", description: $0.description ?? "") }
        )
    }

    // MARK: Teams

    static func teams(from data: Data, leagueID: String) throws -> [Team] {
        let response = try JSONDecoder().decode(ESPNTeamsResponse.self, from: data)
        let items = response.sports?.first?.leagues?.first?.teams ?? []
        let teams = items.compactMap(\.team).map { dto in
            Team(
                id: dto.id?.value ?? "",
                leagueID: leagueID,
                name: dto.displayName ?? "",
                shortName: nonEmpty(dto.shortDisplayName) ?? dto.displayName ?? "",
                abbreviation: dto.abbreviation ?? "",
                colorHex: hexColor(dto.color)
            )
        }
        return teams.sorted { $0.shortName.lowercased() < $1.shortName.lowercased() }
    }

    // MARK: Helpers

    /// Python-style `a or b`: treats empty strings as missing.
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// ESPN colors come without `#`.
    static func hexColor(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return raw.hasPrefix("#") ? raw : "#" + raw
    }
}

/// ESPN timestamps (`parse_ts`): ISO 8601, often without seconds (`2026-10-18T13:00Z`).
nonisolated enum ESPNDate {
    static func parse(_ raw: String?) -> Date? {
        guard var text = raw, !text.isEmpty else { return nil }
        // Insert missing seconds: "yyyy-MM-ddTHH:mm" is 16 characters.
        if text.count > 16 {
            let index = text.index(text.startIndex, offsetBy: 16)
            if text[index] != ":" { text.insert(contentsOf: ":00", at: index) }
        } else if text.count == 16 {
            text += ":00Z"
        }
        if let date = try? Date(text, strategy: .iso8601) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
