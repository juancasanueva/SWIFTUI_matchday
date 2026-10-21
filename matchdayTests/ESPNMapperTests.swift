//
//  ESPNMapperTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("ESPN event normalization")
struct ESPNEventMappingTests {
    let matches: [Match]

    init() throws {
        matches = try ESPNMapper.matches(from: Fixture.data("scoreboard"), leagueID: "eng.1")
    }

    @Test func decodesEveryEvent() {
        #expect(matches.map(\.id) == ["401879263", "401879270", "401879299"])
        #expect(matches.allSatisfy { $0.leagueID == "eng.1" })
    }

    @Test func picksHomeAndAwayByHomeAwayFlag() throws {
        let match = try #require(matches.first)
        #expect(match.home.team.id == "349")
        #expect(match.home.team.name == "AFC Bournemouth")
        #expect(match.home.team.shortName == "Bournemouth")
        #expect(match.home.team.abbreviation == "BOU")
        #expect(match.home.team.colorHex == "#f42727")
        #expect(match.home.team.leagueID == "eng.1")
        #expect(match.home.score == "2")
        #expect(match.home.goals == 2)
        #expect(match.home.winner)
        #expect(match.home.form == "DWLLW")
        #expect(match.home.record == "1-3-3")
        #expect(match.away.team.id == "366")
        #expect(match.away.score == "1")
        #expect(!match.away.winner)
    }

    @Test func fallsBackToCompetitorOrderWithoutHomeAwayFlag() throws {
        let match = try #require(matches.last)
        #expect(match.home.team.id == "382")
        #expect(match.away.team.id == "363")
        // An empty score string means "no score yet".
        #expect(match.home.score == nil)
        #expect(match.away.score == nil)
        #expect(match.home.team.colorHex == "")
    }

    @Test func readsStatusFromCompetitionThenEvent() throws {
        let fullTime = matches[0]
        #expect(fullTime.state == .post)
        #expect(fullTime.completed)
        #expect(fullTime.isFinal)
        #expect(fullTime.statusName == "STATUS_FULL_TIME")
        #expect(fullTime.shortDetail == "FT")
        #expect(fullTime.displayClock == "90'+7'")

        let halftime = matches[1]
        #expect(halftime.state == .in)
        #expect(halftime.isLive)
        #expect(halftime.isHalftime)
        #expect(!halftime.isFinal)

        // No competition status: falls back to the event's status.
        let postponed = matches[2]
        #expect(postponed.state == .pre)
        #expect(postponed.isPostponed)
        #expect(postponed.shortDetail == "Postponed")
    }

    @Test func parsesKickoffWithAndWithoutSeconds() {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let first = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 13))!
        let second = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15, minute: 30))!
        #expect(matches[0].kickoff == first)
        #expect(matches[1].kickoff == second)
    }

    @Test func keepsOnlyGoalsAndRedCardsAsKeyEvents() throws {
        let events = matches[0].keyEvents
        #expect(events.map(\.kind) == [.goal, .redCard, .penalty, .ownGoal])
        #expect(events.map(\.minute) == ["6'", "17'", "55'", "90'+3'"])
        // shortName first, displayName as a fallback.
        #expect(events.map(\.player) == ["M. Tavernier", "K. Danso", "Penalty Taker", "O. Goaler"])
        #expect(events.map(\.teamID) == ["349", "366", "366", "349"])
        #expect(events.map(\.side) == [.home, .away, .away, .home])
        #expect(events.filter(\.isGoal).count == 3)
    }

    @Test func prefersGeoBroadcastsAndDeduplicates() {
        #expect(matches[0].tvNames == ["Peacock", "Telemundo"])
    }

    @Test func fallsBackToUSBroadcasts() {
        // `names` lists win; media-only entries count only for the US region (default).
        #expect(matches[1].tvNames == ["USA Network", "Universo"])
        #expect(matches[2].tvNames.isEmpty)
    }

    @Test func usesMatchLinkOrBuildsOne() {
        #expect(matches[0].espnURL.absoluteString
                == "https://www.espn.com/soccer/match/_/gameId/401879263/sunderland-afc-bournemouth")
        #expect(matches[1].espnURL.absoluteString == "https://www.espn.com/soccer/match/_/gameId/401879270")
    }

    @Test func readsVenueCityAndWeek() {
        #expect(matches[0].venue == "Vitality Stadium")
        #expect(matches[0].city == "Bournemouth")
        #expect(matches[0].week == nil)
        #expect(matches[1].venue == "Emirates Stadium")
        #expect(matches[1].city == "")
        #expect(matches[1].week == 8)
    }
}

