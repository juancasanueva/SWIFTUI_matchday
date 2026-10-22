//
//  AppLanguageTests.swift
//  matchdayTests
//

import AppKit
import Foundation
import Testing
@testable import matchday

/// The languages behind the Settings flags: picker order, how a system locale
/// resolves to one, and what the flags need to draw.
@Suite("App language")
struct AppLanguageTests {
    @Test func shippedLanguagesAreInPickerOrder() {
        #expect(AppLanguage.allCases.map(\.rawValue) == ["en", "es", "fr", "de", "it", "pt-PT", "ja", "ko", "zh-Hans"])
    }

    @Test("Every shipped language is matched from its system locale, variants included", arguments: [
        ("en_GB", AppLanguage.english), ("es_MX", .spanish), ("fr_CA", .french), ("de_AT", .german),
        ("it_IT", .italian), ("pt_BR", .portuguese), ("pt_PT", .portuguese), ("ja_JP", .japanese),
        ("ko_KR", .korean), ("zh_TW", .chinese), ("zh_Hans_CN", .chinese), ("nl_NL", .english),
    ])
    func matching(identifier: String, expected: AppLanguage) {
        #expect(AppLanguage.matching(Locale(identifier: identifier)) == expected)
    }

    /// Native names are never translated: a user who cannot read the current
    /// language still finds their own.
    @Test func everyLanguageNamesItself() {
        #expect(AppLanguage.allCases.map(\.nativeName)
            == ["English", "Español", "Français", "Deutsch", "Italiano", "Português", "日本語", "한국어", "简体中文"])
    }

    @Test func everyLanguagePointsAtAFlagThatShips() {
        #expect(AppLanguage.allCases.map(\.flagAsset)
            == ["UK", "Spain", "France", "Germany", "Italy", "Portugal", "Japan", "South-korea", "China"])
        for language in AppLanguage.allCases {
            #expect(NSImage(named: language.flagAsset) != nil, "missing flag asset \(language.flagAsset)")
        }
    }

    @Test func localeIsTheLprojName() {
        #expect(AppLanguage.japanese.locale.identifier == "ja")
        #expect(AppLanguage.portuguese.locale.language.languageCode?.identifier == "pt")
    }

    /// A system that already speaks the language keeps its regional formats
    /// (24-hour time in Britain); any other language uses its own locale.
    @Test func localeKeepsTheSystemsRegionalFormatsForTheSameLanguage() {
        let british = Locale(identifier: "en_GB")
        #expect(AppLanguage.english.locale(preferring: british) == british)
        #expect(AppLanguage.spanish.locale(preferring: british).identifier == "es")
        let mexican = Locale(identifier: "es_MX")
        #expect(AppLanguage.spanish.locale(preferring: mexican) == mexican)
        // Region- or script-specific copies always use their own locale.
        #expect(AppLanguage.portuguese.locale(preferring: Locale(identifier: "pt_BR")) == AppLanguage.portuguese.locale)
        #expect(AppLanguage.chinese.locale(preferring: Locale(identifier: "zh_CN")) == AppLanguage.chinese.locale)
    }
}
