//
//  MatchRepositoryTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Match repository")
struct MatchRepositoryTests {
    /// 16:00 UTC on the fixture day: the Arsenal match in `scoreboard.json` is at halftime.
    let now = utcDate(2026, 10, 18, 16)
    let arsenal = FavoriteTeam(leagueID: "eng.1", teamID: "359", name: "Arsenal",
                               shortName: "Arsenal", abbreviation: "ARS")
    let fixtures: [String: Data]

    init() throws {
        fixtures = [
            "scoreboard": try Fixture.data("scoreboard"),
            "schedule": try Fixture.data("schedule"),
            "standings": try Fixture.data("standings"),
            "teams": try Fixture.data("teams"),
        ]
    }

    /// Serves the fixtures; only 2026-10-18 has scoreboard events.
    private func espnHandler() -> @Sendable (URL) -> FakeTransport.Reply {
        let fixtures = fixtures
        return { url in
            let text = url.absoluteString
            if text.contains("/scoreboard") {
                return text.hasSuffix("dates=20261018") ? .data(fixtures["scoreboard"]!) : .json(#"{"events":[]}"#)
            }
            if text.contains("/schedule") { return .data(fixtures["schedule"]!) }
            if text.contains("/standings") { return .data(fixtures["standings"]!) }
            if text.hasSuffix("/teams") { return .data(fixtures["teams"]!) }
            return .status(404, "")
        }
    }

    private func makeRepository(_ transport: FakeTransport, directory: URL = temporaryDirectory()) -> MatchRepository {
        MatchRepository(client: ESPNClient(transport: transport, calendar: utcCalendar()),
                        cache: HTTPCache(directory: directory),
                        calendar: utcCalendar())
    }

    @Test func coldStartFetchesEveryJob() async throws {
        let transport = FakeTransport(handler: espnHandler())
        let repository = makeRepository(transport)
        let snapshot = await repository.refreshDue(now: now, leagues: ["eng.1"], favorites: [arsenal])

        // 13 scoreboard days + table + teams, then schedule + fixtures for the favorite.
        let urls = await transport.requestedURLs
        #expect(urls.count == 13 + 2 + 2)
        #expect(urls.contains { $0.hasSuffix("/eng.1/scoreboard?dates=20261015") })
        #expect(urls.contains { $0.hasSuffix("/eng.1/scoreboard?dates=20261027") })
        #expect(urls.contains { $0.hasSuffix("/teams/359/schedule?fixture=true") })

        #expect(snapshot.status == .ok)
        // 3 scoreboard events + 2 schedule events (one per id), sorted by kickoff.
        #expect(snapshot.matches.map(\.id) == ["401879263", "401879270", "401878769", "401879299", "401878800"])
        #expect(snapshot.tables["eng.1"]?.first?.entries.count == 3)
        #expect(snapshot.teams["eng.1"]?.count == 3)
        #expect(snapshot.liveLeagueIDs == ["eng.1"])
    }

    @Test func onlyHotScoreboardsRefreshQuickly() async throws {
        let transport = FakeTransport(handler: espnHandler())
        let repository = makeRepository(transport)
        _ = await repository.refreshDue(now: now, leagues: ["eng.1"], favorites: [arsenal])

        await transport.resetRequests()
        _ = await repository.refreshDue(now: now.addingTimeInterval(10), leagues: ["eng.1"], favorites: [arsenal])
        #expect(await transport.requestedURLs.isEmpty)

        // After 30 s only today's (hot) scoreboard is due; the live table waits 10 minutes.
        _ = await repository.refreshDue(now: now.addingTimeInterval(31), leagues: ["eng.1"], favorites: [arsenal])
        #expect(await transport.requestedURLs == [
            "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard?dates=20261018",
        ])
    }

    @Test func forceRefreshRefetchesEverything() async throws {
        let transport = FakeTransport(handler: espnHandler())
        let repository = makeRepository(transport)
        _ = await repository.refreshDue(now: now, leagues: ["eng.1"], favorites: [])
        await transport.resetRequests()

        await repository.forceRefresh(now: now.addingTimeInterval(5))
        _ = await repository.refreshDue(now: now.addingTimeInterval(6), leagues: ["eng.1"], favorites: [])
        #expect(await transport.requestedURLs.count == 15)
    }

    @Test func restartServesFreshDiskCacheWithoutFetching() async throws {
        let directory = temporaryDirectory()
        let first = FakeTransport(handler: espnHandler())
        _ = await makeRepository(first, directory: directory)
            .refreshDue(now: now, leagues: ["eng.1"], favorites: [])

        let second = FakeTransport(handler: espnHandler())
        let snapshot = await makeRepository(second, directory: directory)
            .refreshDue(now: now.addingTimeInterval(10), leagues: ["eng.1"], favorites: [])
        #expect(await second.requestedURLs.isEmpty)
        #expect(snapshot.matches.count == 3)
    }

    @Test func failuresBackOffForAMinute() async throws {
        let transport = FakeTransport { _ in .failure }
        let repository = makeRepository(transport)
        let offline = await repository.refreshDue(now: now, leagues: ["eng.1"], favorites: [])
        #expect(offline.status == .offline)
        #expect(offline.lastError != nil)

        await transport.resetRequests()
        _ = await repository.refreshDue(now: now.addingTimeInterval(59), leagues: ["eng.1"], favorites: [])
        #expect(await transport.requestedURLs.isEmpty)

        await transport.setHandler(espnHandler())
        let recovered = await repository.refreshDue(now: now.addingTimeInterval(61), leagues: ["eng.1"], favorites: [])
        #expect(await transport.requestedURLs.count == 15)
        #expect(recovered.status == .ok)
        #expect(recovered.lastError == nil)
    }

    @Test func staleWhenFailingLongAfterLastSuccess() async throws {
        let transport = FakeTransport(handler: espnHandler())
        let repository = makeRepository(transport)
        _ = await repository.refreshDue(now: now, leagues: ["eng.1"], favorites: [])

        await transport.setHandler { _ in .failure }
        let snapshot = await repository.refreshDue(now: now.addingTimeInterval(400), leagues: ["eng.1"], favorites: [])
        #expect(snapshot.status == .stale)
        #expect(snapshot.matches.count == 3)
    }

    @Test func scoreboardKeepsScheduleTVWhenItHasNone() async throws {
        let scoreboard = #"""
        {"events":[{"id":"1","date":"2026-10-18T19:00Z","competitions":[{"competitors":[
          {"homeAway":"home","team":{"id":"359"}},{"homeAway":"away","team":{"id":"382"}}]}]}]}
        """#
        let schedule = #"""
        {"events":[{"id":"1","date":"2026-10-18T19:00Z","competitions":[{"competitors":[
          {"homeAway":"home","team":{"id":"359"}},{"homeAway":"away","team":{"id":"382"}}],
          "broadcasts":[{"media":{"shortName":"Peacock"}}]}]}]}
        """#
        let transport = FakeTransport { url in
            let text = url.absoluteString
            if text.hasSuffix("dates=20261018") { return .json(scoreboard) }
            if text.contains("/schedule") { return .json(schedule) }
            return .json(#"{"events":[]}"#)
        }
        let snapshot = await makeRepository(transport)
            .refreshDue(now: now, leagues: ["eng.1"], favorites: [arsenal])
        let match = try #require(snapshot.matches.first { $0.id == "1" })
        #expect(match.tvNames == ["Peacock"])
    }

    @Test func unknownOrEmptyLeagueListFallsBackToAllLeagues() async throws {
        let transport = FakeTransport { _ in .json(#"{"events":[]}"#) }
        _ = await makeRepository(transport).refreshDue(now: now, leagues: ["nope"], favorites: [])
        #expect(await transport.requestedURLs.count == League.all.count * 15)
    }
}
