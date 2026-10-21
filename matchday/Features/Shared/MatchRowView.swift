//
//  MatchRowView.swift
//  matchday
//
//  One fixture or result in a list (`MatchRow` in Panel.qml): status, matchup,
//  league dot, then channels before kickoff or scorers afterwards. Clicking
//  opens the match on ESPN.
//

import SwiftUI

struct MatchRowView: View {
    let row: MatchRowItem
    var highlightedTeamIDs: Set<String> = []

    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    private static let statusWidth: CGFloat = 62

    var body: some View {
        Button {
            openURL(row.match.espnURL)
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    status
                    MatchupView(match: row.match, highlightedTeamIDs: highlightedTeamIDs)
                    if row.showLeague, let league = League.with(id: row.match.leagueID) {
                        LeagueDot(league: league)
                    }
                }
                detail
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(background, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay(alignment: .leading) {
                if row.isFollowed {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help("Open on ESPN")
        .accessibilityHint("Opens the match on ESPN")
    }

    private var status: some View {
        Text((row.isLive ? "● " : "") + row.status)
            .font(Theme.font(.caption, weight: row.isLive ? .bold : .regular))
            .foregroundStyle(row.isLive ? Theme.urgent : row.match.state == .post ? Theme.dim : Theme.foreground)
            .lineLimit(1)
            .frame(width: Self.statusWidth, alignment: .leading)
            .pulsing(row.isLive, minimum: 0.6)
    }

    @ViewBuilder
    private var detail: some View {
        if !row.channels.isEmpty {
            Label(row.channels.joined(separator: " · "), systemImage: "tv")
                .accessibilityLabel("On \(row.channels.joined(separator: ", "))")
                .modifier(DetailLine(leading: Self.statusWidth))
        } else if let scorers = row.scorers {
            Text(scorers)
                .accessibilityLabel("Goals: \(scorers)")
                .modifier(DetailLine(leading: Self.statusWidth))
        }
    }

    private var background: Color {
        if row.isFollowed { return Theme.accent.opacity(isHovered ? 0.20 : 0.11) }
        return isHovered ? Theme.hover : .clear
    }
}

/// Caption line centered under the matchup.
private struct DetailLine: ViewModifier {
    let leading: CGFloat

    func body(content: Content) -> some View {
        content
            .font(Theme.font(.caption))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .padding(.leading, leading)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 2) {
        ForEach(PreviewData.rows) { MatchRowView(row: $0, highlightedTeamIDs: PreviewData.followedIDs) }
    }
    .padding()
    .frame(width: 440)
    .background(Theme.background)
}
#endif
