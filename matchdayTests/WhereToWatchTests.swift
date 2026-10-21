//
//  WhereToWatchTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Where to watch")
struct WhereToWatchTests {
    let catalog: BroadcasterCatalog
    let watch: WhereToWatch

    init() throws {
        catalog = try BroadcasterCatalog.bundled()
        watch = WhereToWatch(catalog: catalog)
    }

    private func match(league: String, home: String = "AAA", away: String = "BBB", tv: [String] = []) -> Match {
        func side(_ abbreviation: String) -> MatchSide {
            let team = Team(id: abbreviation, leagueID: league, name: abbreviation,
                            shortName: abbreviation, abbreviation: abbreviation)
            return MatchSide(team: team, score: nil, winner: false, form: "", record: "")
        }
        return Match(id: "m", leagueID: league, kickoff: utcDate(2026, 10, 21, 19), state: .pre,
                     statusName: "STATUS_SCHEDULED", shortDetail: "", displayClock: "", completed: false,
                     home: side(home), away: side(away), keyEvents: [], tvNames: tv,
                     espnURL: URL(string: "https://www.espn.com")!, venue: "", city: "", week: nil)
    }

    private func ids(_ options: WatchOptions) -> [String] { options.services.map(\.id) }

    @Test func bundledCatalogDecodes() {
        #expect(catalog.season == "2026-27")
        #expect(catalog.services["peacock"]?.name == "Peacock")
        #expect(catalog.services["telemundo"]?.language == "es")
        #expect(catalog.broadcaster(id: "itv").kind == .free)
        #expect(catalog.countries["GB"]?.name == "United Kingdom")
        #expect(catalog.countries["GB"]?.leagues["uefa.nations"]?.teams["ENG"] == ["itv"])
        #expect(catalog.countries["MX"]?.leagues["ita.1"]?.verified == false)
        #expect(catalog.everywhere["usa.1"]?.services == ["appletv"])
        #expect(catalog.espnAliases["usa net"] == "usa")
    }

    @Test func usUsesESPNListingsThroughAliases() {
        let options = watch.options(for: match(league: "eng.1", tv: ["USA Net", " Peacock ", "Some New Channel"]),
                                    country: "US", spanish: true)
        #expect(options.source == .espn)
        #expect(options.verified)
        #expect(ids(options) == ["usa", "peacock", "Some New Channel"])
        #expect(options.services[0].name == "USA Network")
        #expect(options.services[2].name == "Some New Channel")
        #expect(options.label == "✓ confirmed for this match")
    }

    @Test func usWithoutESPNListingsFallsBackToLeagueRights() {
        let options = watch.options(for: match(league: "eng.1"), country: "US", spanish: true)
        #expect(options.source == .rights)
        #expect(ids(options) == ["peacock", "usa", "nbc", "telemundo", "universo"])
        #expect(options.label == "league rights · channel TBA")
    }

    @Test func otherCountriesIgnoreESPNsUSListings() {
        let options = watch.options(for: match(league: "esp.1", tv: ["ESPN+"]), country: "ES", spanish: true)
        #expect(options.source == .rights)
        #expect(ids(options) == ["movistar", "dazn"])
    }

    @Test func everywhereFallbackForUnlistedCountry() {
        let options = watch.options(for: match(league: "usa.1"), country: "FR", spanish: true)
        #expect(ids(options) == ["appletv"])
        #expect(options.services.first?.name == "Apple TV")
    }

    @Test func unknownCountryHasNothingOutsideEverywhere() {
        #expect(watch.options(for: match(league: "eng.1"), country: "FR", spanish: true).services.isEmpty)
        #expect(watch.options(for: match(league: "eng.1"), country: nil, spanish: true).services.isEmpty)
    }

    @Test func nationalTeamRightsFollowWhoIsPlaying() {
        let england = watch.options(for: match(league: "uefa.nations", home: "ENG", away: "GRE"),
                                    country: "GB", spanish: true)
        #expect(ids(england) == ["itv"])
        let derby = watch.options(for: match(league: "uefa.nations", home: "SCO", away: "WAL"),
                                  country: "GB", spanish: true)
        #expect(ids(derby) == ["bbc", "s4c"])
        let others = watch.options(for: match(league: "uefa.nations", home: "FRA", away: "GER"),
                                   country: "GB", spanish: true)
        #expect(ids(others) == ["primevideo"])
    }

    @Test func unverifiedEntriesAreLabelled() {
        let options = watch.options(for: match(league: "ita.1"), country: "MX", spanish: true)
        #expect(!options.verified)
        #expect(options.label == "league rights · unconfirmed")
    }

    @Test func spanishOffDropsSpanishServices() {
        let options = watch.options(for: match(league: "eng.1"), country: "US", spanish: false)
        #expect(ids(options) == ["peacock", "usa", "nbc"])
    }

    @Test func spanishOffKeepsSpanishWhenItIsTheOnlyOption() {
        let options = watch.options(for: match(league: "ita.1"), country: "MX", spanish: false)
        #expect(ids(options) == ["espnlatam"])
    }

    @Test func duplicateServicesAreListedOnce() {
        let options = watch.options(for: match(league: "esp.1", tv: ["ESPN", "ESPN2", "ESPNU"]),
                                    country: "US", spanish: true)
        #expect(ids(options) == ["espn"])
    }

    @Test func countryCodesAreCaseInsensitive() {
        #expect(ids(watch.options(for: match(league: "esp.1"), country: "es", spanish: true)) == ["movistar", "dazn"])
    }

    @Test func footnoteNamesTheCountryAndSeason() {
        #expect(watch.footnote(countryCode: "ES", fallbackName: "Spain")
                == "Where to watch shows 2026-27 rights holders for Spain.")
        #expect(watch.footnote(countryCode: "FR", fallbackName: "France")
                == "Where to watch shows 2026-27 rights holders for France.")
        #expect(watch.footnote(countryCode: nil, fallbackName: nil)
                == "Where to watch shows 2026-27 rights holders for your country.")
        #expect(watch.footnote(countryCode: "US", fallbackName: nil).hasPrefix("Channels marked per match come from ESPN's US listings"))
    }

    @Test func countryListIsSortedByName() {
        #expect(catalog.countryChoices.map(\.code) == ["CA", "IE", "IT", "MX", "ES", "GB", "US"])
        #expect(catalog.knowsCountry("gb"))
        #expect(!catalog.knowsCountry("FR"))
    }
}
