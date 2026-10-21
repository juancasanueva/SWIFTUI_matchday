//
//  MatchNotifier.swift
//  matchday
//
//  Runs the notification planner after each refresh, persists what was
//  announced and hands the alerts to the system (`Notifier` in the original).
//

import Foundation

/// Port for showing alerts. The UserNotifications adapter lives in `Data/Notifications`.
/// `send` returns at once; delivery (and asking for permission) happens in the background.
nonisolated protocol NotificationSender: Sendable {
    func send(_ notification: MatchNotification)
}

/// Port for persisting `NotificationMemory` across launches.
nonisolated protocol NotificationMemoryStore: Sendable {
    func load() -> NotificationMemory
    func save(_ memory: NotificationMemory)
}

/// A sender that drops every alert (unit-test host, previews).
nonisolated struct SilentNotificationSender: NotificationSender {
    func send(_ notification: MatchNotification) {}
}

@MainActor
final class MatchNotifier {
    private let sender: any NotificationSender
    private let memoryStore: any NotificationMemoryStore
    /// Loaded on first use, so launching does not read the file twice.
    private var memory: NotificationMemory?

    init(sender: any NotificationSender, memoryStore: any NotificationMemoryStore) {
        self.sender = sender
        self.memoryStore = memoryStore
    }

    /// Plans alerts for `matches`, saves the updated memory and sends the alerts.
    func process(matches: [Match], settings: AppSettings, now: Date, watch: (Match) -> WatchOptions) {
        let current = memory ?? memoryStore.load()
        let plan = NotificationPlanner.plan(matches: matches, settings: settings, memory: current, now: now,
                                            watch: watch)
        if plan.changed {
            let pruned = plan.memory.pruned(now: now)
            memory = pruned
            memoryStore.save(pruned)
        } else {
            memory = current
        }
        plan.notifications.forEach(sender.send)
    }

    func sendTest() {
        sender.send(.test)
    }
}
