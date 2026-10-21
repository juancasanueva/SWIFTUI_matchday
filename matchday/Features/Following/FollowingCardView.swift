//
//  FollowingCardView.swift
//  matchday
//
//  A followed team's card (`FavoriteCard` in Panel.qml): header with crest,
//  standing and form; the live or next match with countdown, venue and where
//  to watch; and the last result plus the fixture after next.
//

import SwiftUI

struct FollowingCardView: View {
    let card: FollowingCard

    @Environment(\.openURL) private var openURL

    private var isLive: Bool { card.live != nil }
    private var tint: Color { Color(hex: card.colorHex) ?? Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let match = card.featured {
                kicker
                Button {
                    openURL(match.espnURL)
                } label: {
                    MatchupView(match: match, isLarge: true)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open on ESPN")
                .accessibilityHint("Opens the match on ESPN")
                if !card.liveEvents.isEmpty {
                    LiveEventsView(events: card.liveEvents, homeTeamID: match.home.team.id)
                }
                if let venue = card.venue {
                    Label(venue, systemImage: "mappin.and.ellipse")
                        .font(Theme.font(.small))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                if let watch = card.watch, !watch.services.isEmpty {
                    WhereToWatchSection(watch: watch)
                }
            } else {
                Text("No upcoming fixtures scheduled")
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
            }
            if card.last != nil || card.thenText != nil {
                Rectangle()
                    .fill(Theme.faint)
                    .frame(height: 1)
                footer
            }
        }
        .padding(14)
        .padding(.leading, 3)
        .background { background }
        .clipShape(.rect(cornerRadius: Theme.cornerRadius))
        .overlay { border }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            CrestView(team: card.team, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.favorite.name)
                    .font(Theme.font(.heading, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let league = League.with(id: card.favorite.leagueID) {
                        LeagueTag(league: league)
                    }
                    if let standing = card.standing {
                        Text(standing.text)
                            .font(Theme.font(.small))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            FormBoxes(form: card.form)
        }
    }

    private var kicker: some View {
        HStack(alignment: .firstTextBaseline) {
            if let kicker = card.kicker {
                Text(isLive ? "● " + kicker : kicker)
                    .font(Theme.font(.caption, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(isLive ? Theme.urgent : Theme.dim)
                    .pulsing(isLive, minimum: 0.55)
            }
            Spacer()
            if let countdown = card.countdown {
                Text(countdown)
                    .font(Theme.font(.caption, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let last = card.last {
                Button {
                    openURL(last.espnURL)
                } label: {
                    HStack(spacing: 6) {
                        Text("LAST")
                            .tracking(1)
                            .foregroundStyle(Theme.dim)
                        if let result = card.lastResult {
                            FormBox(result: result, size: 14)
                            Text(result.summary)
                                .foregroundStyle(Theme.foreground)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open on ESPN")
            }
            Spacer(minLength: 8)
            if let thenText = card.thenText {
                Text(thenText)
                    .foregroundStyle(Theme.dim)
            }
        }
        .font(Theme.font(.small))
        .lineLimit(1)
    }

    // MARK: Chrome

    private var background: some View {
        ZStack(alignment: .topLeading) {
            Theme.fill
            // Team-color wash across the top of the card.
            LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 64)
            tint.frame(width: 3)
        }
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        if isLive {
            shape.strokeBorder(Theme.urgent.opacity(0.8), lineWidth: 1)
                .pulsing(true, minimum: 0.5)
        } else {
            shape.strokeBorder(Theme.faint, lineWidth: 1)
        }
    }
}

/// "WHERE TO WATCH" with the confidence label and the service pills.
struct WhereToWatchSection: View {
    let watch: WatchOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "WHERE TO WATCH") {
                Text(watch.label)
                    .font(Theme.font(.caption))
                    .foregroundStyle(watch.source == .espn ? Theme.win : Theme.dim)
                    .lineLimit(1)
            }
            WatchPills(services: watch.services)
        }
    }
}

/// Goals and red cards of a live match: home on the left, away on the right.
struct LiveEventsView: View {
    let events: [KeyEvent]
    let homeTeamID: String

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                let isHome = event.side == .home || (event.side == .unknown && event.teamID == homeTeamID)
                HStack(spacing: 4) {
                    Image(systemName: event.kind == .redCard ? "rectangle.portrait.fill" : "soccerball")
                        .imageScale(.small)
                        .accessibilityLabel(event.kind == .redCard ? "Red card" : "Goal")
                    Text(event.label)
                }
                .font(Theme.font(.small))
                .foregroundStyle(event.kind == .redCard ? Theme.urgent : Theme.dim)
                .frame(maxWidth: .infinity, alignment: isHome ? .leading : .trailing)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension FollowingCard {
    /// The followed team with its color, for the crest.
    var team: Team {
        Team(id: favorite.teamID, leagueID: favorite.leagueID, name: favorite.name,
             shortName: favorite.shortName, abbreviation: favorite.abbreviation, colorHex: colorHex)
    }
}

#if DEBUG
#Preview("Next") {
    FollowingCardView(card: PreviewData.realMadridCard)
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}

#Preview("Live") {
    FollowingCardView(card: PreviewData.liveCard)
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
#endif
