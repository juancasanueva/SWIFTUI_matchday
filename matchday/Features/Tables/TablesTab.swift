//
//  TablesTab.swift
//  matchday
//
//  The Tables tab: league chips, the standings (grouped for MLS, the UCL
//  league phase and the Nations League), the zone legend, and click to
//  follow (`tablesTab` in Panel.qml).
//

import SwiftUI

/// Container: reads the store; the panel owns the league selection (h/l cycle it).
struct TablesTab: View {
    @Environment(MatchdayStore.self) private var store
    @Binding var selection: String?

    var body: some View {
        let settings = store.settings
        let league = Derivations.pickerLeague(selected: selection, settings: settings, preferFollowed: true)
        let groups = store.tableGroups(league: league)
        StandingsList(
            selection: Binding(get: { league }, set: { selection = $0 }),
            leagues: settings.leagues.compactMap(League.with(id:)),
            isNational: League.with(id: league)?.isNational ?? false,
            groups: groups,
            legend: Derivations.zoneLegend(groups),
            emptyMessage: StandingsList.emptyMessage(isLoaded: store.snapshot.tables[league] != nil,
                                                     status: store.snapshot.status, locale: store.locale),
            onToggleFollow: store.toggleFollow
        )
    }
}

struct StandingsList: View {
    @Binding var selection: String
    let leagues: [League]
    /// National-team competition: "TEAM" instead of "CLUB".
    let isNational: Bool
    let groups: [TableGroupItem]
    let legend: [StandingZone]
    let emptyMessage: String
    let onToggleFollow: (Team) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LeaguePicker(selection: $selection, leagues: leagues)
            if groups.isEmpty {
                Text(emptyMessage)
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        StandingGroupView(group: group, isNational: isNational, onToggleFollow: onToggleFollow)
                    }
                }
                if !legend.isEmpty {
                    ZoneLegend(zones: legend)
                        .padding(.top, 6)
                }
                Text(isNational ? "Click a team to follow or unfollow it." : "Click a club to follow or unfollow it.")
                    .font(Theme.font(.caption))
                    .italic()
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 2)
            }
        }
    }

    /// Text shown while a league has no table, in the app language of `locale`.
    static func emptyMessage(isLoaded: Bool, status: DataStatus,
                             locale: Locale = AppLocalization.shared.locale) -> String {
        let display = DisplayContext(now: .now, locale: locale)
        if isLoaded { return display.text("No table for this league yet.", comment: "Tables tab without standings.") }
        return status == .offline
            ? display.text("Table unavailable — check your connection.", comment: "Tables tab while offline.")
            : display.text("Loading table…", comment: "Tables tab while the standings load.")
    }
}

/// Column metrics shared by the header and the rows.
private enum StandingsMetrics {
    static let rankWidth: CGFloat = 18
    static let numberWidth: CGFloat = 26
    /// PTS is a little wider than the other stats.
    static let pointsWidth: CGFloat = 32
    static let crestSize: CGFloat = 18
    static let rowHeight: CGFloat = 26
}

/// One table: the group name (when grouped), the column header, and the rows.
struct StandingGroupView: View {
    let group: TableGroupItem
    let isNational: Bool
    let onToggleFollow: (Team) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !group.name.isEmpty {
                // Group names come from ESPN.
                SectionHeader(verbatim: group.name.uppercased())
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
            StandingsHeader(isNational: isNational)
            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                StandingRowView(row: row, isStriped: index % 2 == 1) {
                    onToggleFollow(row.entry.team)
                }
            }
        }
    }
}

struct StandingsHeader: View {
    let isNational: Bool

    /// Played, won, drawn, lost, goal difference: catalog keys, looked up in the app language.
    static let columns = ["P", "W", "D", "L", "GD"]

    var body: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: StandingsMetrics.rankWidth, alignment: .trailing)
            Text(isNational ? "TEAM" : "CLUB")
                .tracking(1)
                .padding(.leading, 32)
            Spacer(minLength: 6)
            ForEach(Self.columns, id: \.self) { column in
                Text(LocalizedStringKey(column))
                    .frame(width: StandingsMetrics.numberWidth, alignment: .trailing)
            }
            Text("PTS")
                .frame(width: StandingsMetrics.pointsWidth, alignment: .trailing)
        }
        .font(Theme.font(.caption))
        .foregroundStyle(Theme.dim)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}

