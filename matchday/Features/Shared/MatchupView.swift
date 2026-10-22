//
//  MatchupView.swift
//  matchday
//
//  "Home [crest] vs|score [crest] Away" (`Matchup` in Panel.qml), large on
//  the Following cards and compact in match rows.
//

import SwiftUI

struct MatchupView: View {
    let match: Match
    var isLarge = false
    /// Followed team ids; their names are bold.
    var highlightedTeamIDs: Set<String> = []

    private var showsScore: Bool { match.state != .pre }
    private var crestSize: CGFloat { isLarge ? 30 : 18 }

    var body: some View {
        HStack(spacing: isLarge ? 8 : 6) {
            name(match.home, dimmed: match.state == .post && match.away.winner)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            CrestView(team: match.home.team, size: crestSize)
            center
                .frame(width: isLarge ? 84 : 46)
            CrestView(team: match.away.team, size: crestSize)
            name(match.away, dimmed: match.state == .post && match.home.winner)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func name(_ side: MatchSide, dimmed: Bool) -> some View {
        let bold = isLarge || side.winner || highlightedTeamIDs.contains(side.team.id)
        return Text(side.team.shortName)
            .font(Theme.font(isLarge ? .title : .body, weight: bold ? .bold : .regular))
            .foregroundStyle(dimmed ? Theme.dim : Theme.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var center: some View {
        if showsScore {
            Text(isLarge ? "\(match.home.displayScore) – \(match.away.displayScore)" : match.scoreText)
                .font(Theme.font(isLarge ? .display : .title, weight: .bold))
                .foregroundStyle(match.isLive ? Theme.urgent : Theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text("vs")
                .font(Theme.font(isLarge ? .title : .caption))
                .foregroundStyle(Theme.dim)
        }
    }

    private var accessibilityText: Text {
        let home = match.home.team.shortName, away = match.away.team.shortName
        return showsScore
            ? Text(verbatim: "\(home) \(match.home.displayScore), \(away) \(match.away.displayScore)")
            : Text("\(home) versus \(away)", comment: "VoiceOver: an upcoming match, home team versus away team.")
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        MatchupView(match: PreviewData.upcoming, isLarge: true)
        MatchupView(match: PreviewData.live, isLarge: true)
        MatchupView(match: PreviewData.finished, highlightedTeamIDs: [PreviewData.barcelona.id])
    }
    .padding()
    .frame(width: 440)
    .background(Theme.background)
}
#endif
