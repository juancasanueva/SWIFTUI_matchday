//
//  ESPNClientTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("ESPN client")
struct ESPNClientTests {

    @Test func endpointURLsAndCacheKeys() {
        let calendar = utcCalendar()
        let day = ESPNEndpoint.dayStamp(utcDate(2026, 10, 8, 23, 30), calendar: calendar)
        #expect(day == "20261008")

        let site = "https://site.api.espn.com/apis/site/v2/sports/soccer"
        let cases: [(ESPNEndpoint, String, String)] = [
            (.scoreboard(league: "esp.1", day: day), "\(site)/esp.1/scoreboard?dates=20261008", "sb:esp.1:20261008"),
            (.standings(league: "ita.1"),
             "https://site.api.espn.com/apis/v2/sports/soccer/ita.1/standings", "table:ita.1"),
            (.teams(league: "usa.1"), "\(site)/usa.1/teams", "teams:usa.1"),
            (.schedule(league: "eng.1", teamID: "359", fixture: false),
             "\(site)/eng.1/teams/359/schedule", "sched:eng.1:359"),
            (.schedule(league: "uefa.champions", teamID: "83", fixture: true),
             "\(site)/uefa.champions/teams/83/schedule?fixture=true", "fix:uefa.champions:83"),
        ]
        for (endpoint, url, key) in cases {
            #expect(endpoint.url.absoluteString == url)
            #expect(endpoint.cacheKey == key)
        }
    }

    @Test func sendsUserAgentAndTimeout() async throws {
        let transport = FakeTransport { _ in .json(#"{"events":[]}"#) }
        let client = ESPNClient(transport: transport, calendar: utcCalendar())
        _ = try await client.data(for: .teams(league: "eng.1"))
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "grivera-matchday/1.0")
        #expect(request.timeoutInterval == 12)
        #expect(request.httpMethod == "GET")
    }

    @Test func espnErrorBodyBecomesAnError() async throws {
        let body = String(decoding: try Fixture.data("error"), as: UTF8.self)
        let client = ESPNClient(transport: FakeTransport { _ in .json(body) }, calendar: utcCalendar())
        await #expect(throws: ESPNError.api("Failed to get league")) {
            try await client.data(for: .standings(league: "eng.1"))
        }
    }

    @Test func nonSuccessStatusIsAnError() async {
        let client = ESPNClient(transport: FakeTransport { _ in .status(503, "busy") }, calendar: utcCalendar())
        await #expect(throws: ESPNError.http(503)) {
            try await client.data(for: .teams(league: "eng.1"))
        }
    }

    @Test func oversizedBodyIsRejected() async {
        let huge = Data(count: ESPNClient.maxBodySize + 1)
        let client = ESPNClient(transport: FakeTransport { _ in .data(huge) }, calendar: utcCalendar())
        await #expect(throws: ESPNError.tooLarge) {
            try await client.data(for: .teams(league: "eng.1"))
        }
    }

    @Test func bodyAtTheSizeLimitIsAccepted() async throws {
        let limit = Data(count: ESPNClient.maxBodySize)
        let client = ESPNClient(transport: FakeTransport { _ in .data(limit) }, calendar: utcCalendar())
        #expect(try await client.data(for: .teams(league: "eng.1")).count == ESPNClient.maxBodySize)
    }

    static let errorBodies: [(String, String?)] = [
        (#"{"code":400,"message":"bad league"}"#, "bad league"),
        (#"{"code":"x","message":"oops","detail":1}"#, "oops"),
        (#"{"code":0,"message":"fine"}"#, nil),
        (#"{"code":"","message":"fine"}"#, nil),
        (#"{"code":null,"message":"fine"}"#, nil),
        (#"{"message":"no code"}"#, nil),
        (#"{"code":1,"message":""}"#, nil),
        (#"{"code":1,"message":"busy","a":1,"b":2}"#, nil),
        (#"{"events":[]}"#, nil),
    ]

    @Test(arguments: errorBodies)
    func errorMessageDetection(body: String, message: String?) {
        #expect(ESPNClient.errorMessage(in: Data(body.utf8)) == message)
    }

    @Test func non2xxStatusesAreErrors() async {
        for code in [301, 404, 500] {
            let client = ESPNClient(transport: FakeTransport { _ in .status(code, "") }, calendar: utcCalendar())
            await #expect(throws: ESPNError.http(code)) {
                try await client.data(for: .standings(league: "eng.1"))
            }
        }
    }

    @Test func decodesThroughTheDataSourcePort() async throws {
        let scoreboard = try Fixture.data("scoreboard")
        let transport = FakeTransport { _ in .data(scoreboard) }
        let source: any SoccerDataSource = ESPNClient(transport: transport, calendar: utcCalendar())
        let matches = try await source.scoreboard(league: "eng.1", date: utcDate(2026, 10, 18, 12))
        #expect(matches.count == 3)
        #expect(await transport.requestedURLs
                == ["https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard?dates=20261018"])
    }
}
