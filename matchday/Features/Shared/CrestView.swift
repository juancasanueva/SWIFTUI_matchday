//
//  CrestView.swift
//  matchday
//
//  Team crest with the colored-circle fallback (`Crest` in Panel.qml).
//  The single place crests are loaded, so a disk crest cache can replace
//  `AsyncImage` here without touching any other view.
//

import SwiftUI

struct CrestView: View {
    let team: Team
    var size: CGFloat = 20

    var body: some View {
        AsyncImage(url: team.crestURL()) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Team-colored circle with the abbreviation, shown until (or unless) the image loads.
    private var fallback: some View {
        Circle()
            .fill((Color(hex: team.colorHex) ?? Theme.dim).opacity(0.85))
            .overlay {
                Text(String(abbreviation.prefix(3)))
                    .font(.system(size: max(6, size * 0.32), weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.background)
                    .minimumScaleFactor(0.5)
            }
    }

    private var abbreviation: String {
        if !team.abbreviation.isEmpty { return team.abbreviation }
        return team.shortName.isEmpty ? "?" : team.shortName
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 12) {
        CrestView(team: PreviewData.realMadrid, size: 38)
        CrestView(team: PreviewData.leipzig, size: 30)
        CrestView(team: Team(id: "0", leagueID: "esp.1", name: "Unknown", shortName: "Unknown",
                             abbreviation: "UNK", colorHex: "#1aa0e8"), size: 30)
    }
    .padding()
    .background(Theme.background)
}
#endif
