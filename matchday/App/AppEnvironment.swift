//
//  AppEnvironment.swift
//  matchday
//
//  Composition root: builds the adapters and the store the scenes share.
//

import Foundation

@MainActor
final class AppEnvironment {
    let store: MatchdayStore
    let launchAtLogin = LaunchAtLogin(service: MainAppLoginItem())

    init(defaults: UserDefaults = .standard) {
        let calendar = Calendar.current
        let repository = MatchRepository(client: ESPNClient(transport: URLSessionTransport(), calendar: calendar),
                                         cache: HTTPCache(), calendar: calendar)
        store = MatchdayStore(
            repository: repository,
            settingsStore: UserDefaultsSettingsStore(defaults: defaults),
            whereToWatch: WhereToWatch(catalog: Self.loadCatalog()),
            calendar: calendar
        )
    }

    /// Starts polling, except when the app only hosts the unit tests.
    func start() {
        guard !Self.isHostingTests else { return }
        store.start()
    }

    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The bundled broadcasters, or an empty catalog (no where-to-watch) if it is unreadable.
    private static func loadCatalog() -> BroadcasterCatalog {
        if let catalog = try? BroadcasterCatalog.bundled() { return catalog }
        // Every key is optional, so an empty object decodes to an empty catalog.
        return try! BroadcasterCatalog.decode(Data("{}".utf8))
    }
}
