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

    /// Before the first refresh; the tooltip is in the current app language.
    static var empty: BarState {
        BarState(showDot: false, isLive: false, liveText: nil, tooltip: Derivations.emptyTooltip, isDimmed: true)
    }
}

nonisolated extension Derivations {
    /// The bar dot lights up when a followed team plays within this window.
    static let dotLead: TimeInterval = 12 * 3600

    /// Hover text with nothing to report, in the current app language.
    static var emptyTooltip: String {
        emptyTooltip(DisplayContext(now: .now, locale: AppLocalization.shared.locale,
                                    bundle: AppLocalization.shared.bundle))
    }

    static func emptyTooltip(_ display: DisplayContext) -> String {
        display.text("Matchday — follow some teams", comment: "Menu bar tooltip while no team is followed.")
    }

    /// One-line status under the panel title, in capitals.
    static func headerSummary(
        snapshot: MatchSnapshot,
        cards: [FollowingCard],
        window: [Match],
        display: DisplayContext
    ) -> String {
        switch snapshot.status {
        case .loading:
            return display.text("Loading fixtures…").uppercased(with: display.locale)
        case .offline:
            let reason = snapshot.lastError
                ?? display.text("can't reach ESPN", comment: "Why the data is offline, after “Offline · ”.")
            return display.text("Offline · \(reason)", comment: "Panel status line without a connection. Shown in capitals.")
                .uppercased(with: display.locale)
        case .ok, .stale:
            break
        }

        var bits: [String] = []
        let liveFavorites = cards.filter { $0.live != nil }.count
        let liveCount = window.filter(\.isLive).count
        if liveFavorites > 0 {
            bits.append(display.text("\(liveFavorites) live",
                                     comment: "Panel status: how many followed teams are playing now. Shown in capitals."))
        } else if liveCount > 0 {
            bits.append(display.text("\(liveCount) live now",
                                     comment: "Panel status: how many matches are being played now. Shown in capitals."))
        }
        if let next = cards.compactMap(\.next).min(by: { $0.kickoff < $1.kickoff }) {
            let when = "\(display.dayLabel(next.kickoff)) \(display.timeLabel(next.kickoff))"
            bits.append(display.text("Next \(next.home.team.abbreviation) v \(next.away.team.abbreviation) · \(when)",
                                     comment: "Panel status: the next followed match (home v away team codes), then day and time. v = versus. Shown in capitals."))
        }
        if bits.isEmpty {
            bits.append(display.text("\(window.count) matches this week",
                                     comment: "Panel status: number of matches in the polled window. Shown in capitals."))
        }
        if snapshot.status == .stale {
            bits.append(display.text("Stale", comment: "Panel status: the data is out of date. Shown in capitals."))
        }
        return bits.joined(separator: "  ·  ").uppercased(with: display.locale)
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
                let line = display.text("\(next.home.team.shortName) v \(next.away.team.shortName) — \(when)",
                                        comment: "Menu bar tooltip line: home v away team, then day and time. v = versus.")
                lines.append(line + (channels.isEmpty ? "" : "  ·  \(channels)"))
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
            tooltip: lines.isEmpty ? emptyTooltip(display) : lines.joined(separator: "\n"),
            isDimmed: settings.favorites.isEmpty
        )
    }
}