@Suite("ESPN schedule normalization")
struct ESPNScheduleMappingTests {
    @Test func decodesObjectScoresAndRecordArrays() throws {
        let matches = try ESPNMapper.matches(from: Fixture.data("schedule"), leagueID: "eng.1")
        #expect(matches.count == 2)
        let result = matches[0]
        #expect(result.home.team.id == "393")
        #expect(result.home.score == "0")
        #expect(result.away.score == "3")
        #expect(result.away.record == "6-1-0")
        #expect(result.tvNames == ["Peacock"])
        #expect(result.espnURL.absoluteString
                == "https://www.espn.com/soccer/match/_/gameId/401878769/arsenal-nottingham-forest")
        let fixture = matches[1]
        #expect(fixture.state == .pre)
        #expect(fixture.home.score == nil)
        #expect(fixture.involves(teamID: "359"))
        #expect(!fixture.involves(teamID: "1"))
    }
}

@Suite("ESPN standings normalization")
struct ESPNStandingsMappingTests {
    @Test func singleTableIsSortedByRankWithEmptyGroupName() throws {
        let groups = try ESPNMapper.standings(from: Fixture.data("standings"), leagueID: "eng.1")
        let table = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(table.name == "")
        #expect(table.entries.map(\.rank) == [1, 2, 18])
        #expect(table.entries.map(\.team.id) == ["382", "359", "393"])

        let city = table.entries[0]
        // Missing displayValue falls back to the numeric value.
        #expect(city.played == 7)
        #expect(city.wins == 7)
        #expect(city.points == 21)
        #expect(city.goalDifference == 12)
        #expect(city.goalDifferenceText == "+12")
        #expect(city.zone == StandingZone(colorHex: "#81D6AC", description: "Champions League"))

        let arsenal = table.entries[1]
        #expect(arsenal.draws == 1)
        #expect(arsenal.losses == 0)
        #expect(arsenal.zone == nil)
        #expect(arsenal.team.shortName == "Arsenal")

        #expect(table.entries[2].goalDifferenceText == "-6")
    }

    @Test func groupedCompetitionKeepsGroupNames() throws {
        let groups = try ESPNMapper.standings(from: Fixture.data("standings_groups"), leagueID: "uefa.nations")
        #expect(groups.map(\.name) == ["Group A1", "Group A2"])
        let spain = try #require(groups.first?.entries.first)
        #expect(spain.team.shortName == "Spain")
        #expect(spain.team.leagueID == "uefa.nations")
        #expect(spain.points == 6)
        #expect(spain.wins == 0)
    }
}

@Suite("ESPN teams normalization")
struct ESPNTeamsMappingTests {
    @Test func teamsAreSortedByShortNameCaseInsensitively() throws {
        let teams = try ESPNMapper.teams(from: Fixture.data("teams"), leagueID: "eng.1")
        #expect(teams.map(\.shortName) == ["Arsenal", "Bournemouth", "Man City"])
        // Numeric ids are stringified; colors get a leading '#'.
        #expect(teams[1].id == "349")
        #expect(teams[1].colorHex == "#f42727")
        #expect(teams[0].colorHex == "")
        #expect(teams.allSatisfy { $0.leagueID == "eng.1" })
    }

    @Test func missingTeamListYieldsEmptyArray() throws {
        let teams = try ESPNMapper.teams(from: Data("{}".utf8), leagueID: "eng.1")
        #expect(teams.isEmpty)
    }
}

@Suite("Domain catalog")
struct DomainCatalogTests {
    @Test func leagueCatalogMatchesOriginal() {
        #expect(League.all.map(\.id) == ["esp.1", "ita.1", "eng.1", "usa.1", "uefa.champions", "uefa.nations"])
        #expect(League.all.filter(\.isNational).map(\.id) == ["uefa.nations"])
        #expect(League.with(id: "eng.1")?.short == "Premier")
        #expect(League.with(id: "nope") == nil)
    }

    @Test func crestURLs() {
        let team = Team(id: "359", leagueID: "eng.1", name: "Arsenal", shortName: "Arsenal", abbreviation: "ARS")
        #expect(team.crestURL().absoluteString
                == "https://a.espncdn.com/combiner/i?img=/i/teamlogos/soccer/500/359.png&w=128&h=128")
        #expect(League.premierLeague.crestURL(dark: true).absoluteString
                == "https://a.espncdn.com/combiner/i?img=/i/leaguelogos/soccer/500-dark/23.png&w=128&h=128")
    }

    @Test func favoriteKeyCombinesLeagueAndTeam() {
        let fav = FavoriteTeam(leagueID: "uefa.champions", teamID: "83", name: "Barcelona",
                               shortName: "Barcelona", abbreviation: "BAR")
        #expect(fav.key == "uefa.champions:83")
    }
}
