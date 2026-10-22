//
//  FollowingDerivation.swift
//  matchday
//
//  The Following tab: one card per followed team (`favorites` in the original
//  `Engine.snapshot` plus the `FavoriteCard` texts in Panel.qml).
//

import Foundation

/// One recent result from a followed team's point of view.
nonisolated struct FormResult: Hashable, Sendable {
    nonisolated enum Outcome: String, Hashable, Sendable {
        case win = "W", draw = "D", loss = "L"
    }

    let matchID: String
    let outcome: Outcome
    /// Our goals first, e.g. "2–1".
    let score: String
    /// Opponent short name.
    let opponent: String
    let isHome: Bool

    /// "2–1 vs Getafe" at home, "1–1 at Valencia" away, in the app language.
    func summary(locale: Locale = AppLocalization.shared.locale) -> String {
        let bundle = locale.appBundle
        return isHome
            ? String(appLocalized: "\(score) vs \(opponent)", bundle: bundle, locale: locale,
                     comment: "A result at home: the score, then the opponent. vs = versus.")
            : String(appLocalized: "\(score) at \(opponent)", bundle: bundle, locale: locale,
                     comment: "A result away: the score, then the opponent the match was played at.")
    }
}

/// A followed team's league position.
nonisolated struct StandingLine: Hashable, Sendable {
    let rank: Int
    /// Group or conference name; empty for single tables.
    let group: String
    let points: Int
    let played: Int

    /// "9th · 6 pts · 2 played", "1st in Eastern · 9 pts · 3 played", in the app language.
    func text(locale: Locale = AppLocalization.shared.locale) -> String {
        let display = DisplayContext(now: .now, locale: locale)
        let groupName = group.hasSuffix(" Conference") ? String(group.dropLast(" Conference".count)) : group
        let rank = display.ordinal(rank)
        let position = groupName.isEmpty ? rank
            : display.text("\(rank) in \(groupName)",
                           comment: "League position within a group: the ordinal rank, then the group name.")
        return display.text("\(position) · \(points) pts · \(played) played",
                            comment: "A team's standing: position, points (pts), matches played.")
    }
}

nonisolated struct FollowingCard: Identifiable, Hashable, Sendable {
    let favorite: FavoriteTeam
    /// Team color from the league's team list, `#rrggbb` or empty.
    let colorHex: String
    let live: Match?
    let next: Match?
    /// The fixture after `next`.
    let after: Match?
    let last: Match?
    /// Up to five recent results, oldest first.
    let form: [FormResult]
    let standing: StandingLine?
    /// "LIVE 67'" or "NEXT · TODAY · 9:00 PM", in capitals.
    let kicker: String?
    /// "in 3h 53m" before kickoff; `nil` while live.
    let countdown: String?
    /// "Stadium, City" before kickoff.
    let venue: String?
    /// Where the featured match can be watched.
    let watch: WatchOptions?
    /// Goals and red cards of the live match.
    let liveEvents: [KeyEvent]
    /// "THEN at Atlético · Sun Oct 25".
    let thenText: String?

    var id: String { favorite.key }
    /// The match the card is about: live, else next.
    var featured: Match? { live ?? next }
    var lastResult: FormResult? { form.last }
}

