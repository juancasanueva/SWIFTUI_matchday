//
//  FileNotificationMemoryStore.swift
//  matchday
//
//  `notified.json` in Application Support, so alerts are not repeated after
//  a relaunch.
//

import Foundation
import OSLog

nonisolated struct FileNotificationMemoryStore: NotificationMemoryStore {
    let url: URL

    init(url: URL = FileNotificationMemoryStore.defaultURL()) {
        self.url = url
    }

    /// `Application Support/com.juancasanueva.matchday/notified.json` (inside the sandbox container).
    static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appending(path: "com.juancasanueva.matchday/notified.json")
    }

    /// The saved memory, or an empty one when the file is missing or unreadable.
    func load() -> NotificationMemory {
        guard let data = try? Data(contentsOf: url),
              let memory = try? JSONDecoder().decode(NotificationMemory.self, from: data)
        else { return NotificationMemory() }
        return memory
    }

    func save(_ memory: NotificationMemory) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(memory).write(to: url, options: .atomic)
        } catch {
            Logger.notifications.error("Could not save notification memory: \(error.localizedDescription)")
        }
    }
}

nonisolated extension Logger {
    static let notifications = Logger(subsystem: "com.juancasanueva.matchday", category: "notifications")
}
