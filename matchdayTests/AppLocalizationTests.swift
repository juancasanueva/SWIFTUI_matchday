//
//  AppLocalizationTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

/// The language bundle strings built outside SwiftUI resolve from. Each test
/// builds a throwaway bundle with real `.lproj` folders, because the app only
/// carries the languages already translated, and its own `AppLocalization`,
/// so the process-wide `shared` one stays on the development language.
@Suite("App localization")
struct AppLocalizationTests {
    /// A flat bundle with `ja.lproj` and `pt-PT.lproj` but no `ko.lproj`.
    private func makeBase() throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLocalizationTests-\(UUID().uuidString)", isDirectory: true)
        let strings = [
            "ja": #""Hello %@" = "こんにちは %@";"# + "\n" + #""Language" = "言語";"#,
            "pt-PT": #""Hello %@" = "Olá %@";"# + "\n" + #""Language" = "Idioma";"#,
        ]
        for (code, text) in strings {
            let folder = root.appendingPathComponent("\(code).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: folder.appendingPathComponent("Localizable.strings"))
        }
        return try #require(Bundle(url: root))
    }

    @Test func aShippedLanguageResolvesItsOwnLproj() throws {
        let base = try makeBase()
        #expect(AppLocalization.bundle(for: .japanese, in: base).bundlePath.hasSuffix("ja.lproj"))
        #expect(AppLocalization.bundle(for: .portuguese, in: base).bundlePath.hasSuffix("pt-PT.lproj"))
    }

    @Test func aLanguageWithoutAnLprojFallsBackToTheBase() throws {
        let base = try makeBase()
        #expect(AppLocalization.bundle(for: .korean, in: base) === base)
    }

    @Test func startsOnTheBaseBundle() throws {
        let base = try makeBase()
        let localization = AppLocalization(base: base)
        #expect(localization.bundle === base)
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
}
