//
//  StatusDerivation.swift
//  matchday
//
//  Panel header summary and menu bar state (`summary`, `barLiveText`,
//  `tooltip`, `todayFav` in Panel.qml).
//

import Foundation

nonisolated struct BarState: Hashable, Sendable {
    /// A followed team is live or plays within `Derivations.dotLead`.
    let showDot: Bool
    /// A followed team is live (red, pulsing dot).
    let isLive: Bool
    /// "BAR 2–1 GET  67'" next to the icon, when enabled.
    let liveText: String?
    /// Hover text, one line per followed team with a live or next match.
    let tooltip: String
    /// Nothing followed yet.
    let isDimmed: Bool

    static let empty = BarState(showDot: false, isLive: false, liveText: nil,
                                tooltip: Derivations.emptyTooltip, isDimmed: true)
}

nonisolated extension Derivations {
    /// The bar dot lights up when a followed team plays within this window.
    static let dotLead: TimeInterval = 12 * 3600
    static let emptyTooltip = "Matchday — follow some teams"

    /// One-line status under the panel title.
    static func headerSummary(
        snapshot: MatchSnapshot,
        cards: [FollowingCard],
        window: [Match],
        display: DisplayContext
    ) -> String {
        switch snapshot.status {
        case .loading:
            return "LOADING FIXTURES…"
        case .offline:
            return "OFFLINE · " + (snapshot.lastError ?? "can't reach ESPN").uppercased(with: display.locale)
        case .ok, .stale:
            break
        }

        var bits: [String] = []
        let liveFavorites = cards.filter { $0.live != nil }.count
        let liveCount = window.filter(\.isLive).count
        if liveFavorites > 0 {
            bits.append("\(liveFavorites) LIVE")
        } else if liveCount > 0 {
            bits.append("\(liveCount) LIVE NOW")
        }
        if let next = cards.compactMap(\.next).min(by: { $0.kickoff < $1.kickoff }) {
            let when = "\(display.dayLabel(next.kickoff)) \(display.timeLabel(next.kickoff))"
            bits.append("NEXT \(next.home.team.abbreviation) v \(next.away.team.abbreviation) · \(when)"
                .uppercased(with: display.locale))
        }
        if bits.isEmpty {
            bits.append("\(window.count) MATCHES THIS WEEK")
        }
        if snapshot.status == .stale {
            bits.append("STALE")
        }
        return bits.joined(separator: "  ·  ")
    }

    /// Menu bar icon state.
    static func barState(cards: [FollowingCard], settings: AppSettings, display: DisplayContext) -> BarState {
        let liveMatch = cards.lazy.compactMap(\.live).first
        let soon = cards.compactMap(\.next).contains { $0.kickoff.timeIntervalSince(display.now) < dotLead }

        var lines: [String] = []
        for card in cards {
            if let live = card.live {
                lines.append("● \(live.home.team.shortName) \(live.scoreText) \(live.away.team.shortName)  \(display.minute(live))")
            } else if let next = card.next {
                let channels = (card.watch?.names(limit: 2) ?? []).joined(separator: ", ")
                let when = "\(display.dayLabel(next.kickoff)) \(display.timeLabel(next.kickoff))"
                lines.append("\(next.home.team.shortName) v \(next.away.team.shortName) — \(when)"
                             + (channels.isEmpty ? "" : "  ·  \(channels)"))
            }
        }

        var liveText: String?
        if let liveMatch, settings.barScore {
            liveText = "\(liveMatch.home.team.abbreviation) \(liveMatch.scoreText) "
                + "\(liveMatch.away.team.abbreviation)  \(display.minute(liveMatch))"
        }
        return BarState(
            showDot: liveMatch != nil || soon,
            isLive: liveMatch != nil,
            liveText: liveText,
            tooltip: lines.isEmpty ? emptyTooltip : lines.joined(separator: "\n"),
            isDimmed: settings.favorites.isEmpty
        )
    }
}
