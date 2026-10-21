//
//  HTTPCacheTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("HTTP disk cache")
struct HTTPCacheTests {
    let directory = temporaryDirectory()
    let now = utcDate(2026, 10, 18, 16)
    let payload = Data(#"{"events":[{"id":"1"}]}"#.utf8)

    private func decoded(_ data: Data?) throws -> NSDictionary {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func roundTripsThroughDisk() async throws {
        let cache = HTTPCache(directory: directory)
        await cache.store(payload, for: "sb:eng.1:20261018", at: now)

        // A new instance (fresh launch) loads the entry on demand.
        let reloaded = HTTPCache(directory: directory)
        let entry = try #require(await reloaded.entry(for: "sb:eng.1:20261018"))
        #expect(entry.fetchedAt == now)
        #expect(try decoded(entry.data) == decoded(payload))
        #expect(await reloaded.age(of: "sb:eng.1:20261018", now: now.addingTimeInterval(42)) == 42)
        #expect(await reloaded.entry(for: "table:eng.1") == nil)
        #expect(await reloaded.age(of: "table:eng.1", now: now) == .infinity)
    }

    @Test func writesTimestampedJSONFiles() async throws {
        let cache = HTTPCache(directory: directory)
        await cache.store(payload, for: "fix:eng.1:359", at: now)
        let file = directory.appending(path: "fix_eng.1_359.json")
        let object = try decoded(try Data(contentsOf: file))
        #expect(object["at"] as? Double == now.timeIntervalSince1970)
        #expect(object["key"] as? String == "fix:eng.1:359")
        #expect(object["data"] is NSDictionary)
    }

    @Test func invalidateAllExpiresButKeepsData() async throws {
        let cache = HTTPCache(directory: directory)
        await cache.store(payload, for: "table:eng.1", at: now)
        await cache.invalidateAll(now: now.addingTimeInterval(5))
        #expect(await cache.age(of: "table:eng.1", now: now.addingTimeInterval(6)) == .infinity)
        #expect(await cache.entry(for: "table:eng.1") != nil)

        // Entries fetched after the invalidation age normally again.
        await cache.store(payload, for: "table:eng.1", at: now.addingTimeInterval(10))
        #expect(await cache.age(of: "table:eng.1", now: now.addingTimeInterval(15)) == 5)
    }

    @Test func pruneDropsOnlyScoreboardsOutsideTheWindow() async throws {
        let cache = HTTPCache(directory: directory)
        await cache.store(payload, for: "sb:eng.1:20261001", at: now)
        await cache.store(payload, for: "sb:eng.1:20261018", at: now)
        await cache.store(payload, for: "table:eng.1", at: now)
        await cache.prune(keepingScoreboards: ["sb:eng.1:20261018"])

        let reloaded = HTTPCache(directory: directory)
        #expect(await reloaded.entry(for: "sb:eng.1:20261001") == nil)
        #expect(await reloaded.entry(for: "sb:eng.1:20261018") != nil)
        #expect(await reloaded.entry(for: "table:eng.1") != nil)
    }
}
