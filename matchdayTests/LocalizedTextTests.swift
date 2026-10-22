//
//  LocalizedTextTests.swift
//  matchdayTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import matchday

/// Text built outside SwiftUI follows the language bundle it is given, and the
/// string catalog holds every key the app resolves at runtime.
@Suite("Localized text")
final class LocalizedTextTests {
    private let bundles = TemporaryBundles()
    /// Wednesday, October 21 2026, 17:07 UTC.
    private let now = utcDate(2026, 10, 21, 17, 7)

    /// A Japanese copy of a few derivation keys.
    private func japanese() throws -> Bundle {
        let base = try bundles.make(["ja": """
            "Today" = "今日";
            "NEXT · %@ · %@" = "次 · %1$@ · %2$@";
            "in %lldh %@m" = "あと%1$lld時間%2$@分";
            "%@ vs %@ in %lld min" = "%1$@ 対 %2$@（あと%3$lld分）";
            "Loading fixtures…" = "日程を読み込み中…";
            """])
        return AppLocalization.bundle(for: .japanese, in: base)
    }

    @Test func derivationsResolveThroughTheirLanguageBundle() throws {
        let display = DisplayContext(now: now, calendar: utcCalendar(), locale: Locale(identifier: "ja_JP"),
                                     bundle: try japanese())
        let madrid = Make.team("rma", abbreviation: "RMA"), sevilla = Make.team("sev", abbreviation: "SEV")
        let tonight = Make.match("s", home: madrid, away: sevilla, at: utcDate(2026, 10, 21, 21))
        let card = try #require(Derivations.followingCards(
            snapshot: Make.snapshot([tonight]), settings: Make.settings(following: [madrid]),
            display: display, watch: { _ in .none }).first)

        #expect(card.kicker == "次 · 今日 · 21:00")
        #expect(card.countdown == "あと3時間53分")
        #expect(Derivations.headerSummary(snapshot: Make.snapshot([], status: .loading), cards: [],
                                          window: [], display: display) == "日程を読み込み中…")
    }

    @Test func notificationsResolveThroughTheirLanguageBundle() throws {
        let madrid = Make.team("rma"), sevilla = Make.team("sev")
        let soon = Make.match("s", home: madrid, away: sevilla, at: now.addingTimeInterval(10 * 60))
        var settings = Make.settings(following: [madrid])
        settings.kickoffLead = 15
        let plan = NotificationPlanner.plan(matches: [soon], settings: settings, memory: NotificationMemory(),
                                            now: now, watch: { _ in .none },
                                            bundle: try japanese(), locale: Locale(identifier: "ja"))
        #expect(plan.notifications.first?.title.hasPrefix("\(madrid.shortName) 対 \(sevilla.shortName)") == true)
    }

    // MARK: Catalog

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            let comment: String?
        }

        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func catalog() throws -> Catalog {
        let data = try Data(contentsOf: ReleasePipelineSources.url("Localizable.xcstrings"))
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    @Test func catalogIsEnglishSourced() throws {
        #expect(try catalog().sourceLanguage == "en")
    }

    /// Keys resolved through `String(appLocalized:)` or looked up at runtime,
    /// which Xcode only extracts from an IDE build (or not at all).
    @Test(arguments: [
        "Today", "Tomorrow", "Yesterday", "kicking off", "in %lldh %@m", "HT", "FT", "PPD", "LIVE",
        "Loading fixtures…", "Offline · %@", "%lld live now", "Next %@ v %@ · %@", "Stale",
        "Matchday — follow some teams", "%@ vs %@ in %lld min", "Watch on %@", "GOAL! %@", "Goal · %@",
        "Full time · Win for %@", "About Matchday", "Quit Matchday", "Automatic — %@", "unknown",
        "System", "Light", "Dark", "Data", "License", "Source", "Version", "Unknown",
        "✓ confirmed for this match", "Following", "Matches", "Tables", "Teams", "Settings",
        "Click a club to follow or unfollow it.", "Click a team to follow or unfollow it.",
        "Matchday, a followed team is live", "%@ · %lld pts · %lld played", "%@ in %@",
    ])
    func catalogHasRuntimeKey(_ key: String) throws {
        #expect(try catalog().strings[key] != nil, "missing key \(key)")
    }

    /// A noun spliced into a sentence cannot be translated; each case is its own sentence.
    @Test func noSentenceTakesASplicedNoun() throws {
        #expect(try catalog().strings["Click a %@ to follow or unfollow it."] == nil)
    }

    /// Single letters and abbreviations are ambiguous without a note.
    @Test(arguments: ["FT", "HT", "P", "W", "D", "L", "GD", "PTS", "vs", "%@ %@ (P)", "%@ %@ (OG)"])
    func shortKeysCarryATranslatorComment(_ key: String) throws {
        let comment = try #require(try catalog().strings[key]).comment ?? ""
        #expect(comment.count > 10, "key \(key) needs a comment")
    }
}

/// The About window follows the app language while it is open.
@MainActor
@Suite("About window")
final class AboutWindowTests {
    private let bundles = TemporaryBundles()

    @Test func anOpenWindowIsRetitledWhenTheLanguageChanges() async throws {
        // With `en.lproj`, as the app has: a flat bundle with only `ja.lproj` would read Japanese everywhere.
        let base = try bundles.make(["ja": #""About %@" = "%@について";"#, "en": ""])
        let store = try StoreFactory.make()
        let controller = AboutWindowController(info: AboutModel.info(bundleInfo: [:]), store: store, base: base)
        controller.loadWindow()
        #expect(controller.windowTitle == "About Matchday")

        store.setLanguage(.japanese)
        await waitUntil { controller.windowTitle == "Matchdayについて" }
        #expect(controller.windowTitle == "Matchdayについて")
    }
}

/// League short names are data: they are drawn verbatim, never looked up.
@MainActor
@Suite("Chip titles")
struct ChipTitleTests {
    @Test func aLiteralTitleIsLocalizedAndALeagueNameVerbatim() {
        #expect(Chip(title: "All", isSelected: false) {}.title == Text("All"))
        #expect(Chip(verbatim: "Serie A", isSelected: false) {}.title == Text(verbatim: "Serie A"))
        #expect(Chip(verbatim: "Serie A", isSelected: false) {}.title != Text("Serie A"))
    }
}
