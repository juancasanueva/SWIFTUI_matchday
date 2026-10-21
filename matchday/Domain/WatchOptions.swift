//
//  WatchOptions.swift
//  matchday
//

import Foundation

/// A TV channel or streaming service showing a match.
nonisolated struct Broadcaster: Hashable, Sendable, Identifiable {
    nonisolated enum Kind: String, Hashable, Sendable {
        case tv, stream, free
    }

    /// Catalog id (`peacock`), or the raw ESPN name for channels the catalog does not know.
    let id: String
    let name: String
    let url: URL?
    /// `#rrggbb`, or empty.
    let colorHex: String
    let kind: Kind
    /// Broadcast language when it is not English, e.g. `es`.
    let language: String?
}

/// Where one match can be watched (`where_to_watch` in the original plugin).
nonisolated struct WatchOptions: Hashable, Sendable {
    nonisolated enum Source: String, Hashable, Sendable {
        /// ESPN's per-match US listing.
        case espn
        /// The country's league rights holders.
        case rights
    }

    let source: Source
    /// `false` when the rights entry could not be confirmed for this season.
    let verified: Bool
    let services: [Broadcaster]

    static let none = WatchOptions(source: .rights, verified: true, services: [])

    /// Confidence label next to the watch pills.
    var label: String {
        if source == .espn { return "✓ confirmed for this match" }
        return verified ? "league rights · channel TBA" : "league rights · unconfirmed"
    }

    /// The first few service names, e.g. for a row or notification.
    func names(limit: Int) -> [String] {
        services.prefix(limit).map(\.name)
    }
}
