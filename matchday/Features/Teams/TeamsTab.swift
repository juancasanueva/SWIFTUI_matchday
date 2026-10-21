//
//  TeamsTab.swift
//  matchday
//
//  The Teams tab: league chips, a crest grid to follow or unfollow teams,
//  then the settings (`teamsTab` in Panel.qml).
//

import SwiftUI

/// Container: owns the league selection and reads the store.
struct TeamsTab: View {
    @Environment(MatchdayStore.self) private var store
    @State private var selection: String?

    var body: some View {
        let settings = store.settings
        let league = Derivations.pickerLeague(selected: selection, settings: settings, preferFollowed: false)
        VStack(alignment: .leading, spacing: 10) {
            TeamPicker(
                selection: Binding(get: { league }, set: { selection = $0 }),
                leagues: settings.leagues.compactMap(League.with(id:)),
                isNational: League.with(id: league)?.isNational ?? false,
                teams: store.snapshot.teams[league] ?? [],
                followedIDs: Set(settings.favorites.filter { $0.leagueID == league }.map(\.teamID)),
                onToggleFollow: store.toggleFollow
            )
            Rectangle()
                .fill(Theme.faint)
                .frame(height: 1)
                .padding(.vertical, 4)
            SettingsSection()
        }
    }
}

struct TeamPicker: View {
    @Binding var selection: String
    let leagues: [League]
    /// National-team competition: "Loading teams…" instead of "Loading clubs…".
    let isNational: Bool
    /// The league's teams, alphabetical; empty until the team list loads.
    let teams: [Team]
    let followedIDs: Set<String>
    let onToggleFollow: (Team) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LeaguePicker(selection: $selection, leagues: leagues)
            if teams.isEmpty {
                Text(isNational ? "Loading teams…" : "Loading clubs…")
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(teams) { team in
                        TeamTile(team: team, isFollowed: followedIDs.contains(team.id)) {
                            onToggleFollow(team)
                        }
                    }
                }
            }
        }
    }
}

/// Crest and short name; followed teams get the accent border, ★ and bold name.
struct TeamTile: View {
    let team: Team
    let isFollowed: Bool
    let onToggle: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 0) {
                CrestView(team: team, size: 32)
                    .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
                    .animation(.easeOut(duration: 0.14), value: isHovered)
                    .padding(.top, 10)
                Spacer(minLength: 4)
                Text(team.shortName)
                    .font(Theme.font(.caption, weight: isFollowed ? .bold : .regular))
                    .foregroundStyle(isFollowed ? Theme.foreground : Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(background, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(isFollowed ? Theme.accent : Theme.faint, lineWidth: isFollowed ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isFollowed {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                        .padding(6)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerStyle(.link)
        .help(team.name)
        .accessibilityLabel(team.name)
        .accessibilityValue(isFollowed ? "Following" : "Not following")
        .accessibilityHint(isFollowed ? "Unfollow" : "Follow")
        .accessibilityAddTraits(isFollowed ? .isSelected : [])
    }

    private var background: Color {
        if isFollowed { return Theme.accent.opacity(0.16) }
        return Theme.foreground.opacity(isHovered ? 0.08 : 0.03)
    }
}

#if DEBUG
#Preview("Grid") {
    @Previewable @State var league = League.laLiga.id
    TeamPicker(selection: $league, leagues: League.all, isNational: false,
               teams: PreviewData.snapshot.teams["esp.1", default: []].sorted { $0.shortName < $1.shortName },
               followedIDs: PreviewData.followedIDs, onToggleFollow: { _ in })
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}

#Preview("Loading") {
    @Previewable @State var league = League.nationsLeague.id
    TeamPicker(selection: $league, leagues: League.all, isNational: true, teams: [], followedIDs: [],
               onToggleFollow: { _ in })
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
#endif
