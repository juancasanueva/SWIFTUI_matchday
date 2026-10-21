//
//  WhereToWatch.swift
//  matchday
//
//  Port of the original plugin's `where_to_watch`.
//

import Foundation

nonisolated struct WhereToWatch: Sendable {
    let catalog: BroadcasterCatalog

    /// Where `match` can be watched in `country`.
    ///
    /// In the US, ESPN's per-match TV names win (confirmed). Otherwise the
    /// country's league rights apply, falling back to rights that hold
    /// everywhere. With `spanish` off, Spanish-language services are dropped
    /// unless nothing else is left.
    func options(for match: Match, country: String?, spanish: Bool) -> WatchOptions {
        let code = country?.uppercased()
        var services: [Broadcaster] = []
        var source = WatchOptions.Source.rights
        var verified = true

        if code == "US", !match.tvNames.isEmpty {
            source = .espn
            services = match.tvNames.map { name in
                let alias = catalog.espnAliases[name.trimmingCharacters(in: .whitespaces).lowercased()]
                return alias.map(catalog.broadcaster(id:))
                    ?? Broadcaster(id: name, name: name, url: nil, colorHex: "", kind: .tv, language: nil)
            }
        } else if let rights = code.flatMap({ catalog.countries[$0]?.leagues[match.leagueID] })
                    ?? catalog.everywhere[match.leagueID] {
            verified = rights.verified
            // National-team rights often follow who is playing: England on ITV,
            // Scotland on BBC, everyone else on the league-wide holder.
            let picked = [match.home, match.away].flatMap { rights.teams[$0.team.abbreviation] ?? [] }
            services = (picked.isEmpty ? rights.services : picked).map(catalog.broadcaster(id:))
        }

        if !spanish {
            let kept = services.filter { $0.language != "es" }
            if !kept.isEmpty { services = kept }
        }
        var seen: Set<String> = []
        services = services.filter { seen.insert($0.id).inserted }
        return WatchOptions(source: source, verified: verified, services: services)
    }

    /// Footnote under the watch pills (`WatchFootnote`).
    func footnote(countryCode: String?, fallbackName: String?) -> String {
        let season = catalog.season
        if countryCode?.uppercased() == "US" {
            return "Channels marked per match come from ESPN's US listings; the rest show the \(season) league rights holders until the channel is posted."
        }
        let name = countryCode.flatMap { catalog.countries[$0.uppercased()]?.name }.flatMap { $0.isEmpty ? nil : $0 }
            ?? fallbackName ?? "your country"
        return "Where to watch shows \(season) rights holders for \(name)."
    }
}
