//
//  matchdayTests.swift
//  matchdayTests
//

import Testing
@testable import matchday

struct matchdayTests {

    @Test func appModuleLoads() async throws {
        // Smoke test: the test bundle links against the app module.
        #expect(Bool(true))
    }

}
