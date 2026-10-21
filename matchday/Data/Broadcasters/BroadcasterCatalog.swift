//
//  BroadcasterCatalog.swift
//  matchday
//
//  The bundled `broadcasters.json` rights table (`load_rights` in the original plugin).
//

import Foundation

nonisolated struct BroadcasterCatalog: Decodable, Sendable {
    nonisolated struct Service: Decodable, Hashable, Sendable {
        let name: String
        let url: String?
        let color: String?
        let kind: String?
        let language: String?

        private enum CodingKeys: String, CodingKey {
            case name, url, color, kind
            case language = "lang"
        }
    }

    /// A league's rights in one country: a plain list, or services plus
    /// per-team services for national-team competitions.
    nonisolated struct Rights: Decodable, Hashable, Sendable {
        let services: [String]
        /// ESPN team abbreviation -> services when that team plays.
        let teams: [String: [String]]
        let verified: Bool

        init(services: [String], teams: [String: [String]] = [:], verified: Bool = true) {
            self.services = services
            self.teams = teams
            self.verified = verified
        }

        private enum CodingKeys: String, CodingKey {
            case services, teams, verified
        }

        init(from decoder: Decoder) throws {
            if let list = try? decoder.singleValueContainer().decode([String].self) {
                self.init(services: list)
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(services: try container.decodeIfPresent([String].self, forKey: .services) ?? [],
                      teams: try container.decodeIfPresent([String: [String]].self, forKey: .teams) ?? [:],
                      verified: try container.decodeIfPresent(Bool.self, forKey: .verified) ?? true)
        }
    }

    /// One country: its display name plus league id -> rights.
    nonisolated struct Country: Decodable, Hashable, Sendable {
        let name: String
        let leagues: [String: Rights]

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            var name = ""
            var leagues: [String: Rights] = [:]
            for key in container.allKeys {
                if key.stringValue == "name" {
                    name = try container.decode(String.self, forKey: key)
                } else if let rights = try? container.decode(Rights.self, forKey: key) {
                    leagues[key.stringValue] = rights
                }
            }
            self.name = name
            self.leagues = leagues
        }
    }

    nonisolated struct CountryChoice: Hashable, Sendable {
        let code: String
        let name: String
    }

    /// Rights season, e.g. `2026-27`.
    let season: String
    let services: [String: Service]
    /// ISO country code -> rights.
    let countries: [String: Country]
    /// League id -> rights that apply in every country (MLS on Apple TV).
    let everywhere: [String: Rights]
    /// Lowercased ESPN TV name -> service id.
    let espnAliases: [String: String]

    private enum CodingKeys: String, CodingKey {
        case season, services, countries, everywhere, espnAliases
    }

    /// No services or rights: where-to-watch falls back to ESPN's own listings.
    static let empty = BroadcasterCatalog(season: "", services: [:], countries: [:], everywhere: [:],
                                          espnAliases: [:])

    init(season: String, services: [String: Service], countries: [String: Country],
         everywhere: [String: Rights], espnAliases: [String: String]) {
        self.season = season
        self.services = services
        self.countries = countries
        self.everywhere = everywhere
        self.espnAliases = espnAliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        season = try container.decodeIfPresent(String.self, forKey: .season) ?? ""
        services = try container.decodeIfPresent([String: Service].self, forKey: .services) ?? [:]
        countries = try container.decodeIfPresent([String: Country].self, forKey: .countries) ?? [:]
        everywhere = try container.decodeIfPresent([String: Rights].self, forKey: .everywhere) ?? [:]
        espnAliases = try container.decodeIfPresent([String: String].self, forKey: .espnAliases) ?? [:]
    }

    // MARK: Loading

    enum LoadError: Error { case missing }

    static func decode(_ data: Data) throws -> BroadcasterCatalog {
        try JSONDecoder().decode(BroadcasterCatalog.self, from: data)
    }

    /// The `broadcasters.json` shipped in the app bundle.
    static func bundled(in bundle: Bundle = .main) throws -> BroadcasterCatalog {
        guard let url = bundle.url(forResource: "broadcasters", withExtension: "json") else {
            throw LoadError.missing
        }
        return try decode(Data(contentsOf: url))
    }

    // MARK: Lookups

    func knowsCountry(_ code: String) -> Bool {
        countries[code.uppercased()] != nil
    }

    /// Countries with rights data, sorted by name (the settings picker).
    var countryChoices: [CountryChoice] {
        countries.map { CountryChoice(code: $0.key, name: $0.value.name.isEmpty ? $0.key : $0.value.name) }
            .sorted { $0.name < $1.name }
    }

    /// The catalog entry for `id`, or a plain TV channel named after it (`service`).
    func broadcaster(id: String) -> Broadcaster {
        guard let service = services[id] else {
            return Broadcaster(id: id, name: id, url: nil, colorHex: "", kind: .tv, language: nil)
        }
        return Broadcaster(
            id: id,
            name: service.name,
            url: service.url.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            colorHex: service.color ?? "",
            kind: service.kind.flatMap(Broadcaster.Kind.init(rawValue:)) ?? .tv,
            language: service.language
        )
    }
}
