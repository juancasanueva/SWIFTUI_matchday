//
//  AppLanguage.swift
//  matchday
//
//  The languages Matchday ships, in the order the Settings flags offer them.
//

import Foundation

/// Raw values are the `.lproj` folder names, which is what the bundle lookup
/// and the saved setting both use.
nonisolated enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt-PT"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh-Hans"

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// The locale the app formats and looks strings up in: the system's own
    /// when it already speaks this language, so regional formats (24-hour time
    /// in Britain) survive, else this language's locale. The Portugal and
    /// Simplified Chinese copies always use their own, so a Brazilian or
    /// Taiwanese system never asks for a copy the app does not carry.
    func locale(preferring system: Locale) -> Locale {
        guard !rawValue.contains("-"), system.language.languageCode?.identifier == rawValue else { return locale }
        return system
    }

    /// The flag image set in the asset catalog.
    var flagAsset: String {
        switch self {
        case .english: "UK"
        case .spanish: "Spain"
        case .french: "France"
        case .german: "Germany"
        case .italian: "Italy"
        case .portuguese: "Portugal"
        case .japanese: "Japan"
        case .korean: "South-korea"
        case .chinese: "China"
        }
    }

    /// The language written in itself, never translated: a user who cannot read
    /// the current language still finds their own.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .chinese: "简体中文"
        }
    }

    /// The language a system locale resolves to, by language code alone: every
    /// Portuguese variant lands on the Portugal copy and every Chinese variant on
    /// Simplified Chinese, the ones shipped. Anything else falls back to English.
    static func matching(_ locale: Locale) -> AppLanguage {
        switch locale.language.languageCode?.identifier {
        case "es": .spanish
        case "fr": .french
        case "de": .german
        case "it": .italian
        case "pt": .portuguese
        case "ja": .japanese
        case "ko": .korean
        case "zh": .chinese
        default: .english
        }
    }
}