nonisolated enum Derivations {
    /// Upcoming fixtures stay "next" this long after their kickoff time.
    static let staleFixtureGrace: TimeInterval = 3 * 3600
    static let formLength = 5

    static func isFollowed(_ match: Match, settings: AppSettings) -> Bool {
        settings.isFollowing(leagueID: match.leagueID, teamID: match.home.team.id)
            || settings.isFollowing(leagueID: match.leagueID, teamID: match.away.team.id)
    }

    /// Cards for every followed team: live first, then by kickoff, teams with
    /// nothing scheduled last; ties keep the follow order.
    static func followingCards(
        snapshot: MatchSnapshot,
        settings: AppSettings,
        display: DisplayContext,
        watch: (Match) -> WatchOptions
    ) -> [FollowingCard] {
        var standings: [String: StandingLine] = [:]
        for (league, groups) in snapshot.tables {
            for group in groups {
                for entry in group.entries {
                    standings["\(league):\(entry.team.id)"] = StandingLine(
                        rank: entry.rank, group: group.name, points: entry.points, played: entry.played)
                }
            }
        }

        let cards = settings.favorites.map { favorite in
            card(for: favorite, snapshot: snapshot, standing: standings[favorite.key], display: display, watch: watch)
        }
        return cards.enumerated().sorted { lhs, rhs in
            let left = sortKey(lhs.element), right = sortKey(rhs.element)
            if left.tier != right.tier { return left.tier < right.tier }
            if left.kickoff != right.kickoff { return left.kickoff < right.kickoff }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func sortKey(_ card: FollowingCard) -> (tier: Int, kickoff: Date) {
        if let live = card.live { return (0, live.kickoff) }
        if let next = card.next { return (1, next.kickoff) }
        return (2, .distantPast)
    }

    private static func card(
        for favorite: FavoriteTeam,
        snapshot: MatchSnapshot,
        standing: StandingLine?,
        display: DisplayContext,
        watch: (Match) -> WatchOptions
    ) -> FollowingCard {
        let mine = snapshot.matches.filter { $0.leagueID == favorite.leagueID && $0.involves(teamID: favorite.teamID) }
        let live = mine.first(where: \.isLive)
        let upcoming = mine.filter {
            $0.state == .pre && $0.kickoff > display.now.addingTimeInterval(-staleFixtureGrace) && !$0.isPostponed
        }
        let played = mine.filter(\.isFinal)
        let next = upcoming.first
        let after = upcoming.dropFirst().first
        let featured = live ?? next

        var kicker: String?
        if let live {
            kicker = display.text("LIVE \(display.minute(live))",
                                  comment: "Card kicker of a live match: the minute or status follows. Keep it in capitals.")
        } else if let next {
            let day = display.dayLabel(next.kickoff).uppercased(with: display.locale)
            kicker = display.text("NEXT · \(day) · \(display.timeLabel(next.kickoff))",
                                  comment: "Card kicker of the next match: day (in capitals), then kickoff time. Keep NEXT in capitals.")
        }

        var venue: String?
        if live == nil, let next, !next.venue.isEmpty {
            venue = next.city.isEmpty ? next.venue : "\(next.venue), \(next.city)"
        }

        let thenText = after.map { after in
            let isHome = after.home.team.id == favorite.teamID
            let opponent = isHome ? after.away.team : after.home.team
            let day = display.dayLabel(after.kickoff)
            return isHome
                ? display.text("THEN vs \(opponent.shortName) · \(day)",
                               comment: "The fixture after the next one, at home: opponent, then day. Keep THEN in capitals.")
                : display.text("THEN at \(opponent.shortName) · \(day)",
                               comment: "The fixture after the next one, away: opponent, then day. Keep THEN in capitals.")
        }

        let colorHex = snapshot.teams[favorite.leagueID]?.first { $0.id == favorite.teamID }?.colorHex ?? ""
        return FollowingCard(
            favorite: favorite,
            colorHex: colorHex,
            live: live,
            next: next,
            after: after,
            last: played.last,
            form: played.suffix(formLength).compactMap { formResult($0, teamID: favorite.teamID) },
            standing: standing,
            kicker: kicker,
            countdown: live == nil ? next.map { display.countdown(to: $0.kickoff) } : nil,
            venue: venue,
            watch: featured.map(watch),
            liveEvents: live?.keyEvents ?? [],
            thenText: thenText
        )
    }

    /// W/D/L from `teamID`'s side; results without numeric scores are skipped.
    static func formResult(_ match: Match, teamID: String) -> FormResult? {
        let isHome = match.home.team.id == teamID
        let us = isHome ? match.home : match.away
        let them = isHome ? match.away : match.home
        guard let ours = Int(us.displayScore), let theirs = Int(them.displayScore) else { return nil }
        let outcome: FormResult.Outcome = ours > theirs ? .win : ours < theirs ? .loss : .draw
        return FormResult(matchID: match.id, outcome: outcome, score: "\(ours)–\(theirs)",
                          opponent: them.team.shortName, isHome: isHome)
    }

    // MARK: Window

    /// Matches of enabled leagues inside the polled day window (`events` in the snapshot).
    static func windowMatches(snapshot: MatchSnapshot, settings: AppSettings, display: DisplayContext) -> [Match] {
        let calendar = display.calendar
        guard let start = calendar.date(byAdding: .day, value: -RefreshPolicy.daysBack, to: display.today),
              let end = calendar.date(byAdding: .day, value: RefreshPolicy.daysAhead + 1, to: display.today)
        else { return [] }
        let leagues = Set(settings.leagues)
        return snapshot.matches.filter { $0.kickoff >= start && $0.kickoff < end && leagues.contains($0.leagueID) }
    }

    /// Live matches not involving a followed team ("LIVE ELSEWHERE").
    static func liveElsewhere(snapshot: MatchSnapshot, settings: AppSettings, display: DisplayContext) -> [Match] {
        windowMatches(snapshot: snapshot, settings: settings, display: display)
            .filter { $0.isLive && !isFollowed($0, settings: settings) }
    }
}
