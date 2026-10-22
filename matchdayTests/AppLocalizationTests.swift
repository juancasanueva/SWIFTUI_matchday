//
//  AppLocalizationTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

/// Builds throwaway bundles with real `.lproj` folders, because the app only
/// carries the languages already translated, and removes them when the test
/// that made them ends.
final class TemporaryBundles {
    private var roots: [URL] = []

    deinit {
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A flat bundle with one `.lproj` per entry of `strings` (language code to
    /// `Localizable.strings` text).
    func make(_ strings: [String: String]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLocalizationTests-\(UUID().uuidString)", isDirectory: true)
        roots.append(root)
        for (code, text) in strings {
            let folder = root.appendingPathComponent("\(code).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: folder.appendingPathComponent("Localizable.strings"))
        }
        return try #require(Bundle(url: root))
    }
}

/// The language bundle strings built outside SwiftUI resolve from. Each test
/// builds its own `AppLocalization`, so the process-wide `shared` one stays on
/// the development language.
@Suite("App localization")
final class AppLocalizationTests {
    private let bundles = TemporaryBundles()

    /// `ja.lproj` and `pt-PT.lproj` but no `ko.lproj`; `en.lproj` only when asked.
    private func makeBase(withEnglish: Bool = false) throws -> Bundle {
        var strings = [
            "ja": #""Hello %@" = "こんにちは %@";"# + "\n" + #""Language" = "言語";"#,
            "pt-PT": #""Hello %@" = "Olá %@";"# + "\n" + #""Language" = "Idioma";"#,
        ]
        if withEnglish { strings["en"] = #""Language" = "Language";"# }
        return try bundles.make(strings)
    }

    @Test func aShippedLanguageResolvesItsOwnLproj() throws {
        let base = try makeBase()
        #expect(AppLocalization.bundle(for: .japanese, in: base).bundlePath.hasSuffix("ja.lproj"))
        #expect(AppLocalization.bundle(for: .portuguese, in: base).bundlePath.hasSuffix("pt-PT.lproj"))
    }

    /// Not the base bundle, whose lookups follow the system languages: a Spanish
    /// Mac would get Spanish for a language Matchday does not carry yet.
    @Test func aLanguageWithoutAnLprojFallsBackToTheDevelopmentLanguage() throws {
        let base = try makeBase(withEnglish: true)
        #expect(AppLocalization.bundle(for: .korean, in: base).bundlePath.hasSuffix("en.lproj"))
    }

    @Test func withoutAnEnglishLprojTheFallbackIsTheBase() throws {
        let base = try makeBase()
        #expect(AppLocalization.bundle(for: .korean, in: base) === base)
    }

    @Test func startsOnTheDevelopmentLanguage() throws {
        let localization = AppLocalization(base: try makeBase(withEnglish: true))
        #expect(localization.bundle.bundlePath.hasSuffix("en.lproj"))
        #expect(localization.locale.language.languageCode?.identifier == "en")
    }

    @Test func applyingALanguageSwitchesBundleAndLocale() throws {
        let base = try makeBase()
        let localization = AppLocalization(base: base)

        localization.apply(.japanese, locale: Locale(identifier: "ja"))
        #expect(localization.bundle.bundlePath.hasSuffix("ja.lproj"))
        #expect(localization.locale.identifier == "ja")

        localization.apply(.korean, locale: Locale(identifier: "ko"))
        #expect(localization.bundle === base)
        #expect(localization.locale.identifier == "ko")
    }

    @Test func stringsResolveFromTheAppliedLanguageKeepingTheirArguments() throws {
        let base = try makeBase()
        let localization = AppLocalization(base: base)
        let name = "Juan"

        localization.apply(.japanese, locale: Locale(identifier: "ja"))
        #expect(String(appLocalized: "Hello \(name)", bundle: localization.bundle,
                       locale: localization.locale) == "こんにちは Juan")
        #expect(String(appLocalizedKey: "Language", bundle: localization.bundle) == "言語")

        localization.apply(.portuguese, locale: Locale(identifier: "pt-PT"))
        let resource = LocalizedStringResource("Hello \(name)")
        #expect(String(appLocalized: resource, bundle: localization.bundle,
                       locale: localization.locale) == "Olá Juan")
    }

    @Test func aMissingKeyFallsBackToItself() throws {
        let localization = AppLocalization(base: try makeBase())
        localization.apply(.japanese, locale: Locale(identifier: "ja"))
        #expect(String(appLocalizedKey: "Not in the catalog", bundle: localization.bundle) == "Not in the catalog")
    }

    @Test func temporaryBundlesAreRemovedWithTheirOwner() throws {
        var owner: TemporaryBundles? = TemporaryBundles()
        let path = try #require(owner).make(["ja": ""]).bundlePath
        #expect(FileManager.default.fileExists(atPath: path))
        owner = nil
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}

/// The step that keeps a language bundle on the store's effective language.
@MainActor
@Suite("Language observer")
final class LanguageObserverTests {
    private let bundles = TemporaryBundles()

    @Test func appliesTheStoresLanguageNowAndOnEveryChange() async throws {
        let base = try bundles.make(["ja": #""Language" = "言語";"#])
        let localization = AppLocalization(base: base)
        let store = try StoreFactory.make(locale: Locale(identifier: "en_US"))
        var applied: [AppLanguage] = []
        let observer = LanguageObserver(store: store) { language, locale in
            applied.append(language)
            localization.apply(language, locale: locale)
        }

        #expect(applied == [.english])
        store.setLanguage(.japanese)
        await waitUntil { applied.count == 2 }
        #expect(applied == [.english, .japanese])
        #expect(localization.bundle.bundlePath.hasSuffix("ja.lproj"))
        #expect(localization.locale.language.languageCode?.identifier == "ja")
        withExtendedLifetime(observer) {}
    }

    @Test func ignoresUnrelatedSettingsChanges() async throws {
        let store = try StoreFactory.make(locale: Locale(identifier: "en_US"))
        var count = 0
        let observer = LanguageObserver(store: store) { _, _ in count += 1 }
        store.setAppearance(.dark)
        store.setKickoffLead(30)
        // A language switch after them is reported once; had either of them been
        // reported too, the count would pass 2 by the time this one lands.
        store.setLanguage(.japanese)
        await waitUntil { count >= 2 }
        #expect(count == 2)
        withExtendedLifetime(observer) {}
    }
}
