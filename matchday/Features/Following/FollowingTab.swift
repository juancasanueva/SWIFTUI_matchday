//
//  FollowingTab.swift
//  matchday
//
//  The Following tab: a card per followed team, then other live games.
//

import SwiftUI

/// Container: reads the store.
struct FollowingTab: View {
    @Environment(MatchdayStore.self) private var store
    let onChooseTeams: () -> Void

    var body: some View {
        FollowingList(
            cards: store.following,
            liveElsewhere: store.liveElsewhereRows,
            hasFavorites: !store.settings.favorites.isEmpty,
            onChooseTeams: onChooseTeams
        )
    }
}

struct FollowingList: View {
    let cards: [FollowingCard]
    let liveElsewhere: [MatchRowItem]
    let hasFavorites: Bool
    let onChooseTeams: () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if !hasFavorites {
                FollowingEmptyView(onChooseTeams: onChooseTeams)
            }
            ForEach(cards) { FollowingCardView(card: $0) }
            if hasFavorites && !liveElsewhere.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "LIVE ELSEWHERE", color: Theme.urgent)
                        .padding(.top, 4)
                    ForEach(liveElsewhere) { MatchRowView(row: $0) }
                }
            }
        }
    }
}

struct FollowingEmptyView: View {
    let onChooseTeams: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sportscourt")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Follow your teams")
                .font(Theme.font(.heading, weight: .bold))
            // One literal, so the whole sentence is a single catalog key.
            Text("Pick the clubs and national teams you care about. Matchday tracks their games, tells you which channel has them where you are, and pings you at kickoff.")
                .font(Theme.font(.body))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onChooseTeams) {
                Label("Choose teams", systemImage: "star")
                    .font(Theme.font(.body, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Theme.fill, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.faint, lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview("Cards") {
    ScrollView {
        FollowingList(cards: PreviewData.cards, liveElsewhere: PreviewData.liveElsewhereRows,
                      hasFavorites: true, onChooseTeams: {})
            .padding(16)
    }
    .frame(width: Theme.panelWidth, height: Theme.panelHeight)
    .background(Theme.background)
}

#Preview("Empty") {
    FollowingList(cards: [], liveElsewhere: [], hasFavorites: false, onChooseTeams: {})
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
#endif
