//
//  MatchNotifierTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

/// Records notifications instead of showing them.
final class RecordingSender: NotificationSender, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [MatchNotification] = []

    var notifications: [MatchNotification] { lock.withLock { sent } }

    func send(_ notification: MatchNotification) {
        lock.withLock { sent.append(notification) }
    }
}

/// Notification memory kept in memory, standing in for `notified.json`.
final class InMemoryNotificationMemoryStore: NotificationMemoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var memory: NotificationMemory
    private(set) var saveCount = 0

    init(_ memory: NotificationMemory = NotificationMemory()) {
        self.memory = memory
    }

    func load() -> NotificationMemory {
        lock.withLock { memory }
    }

    func save(_ memory: NotificationMemory) {
        lock.withLock {
            self.memory = memory
            saveCount += 1
        }
    }
}

@Suite("Notification memory file")
struct FileNotificationMemoryStoreTests {
    @Test func savedMemoryLoadsBack() {
        let url = temporaryDirectory().appending(path: "notified.json")
        let store = FileNotificationMemoryStore(url: url)
        #expect(store.load() == NotificationMemory())

        var memory = NotificationMemory()
        memory.kickoff["1"] = utcDate(2026, 10, 21, 18)
        memory.final["2"] = utcDate(2026, 10, 20, 22)
        memory.scores["3"] = NotificationMemory.Score(value: "2-1", at: utcDate(2026, 10, 21, 19))
        store.save(memory)
        #expect(FileNotificationMemoryStore(url: url).load() == memory)
    }

    @Test func unreadableFileLoadsEmpty() throws {
        let url = temporaryDirectory().appending(path: "notified.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(FileNotificationMemoryStore(url: url).load() == NotificationMemory())
    }

    @Test func defaultFileLivesInApplicationSupport() {
        let path = FileNotificationMemoryStore.defaultURL().path
        #expect(path.hasSuffix("Application Support/com.juancasanueva.matchday/notified.json"))
    }
}

@MainActor
@Suite("Match notifier")
struct MatchNotifierTests {
    let now = utcDate(2026, 10, 21, 18)
    let madrid = Make.team("86", short: "Real Madrid")
    let barca = Make.team("83", short: "Barcelona")

    private func process(_ notifier: MatchNotifier, _ matches: [Match], at time: Date? = nil) {
        notifier.process(matches: matches, settings: Make.settings(following: [madrid]), now: time ?? now,
                         watch: { _ in .none })
    }

    @Test func sendsPlannedNotificationsAndPersistsPrunedMemory() {
        var stale = NotificationMemory()
        stale.kickoff["old"] = now.addingTimeInterval(-8 * 86_400)
        let memoryStore = InMemoryNotificationMemoryStore(stale)
        let sender = RecordingSender()
        let notifier = MatchNotifier(sender: sender, memoryStore: memoryStore)
        let match = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(300))

        process(notifier, [match])
        #expect(sender.notifications.map(\.id) == ["kick-1"])
        #expect(memoryStore.load().kickoff == ["1": now])
    }

    @Test func nothingNewSavesNothing() {
        let memoryStore = InMemoryNotificationMemoryStore()
        let notifier = MatchNotifier(sender: RecordingSender(), memoryStore: memoryStore)
        process(notifier, [Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(86_400))])
        #expect(memoryStore.saveCount == 0)
    }

    @Test func goalsSeenBeforeARestartAreNotRepeated() {
        let memoryStore = InMemoryNotificationMemoryStore()
        let live = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-1800), state: .in,
                              score: (1, 0))
        let firstSender = RecordingSender()
        process(MatchNotifier(sender: firstSender, memoryStore: memoryStore), [live])

        // Relaunch: a new notifier reads the saved memory.
        let secondSender = RecordingSender()
        let relaunched = MatchNotifier(sender: secondSender, memoryStore: memoryStore)
        process(relaunched, [live], at: now.addingTimeInterval(60))
        let scored = Make.match("1", home: madrid, away: barca, at: now.addingTimeInterval(-1800), state: .in,
                                score: (2, 0))
        process(relaunched, [scored], at: now.addingTimeInterval(120))

        #expect(firstSender.notifications.isEmpty)
        #expect(secondSender.notifications.map(\.title) == ["GOAL! Real Madrid"])
    }

    @Test func testNotificationGoesStraightToTheSender() {
        let sender = RecordingSender()
        let notifier = MatchNotifier(sender: sender, memoryStore: InMemoryNotificationMemoryStore())
        notifier.sendTest()
        #expect(sender.notifications == [.test])
    }
}

@Suite("Notification clicks")
struct NotificationClickTests {
    @Test func onlyWebLinksAreOpened() {
        #expect(UserNotificationSender.openableURL("https://www.espn.com/soccer/match/_/gameId/1")?.host() == "www.espn.com")
        #expect(UserNotificationSender.openableURL("HTTP://espn.com") != nil)
        #expect(UserNotificationSender.openableURL("file:///etc/passwd") == nil)
        #expect(UserNotificationSender.openableURL("") == nil)
    }
}
