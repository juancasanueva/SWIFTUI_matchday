//
//  CrestCacheTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Crest cache")
struct CrestCacheTests {
    /// A PNG signature padded past the 200-byte sanity check.
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 7, count: 256)

    let directory = temporaryDirectory()
    let start = utcDate(2026, 10, 21, 12)

    /// A clock the test can move forward.
    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date
        init(_ date: Date) { self.date = date }
        var now: Date { lock.withLock { date } }
        func advance(_ seconds: TimeInterval) { lock.withLock { date += seconds } }
    }

    private func makeCache(_ transport: FakeTransport, clock: TestClock? = nil) -> CrestCache {
        let clock = clock ?? TestClock(start)
        return CrestCache(directory: directory, transport: transport, clock: { clock.now })
    }

    @Test func fileNamesMatchTheOriginal() {
        #expect(CrestCache.fileName(kind: .team, id: "86", dark: false) == "team-86.png")
        #expect(CrestCache.fileName(kind: .team, id: "86", dark: true) == "team-86-dark.png")
        #expect(CrestCache.fileName(kind: .league, id: "2395", dark: false) == "league-2395.png")
    }

    @Test func defaultDirectoryIsTheLogosCache() {
        #expect(CrestCache.defaultDirectory().path.hasSuffix("Caches/com.juancasanueva.matchday/logos"))
    }

    @Test func downloadsOnceThenServesFromDisk() async throws {
        let png = Self.png
        let transport = FakeTransport { _ in .data(png) }
        let cache = makeCache(transport)

        let file = try #require(await cache.file(kind: .team, id: "86", dark: true))
        #expect(file.lastPathComponent == "team-86-dark.png")
        #expect(try Data(contentsOf: file) == png)
        #expect(await transport.requestedURLs == [Crest.url(kind: .team, id: "86", dark: true).absoluteString])

        // A new cache over the same directory (next launch) does not download again.
        let relaunched = makeCache(transport)
        #expect(await relaunched.file(kind: .team, id: "86", dark: true) == file)
        #expect(await relaunched.cachedFile(kind: .team, id: "86", dark: true) == file)
        #expect(await transport.requestedURLs.count == 1)
    }

    static let badReplies: [FakeTransport.Reply] = [.status(404, ""), .json("<html>not a png</html>")]

    @Test func transportFailuresAreRetriedWithoutAMarker() async throws {
        let transport = FakeTransport { _ in .failure }
        let cache = makeCache(transport)
        #expect(await cache.file(kind: .team, id: "86", dark: false) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "team-86.png.missing").path))

        let png = Self.png
        await transport.setHandler { _ in .data(png) }
        let file = await cache.file(kind: .team, id: "86", dark: false)
        #expect(file?.lastPathComponent == "team-86.png")
        #expect(await transport.requestedURLs.count == 2)
    }

    @Test(arguments: badReplies)
    func failuresLeaveAMissingMarker(reply: FakeTransport.Reply) async {
        let transport = FakeTransport { _ in reply }
        let cache = makeCache(transport)
        #expect(await cache.file(kind: .team, id: "86", dark: false) == nil)
        let marker = directory.appending(path: "team-86.png.missing")
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "team-86.png").path))
    }

    @Test func missingMarkerIsRetriedAfterADay() async throws {
        let transport = FakeTransport { _ in .status(404, "") }
        let clock = TestClock(start)
        let cache = makeCache(transport, clock: clock)
        #expect(await cache.file(kind: .team, id: "86", dark: false) == nil)

        clock.advance(23 * 3600)
        #expect(await cache.file(kind: .team, id: "86", dark: false) == nil)
        #expect(await transport.requestedURLs.count == 1)

        let png = Self.png
        await transport.setHandler { _ in .data(png) }
        clock.advance(3600 + 1)
        let file = await cache.file(kind: .team, id: "86", dark: false)
        #expect(file?.lastPathComponent == "team-86.png")
        #expect(await transport.requestedURLs.count == 2)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "team-86.png.missing").path))
    }

    @Test func concurrentRequestsShareOneDownload() async {
        let png = Self.png
        let transport = FakeTransport { _ in .data(png) }
        let cache = makeCache(transport)
        async let first = cache.file(kind: .team, id: "86", dark: false)
        async let second = cache.file(kind: .team, id: "86", dark: false)
        let files = await [first, second]
        #expect(files[0] != nil && files[0] == files[1])
        #expect(await transport.requestedURLs.count == 1)
    }
}
