//
//  StoreFactory.swift
//  matchdayTests
//

import Foundation
@testable import matchday

/// A store with no data behind it, for tests about settings and language only.
@MainActor
enum StoreFactory {
    static func make(settings: AppSettings = AppSettings(),
                     locale: Locale = Locale(identifier: "en_US")) throws -> MatchdayStore {
        let transport = FakeTransport { _ in .status(404, "") }
        let repository = MatchRepository(client: ESPNClient(transport: transport, calendar: utcCalendar()),
                                         cache: HTTPCache(directory: temporaryDirectory()),
                                         calendar: utcCalendar())
        return MatchdayStore(
            repository: repository,
            settingsStore: InMemorySettingsStore(settings),
            whereToWatch: WhereToWatch(catalog: try BroadcasterCatalog.bundled()),
            countryResolver: CountryResolver(regionCode: "US", timeZone: TimeZone(identifier: "UTC")!,
                                             locale: locale),
            calendar: utcCalendar(),
            locale: locale,
            clock: { utcDate(2026, 10, 21, 17) }
        )
    }
}
