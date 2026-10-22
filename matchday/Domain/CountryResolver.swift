//
//  CountryResolver.swift
//  matchday
//
//  Country used for where-to-watch (`detect_location` / `Engine.country` in the original).
//

import Foundation

nonisolated struct CountryResolver: Sendable {
    /// The system region, e.g. `ES`; `nil` when the system has none.
    let regionCode: String?
    let timeZone: TimeZone
    /// Locale used to name countries.
    let locale: Locale

    init(regionCode: String?, timeZone: TimeZone, locale: Locale) {
        self.regionCode = regionCode?.uppercased()
        self.timeZone = timeZone
        self.locale = locale
    }

    static var current: CountryResolver {
        CountryResolver(regionCode: Locale.current.region?.identifier, timeZone: .current, locale: .current)
    }

    /// ISO country code for a `country` setting: the system region for `auto`, else the code itself.
    func countryCode(for setting: String) -> String? {
        let trimmed = setting.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == AppSettings.automaticCountry { return regionCode }
        return trimmed.uppercased()
    }

    /// City of the system time zone, e.g. `New York` for `America/New_York`.
    var city: String {
        let identifier = timeZone.identifier
        guard identifier.contains("/") else { return "" }
        return identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? ""
    }

    /// The same resolver naming countries in `locale` (the app's).
    func naming(in locale: Locale) -> CountryResolver {
        CountryResolver(regionCode: regionCode, timeZone: timeZone, locale: locale)
    }

    func countryName(for code: String) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    /// "Madrid, Spain": shown next to the automatic choice (`auto_label`).
    var automaticLabel: String {
        let name = regionCode.map(countryName(for:))
            ?? String(appLocalized: "unknown", bundle: locale.appBundle, locale: locale,
                      comment: "Country of the Mac when it has no region, after the city: “Madrid, unknown”.")
        return city.isEmpty ? name : "\(city), \(name)"
    }
}
