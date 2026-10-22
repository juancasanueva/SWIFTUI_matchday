//
//  StringCatalogTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

/// Every shipped language carries every catalog key, with the same format
/// arguments as the English source, and the built app holds its `.lproj`.
@Suite("String catalog")
struct StringCatalogTests {
    private struct Catalog: Decodable {
        struct StringUnit: Decodable {
            let state: String
            let value: String
        }

        struct Variations: Decodable {
            let plural: [String: Localization]?
        }

        struct Localization: Decodable {
            let stringUnit: StringUnit?
            let variations: Variations?
        }

        struct Entry: Decodable {
            let localizations: [String: Localization]?
        }

        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private let catalog: Catalog

    init() throws {
        let data = try Data(contentsOf: ReleasePipelineSources.url("Localizable.xcstrings"))
        catalog = try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// Languages whose plural rules have a separate "one" form.
    private static let singularLanguages: Set<AppLanguage> = [.english, .spanish, .french, .german, .italian,
                                                             .portuguese]

    /// The texts of one localization: its string, or each of its plural forms.
    private func texts(_ localization: Catalog.Localization) -> [Catalog.StringUnit] {
        if let unit = localization.stringUnit { return [unit] }
        return localization.variations?.plural?.values.compactMap(\.stringUnit) ?? []
    }

    /// Format argument types in order of appearance, positions dropped:
    /// `%2$@ … %1$lld` and `%lld … %@` both read `["@", "lld"]` once sorted.
    private func arguments(_ text: String) -> [String] {
        text.replacingOccurrences(of: "%%", with: "")
            .matches(of: /%(?:\d+\$)?(lld|ld|d|@|f|s)/)
            .map { String($0.output.1) }
            .sorted()
    }

    @Test(arguments: AppLanguage.allCases)
    func everyKeyIsTranslated(_ language: AppLanguage) {
        for (key, entry) in catalog.strings {
            guard let localization = entry.localizations?[language.rawValue] else {
                // The source language may leave a key as its own text.
                #expect(language.rawValue == catalog.sourceLanguage, "\(language.rawValue) lacks \(key)")
                continue
            }
            if let plural = localization.variations?.plural {
                #expect(plural["other"] != nil, "\(language.rawValue) \(key) lacks the other plural form")
                if Self.singularLanguages.contains(language) {
                    #expect(plural["one"] != nil, "\(language.rawValue) \(key) lacks the one plural form")
                }
            }
            let units = texts(localization)
            #expect(!units.isEmpty, "\(language.rawValue) \(key) has no text")
            for unit in units where language.rawValue != catalog.sourceLanguage {
                #expect(unit.state == "translated", "\(language.rawValue) \(key) is \(unit.state)")
                #expect(!unit.value.isEmpty, "\(language.rawValue) \(key) is empty")
            }
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func translationsKeepTheSourceFormatArguments(_ language: AppLanguage) {
        for (key, entry) in catalog.strings {
            let expected = arguments(key)
            for unit in entry.localizations?[language.rawValue].map(texts) ?? [] {
                #expect(arguments(unit.value) == expected, "\(language.rawValue) \(key): \(unit.value)")
            }
        }
    }

    @Test func argumentsIgnorePositionsAndOrder() {
        #expect(arguments("%2$@ in %1$lld min") == arguments("%lld min: %@"))
        #expect(arguments("100%% %@") == ["@"])
        #expect(arguments("%@ %@") != arguments("%@"))
    }

    /// The unit-test host is the app, so its main bundle is the built Matchday.app.
    @Test(arguments: AppLanguage.allCases)
    func theBuiltAppShipsTheLanguage(_ language: AppLanguage) {
        #expect(Bundle.main.path(forResource: language.rawValue, ofType: "lproj") != nil,
                "Matchday.app lacks \(language.rawValue).lproj")
    }

    // MARK: The built catalog, resolved

    @Test func japaneseResolvesFromTheBuiltApp() {
        let bundle = AppLocalization.bundle(for: .japanese)
        let locale = Locale(identifier: "ja")
        #expect(String(appLocalizedKey: "Settings", bundle: bundle) == "設定")
        #expect(String(appLocalized: "About \("Matchday")", bundle: bundle, locale: locale) == "Matchdayについて")
    }

    @Test func spanishResolvesFromTheBuiltApp() {
        let bundle = AppLocalization.bundle(for: .spanish)
        let locale = Locale(identifier: "es_ES")
        let hours = 3, minutes = "05"
        #expect(String(appLocalizedKey: "HT", bundle: bundle) == "Descanso")
        #expect(String(appLocalized: "in \(hours)h \(minutes)m", bundle: bundle, locale: locale) == "en 3 h 05 min")
    }

    @Test func pluralFormsResolveFromTheBuiltApp() {
        let spanish = AppLocalization.bundle(for: .spanish), locale = Locale(identifier: "es_ES")
        let one = 1, many = 4
        #expect(String(appLocalized: "\(one) points", bundle: spanish, locale: locale) == "1 punto")
        #expect(String(appLocalized: "\(many) points", bundle: spanish, locale: locale) == "4 puntos")
        let english = AppLocalization.bundle(for: .english), us = Locale(identifier: "en_US")
        #expect(String(appLocalized: "\(one) points", bundle: english, locale: us) == "1 point")
    }
}
