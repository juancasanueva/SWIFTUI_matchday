//
//  MatchesTab.swift
//  matchday
//
//  The Matches tab: filter chips, then fixtures by day with results last
//  (`matchesTab` in Panel.qml).
//

import SwiftUI

/// Container: reads the store; the panel owns the filter (h/l cycle it).
struct MatchesTab: View {
    @Environment(MatchdayStore.self) private var store
    @Binding var filter: MatchFilter

    var body: some View {
        let settings = store.settings
        MatchesList(
            filter: $filter,
            leagues: settings.leagues.compactMap(League.with(id:)),
            sections: store.daySections(filter: filter),
            followedTeamIDs: Set(settings.favorites.map(\.teamID)),
            emptyMessage: MatchesList.emptyMessage(filter: filter, hasFavorites: !settings.favorites.isEmpty,
                                                   isLoading: store.snapshot.status == .loading,
                                                   locale: store.locale),
            footnote: store.footnote
        )
    }
}

struct MatchesList: View {
    @Binding var filter: MatchFilter
    let leagues: [League]
    let sections: [DaySection]
    let followedTeamIDs: Set<String>
    let emptyMessage: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MatchFilterBar(filter: $filter, leagues: leagues)
            if sections.isEmpty {
                Text(emptyMessage)
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sections) { section in
                        DaySectionView(section: section, followedTeamIDs: followedTeamIDs)
                    }
                }
                Text(footnote)
                    .font(Theme.font(.caption))
                    .italic()
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    /// Text shown when no section matches the filter, in the app language of `locale`.
    static func emptyMessage(filter: MatchFilter, hasFavorites: Bool, isLoading: Bool,
                             locale: Locale = AppLocalization.shared.locale) -> String {
        let display = DisplayContext(now: .now, locale: locale)
        if filter == .mine && !hasFavorites {
            return display.text("You're not following anyone yet — pick teams in the Teams tab.",
                                comment: "Matches tab, Mine filter, with no followed team.")
        }
        if isLoading { return display.text("Loading fixtures…", comment: "Shown while matches load.") }
        return display.text("No matches in the next \(RefreshPolicy.daysAhead + 1) days. International break?",
                            comment: "Matches tab with nothing scheduled. The argument is a number of days.")
    }
}

/// All / ★ Mine / one chip per enabled league, wrapping onto new lines.
struct MatchFilterBar: View {
    @Binding var filter: MatchFilter
    let leagues: [League]

    var body: some View {
        FlowLayout(spacing: 6) {
            Chip(title: "All", isSelected: filter == .all, size: .small) { filter = .all }
            Chip(title: "Mine", systemImage: "star.fill", isSelected: filter == .mine, size: .small) {
                filter = .mine
            }
            ForEach(leagues) { league in
                Chip(verbatim: league.short, isSelected: filter == .league(league.id), size: .small) {
                    filter = .league(league.id)
                }
                .help(league.name)
            }
        }
        .padding(.vertical, 1)
    }
}

/// One day: the RESULTS divider before the first past day, the day label
/// with its live count, and the rows.
struct DaySectionView: View {
    let section: DaySection
    let followedTeamIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if section.isFirstPast {
                Text("RESULTS")
                    .font(Theme.font(.caption, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.dim)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
            }
            SectionHeader(verbatim: section.label, color: section.isPast ? Theme.dim : Theme.foreground) {
                if section.liveCount > 0 {
                    Text("● \(section.liveCount) LIVE")
                        .font(Theme.font(.caption, weight: .bold))
                        .foregroundStyle(Theme.urgent)
                        .pulsing(true, minimum: 0.55)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 2)
            Rectangle()
                .fill(Theme.faint)
                .frame(height: 1)
                .padding(.bottom, 2)
            ForEach(section.rows) { row in
                MatchRowView(row: row, highlightedTeamIDs: followedTeamIDs)
            }
        }
    }
}

#if DEBUG
#Preview("All") {
    @Previewable @State var filter = MatchFilter.all
    ScrollView {
        MatchesList(filter: $filter, leagues: League.all, sections: PreviewData.sections(filter),
                    followedTeamIDs: PreviewData.followedIDs, emptyMessage: "",
                    footnote: "Where to watch shows 2026-27 rights holders for Spain.")
            .padding(16)
    }
    .frame(width: Theme.panelWidth, height: Theme.panelHeight)
    .background(Theme.background)
}

#Preview("Empty") {
    @Previewable @State var filter = MatchFilter.mine
    MatchesList(filter: $filter, leagues: League.all, sections: [], followedTeamIDs: [],
                emptyMessage: MatchesList.emptyMessage(filter: .mine, hasFavorites: false, isLoading: false),
                footnote: "")
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
#endif
