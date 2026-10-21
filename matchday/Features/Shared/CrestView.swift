//
//  CrestView.swift
//  matchday
//
//  Team crest with the colored-circle fallback (`Crest` in Panel.qml).
//  The single place crests are loaded: through `CrestLoader`, from the disk
//  crest cache, using the dark variant on dark backgrounds.
//

import SwiftUI

struct CrestView: View {
    let team: Team
    var size: CGFloat = 20
    var loader: CrestLoader = .shared

    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            if let image = image ?? loader.loadedImage(for: team, dark: isDark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: "\(team.id)-\(isDark)") {
            image = loader.loadedImage(for: team, dark: isDark)
            if image == nil {
                image = await loader.image(for: team, dark: isDark)
            }
        }
    }

    /// Team-colored circle with the abbreviation, shown until (or unless) the image loads.
    private var fallback: some View {
        Circle()
            .fill(Theme.readable(hex: team.colorHex, fallback: .accent).opacity(0.85))
            .overlay {
                Text(String(abbreviation.prefix(3)))
                    .font(.system(size: max(6, size * 0.32), weight: .bold))
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
