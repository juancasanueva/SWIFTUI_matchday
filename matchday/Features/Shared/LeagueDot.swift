//
//  LeagueDot.swift
//  matchday
//
//  League color dot, alone or with the league's short name (`LeagueTag`).
//

import SwiftUI

struct LeagueDot: View {
    let league: League
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(league.color)
            .frame(width: size, height: size)
            .help(league.name)
            .accessibilityLabel(league.name)
    }
}

/// "● LaLiga".
struct LeagueTag: View {
    let league: League

    var body: some View {
        HStack(spacing: 4) {
            LeagueDot(league: league, size: 6)
                .accessibilityHidden(true)
            Text(league.short)
                .font(Theme.font(.small))
                .foregroundStyle(Theme.dim)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ForEach(League.all) { LeagueTag(league: $0) }
    }
    .padding()
    .background(Theme.background)
}
