//
//  EmptyMessageTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@MainActor
@Suite("Empty messages")
struct EmptyMessageTests {
    @Test func standingsMessageFollowsLoadAndConnection() {
        #expect(StandingsList.emptyMessage(isLoaded: true, status: .offline) == "No table for this league yet.")
        #expect(StandingsList.emptyMessage(isLoaded: false, status: .offline)
                == "Table unavailable — check your connection.")
        #expect(StandingsList.emptyMessage(isLoaded: false, status: .loading) == "Loading table…")
        #expect(StandingsList.emptyMessage(isLoaded: false, status: .ok) == "Loading table…")
    }

    @Test func matchesMessageExplainsWhyTheListIsEmpty() {
        #expect(MatchesList.emptyMessage(filter: .mine, hasFavorites: false, isLoading: true)
                == "You're not following anyone yet — pick teams in the Teams tab.")
        #expect(MatchesList.emptyMessage(filter: .all, hasFavorites: false, isLoading: true) == "Loading fixtures…")
        #expect(MatchesList.emptyMessage(filter: .mine, hasFavorites: true, isLoading: false)
                == "No matches in the next 10 days. International break?")
    }
}