/// A table row: zone bar, rank, crest, name (★ when followed) and the stats.
/// Clicking it follows or unfollows the team.
struct StandingRowView: View {
    let row: TableRowItem
    let isStriped: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    private var entry: StandingEntry { row.entry }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 0) {
                Text("\(entry.rank)")
                    .font(Theme.font(.small))
                    .foregroundStyle(Theme.dim)
                    .frame(width: StandingsMetrics.rankWidth, alignment: .trailing)
                CrestView(team: entry.team, size: StandingsMetrics.crestSize)
                    .padding(.leading, 6)
                Text(row.isFollowed ? "\(entry.team.shortName)  ★" : entry.team.shortName)
                    .font(Theme.font(.body, weight: row.isFollowed ? .bold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 8)
                Spacer(minLength: 6)
                stats
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: StandingsMetrics.rowHeight)
            .background(background, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay(alignment: .leading) { zoneBar }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerStyle(.link)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(row.isFollowed ? "Unfollow" : "Follow")
        .accessibilityAddTraits(row.isFollowed ? .isSelected : [])
    }

    private var stats: some View {
        HStack(spacing: 0) {
            ForEach(Array([entry.played, entry.wins, entry.draws, entry.losses].enumerated()), id: \.offset) { _, value in
                number("\(value)")
            }
            number(entry.goalDifferenceText)
            Text("\(entry.points)")
                .font(Theme.font(.body, weight: .bold))
                .frame(width: StandingsMetrics.pointsWidth, alignment: .trailing)
        }
        .monospacedDigit()
    }

    private func number(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(.small))
            .foregroundStyle(Theme.dim)
            .frame(width: StandingsMetrics.numberWidth, alignment: .trailing)
    }

    /// Qualification / relegation color on the row's left edge; colors that
    /// vanish on the panel (ESPN's white) fall back to the dim text color.
    @ViewBuilder
    private var zoneBar: some View {
        if let zone = entry.zone, !zone.colorHex.isEmpty {
            Capsule()
                .fill(Theme.readable(hex: zone.colorHex, fallback: .dim))
                .frame(width: 3, height: StandingsMetrics.rowHeight - 8)
        }
    }

    private var background: Color {
        if row.isFollowed { return Theme.accent.opacity(0.16) }
        if isHovered { return Theme.hover }
        return isStriped ? Theme.foreground.opacity(0.03) : .clear
    }

    @Environment(\.locale) private var locale

    private var accessibilityText: String {
        let display = DisplayContext(now: .now, locale: locale)
        var parts = ["\(entry.rank). \(entry.team.name)",
                     display.text("\(entry.points) points", comment: "VoiceOver: a team's points in the table."),
                     display.text("played \(entry.played)", comment: "VoiceOver: matches a team has played."),
                     display.text("goal difference \(entry.goalDifferenceText)",
                                  comment: "VoiceOver: a team's goal difference, e.g. +3.")]
        if row.isFollowed {
            parts.insert(display.text("followed", comment: "VoiceOver: the user follows this team."), at: 1)
        }
        if let zone = entry.zone, !zone.description.isEmpty { parts.append(zone.description) }
        return parts.joined(separator: ", ")
    }
}

/// "● Champions League  ● Europa League …", wrapping as needed.
struct ZoneLegend: View {
    let zones: [StandingZone]

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(zones, id: \.description) { zone in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.readable(hex: zone.colorHex, fallback: .dim))
                        .frame(width: 8, height: 8)
                    Text(zone.description)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.dim)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
#Preview("LaLiga") {
    @Previewable @State var league = League.laLiga.id
    ScrollView {
        StandingsList(selection: $league, leagues: League.all, isNational: false,
                      groups: PreviewData.tableGroups,
                      legend: Derivations.zoneLegend(PreviewData.tableGroups),
                      emptyMessage: "", onToggleFollow: { _ in })
            .padding(16)
    }
    .frame(width: Theme.panelWidth, height: Theme.panelHeight)
    .background(Theme.background)
}

#Preview("Loading") {
    @Previewable @State var league = League.mls.id
    StandingsList(selection: $league, leagues: League.all, isNational: false, groups: [], legend: [],
                  emptyMessage: StandingsList.emptyMessage(isLoaded: false, status: .loading),
                  onToggleFollow: { _ in })
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
#endif
