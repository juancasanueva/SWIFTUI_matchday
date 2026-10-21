//
//  AppEnvironment.swift
//  matchday
//
//  Composition root: builds the adapters and the store the scenes share.
//

import Foundation
import OSLog

@MainActor
final class AppEnvironment {
    let store: MatchdayStore
    let launchAtLogin = LaunchAtLogin(service: MainAppLoginItem())
    /// `nil` in the unit-test host, which must never touch the notification center.
    private let notificationSender: UserNotificationSender?

    init(defaults: UserDefaults = .standard) {
        let calendar = Calendar.current
        let repository = MatchRepository(client: ESPNClient(transport: URLSessionTransport(), calendar: calendar),
                                         cache: HTTPCache(), calendar: calendar)
        let crests = CrestLoader.shared.cache
        let sender = Self.isHostingTests ? nil : UserNotificationSender(crestFile: { team in
            await crests.cachedFile(kind: .team, id: team.id, dark: false)
        })
        notificationSender = sender
        store = MatchdayStore(
            repository: repository,
            settingsStore: UserDefaultsSettingsStore(defaults: defaults),
            whereToWatch: WhereToWatch(catalog: Self.loadCatalog()),
            calendar: calendar,
            notifier: MatchNotifier(sender: sender ?? SilentNotificationSender(),
                                    memoryStore: FileNotificationMemoryStore())
        )
    }

    /// Starts polling and notification handling, except when the app only hosts the unit tests.
    func start() {
        guard !Self.isHostingTests else { return }
        notificationSender?.activate()
        store.start()
    }

    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The bundled broadcasters, or an empty catalog (no where-to-watch) if it is unreadable.
    private static func loadCatalog() -> BroadcasterCatalog {
        do {
            return try BroadcasterCatalog.bundled()
        } catch {
            Logger.app.error("Bundled broadcasters unreadable: \(error.localizedDescription)")
            return .empty
        }
    }
}

nonisolated extension Logger {
    static let app = Logger(subsystem: "com.juancasanueva.matchday", category: "app")
}
