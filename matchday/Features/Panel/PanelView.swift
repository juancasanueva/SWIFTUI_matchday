//
//  PanelView.swift
//  matchday
//
//  The menu bar panel: header, tab bar, the selected tab, and a footer.
//

import AppKit
import SwiftUI

/// Container: reads the store and handles the keyboard (Panel.qml:377-389, see
/// `PanelKeyboard`). The popover's owner refreshes on every open (Panel.qml:375).
struct PanelView: View {
    @Environment(MatchdayStore.self) private var store
    @Environment(PanelPresentation.self) private var presentation
    @State private var tab: PanelTab = .following
    /// Chip selections live here so they survive tab switches.
    @State private var selection = PanelSelection()
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var scrollMetrics = PanelScrollMetrics()
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        PanelShell(
            summary: store.header,
            location: store.locationLabel,
            isRefreshing: store.isRefreshing,
            tab: $tab,
            scrollPosition: $scrollPosition,
            onScroll: { scrollMetrics = $0 },
            onRefresh: refresh
        ) {
            content
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onChange(of: presentation.isOpen, initial: true) { _, isOpen in
            hasKeyboardFocus = isOpen
        }
        .onKeyPress(.escape) {
            presentation.close()
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            handle(press)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .following:
            FollowingTab { tab = .teams }
        case .matches:
            MatchesTab(filter: $selection.matchFilter)
        case .tables:
            TablesTab(selection: $selection.tableLeague)
        case .teams:
            TeamsTab(selection: $selection.teamsLeague)
        case .settings:
            SettingsSection()
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Leave ⌘Q and other shortcuts to the system.
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
              let character = press.characters.first,
              let command = PanelCommand(character: character)
        else { return .ignored }
        switch command {
        case .selectTab(let newTab):
            tab = newTab
        case .cycleFilter(let step):
            selection.cycleFilter(on: tab, by: step, settings: store.settings)
        case .scroll(let direction):
            let offset = PanelSelection.scrollOffset(from: scrollMetrics.offset, by: direction,
                                                     contentHeight: scrollMetrics.contentHeight,
                                                     viewportHeight: scrollMetrics.viewportHeight)
            withAnimation(.snappy(duration: 0.15)) { scrollPosition.scrollTo(y: offset) }
        case .refresh:
            refresh()
        }
        return .handled
    }

    private func refresh() {
        Task { await store.refreshNow() }
    }
}

/// Where the panel's scroll view is, for j/k.
struct PanelScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
}

/// Presentational frame of the panel around the selected tab's content.
struct PanelShell<Content: View>: View {
    let summary: String
    let location: String
    let isRefreshing: Bool
    @Binding var tab: PanelTab
    @Binding var scrollPosition: ScrollPosition
    var onScroll: (PanelScrollMetrics) -> Void = { _ in }
    let onRefresh: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(summary: summary, location: location)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            PanelTabBar(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(tab)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: PanelScrollMetrics.self) { geometry in
                PanelScrollMetrics(offset: geometry.contentOffset.y, contentHeight: geometry.contentSize.height,
                                   viewportHeight: geometry.containerSize.height)
            } action: { _, metrics in
                onScroll(metrics)
            }
            .scrollIndicators(.automatic)
            Rectangle()
                .fill(Theme.faint)
                .frame(height: 1)
            PanelFooter(isRefreshing: isRefreshing, onRefresh: onRefresh)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
    }
}

struct PanelHeader: View {
    let summary: String
    let location: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // The app icon itself, so the header always matches the AppIcon set.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Matchday")
                        .font(Theme.font(.display, weight: .bold))
                    Spacer(minLength: 8)
                    locationPill
                }
                // The summary runs the full width under the title row.
                Text(summary)
                    .font(Theme.font(.caption, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
        }
    }

    private var locationPill: some View {
        Label("Watching from \(location)", systemImage: "mappin.and.ellipse")
            .labelStyle(.titleAndIcon)
            .font(Theme.font(.small))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .overlay {
                Capsule().strokeBorder(Theme.foreground.opacity(0.35), lineWidth: 1)
            }
            .layoutPriority(1)
            .help("Where to watch uses this country")
    }
}

struct PanelTabBar: View {
    @Binding var selection: PanelTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PanelTab.allCases) { tab in
                Chip(title: LocalizedStringKey(tab.title), isSelected: selection == tab) {
                    selection = tab
                }
            }
        }
    }
}

struct PanelFooter: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Refreshing…")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .accessibilityLabel("Refresh")
            .disabled(isRefreshing)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(Theme.font(.small))
            .keyboardShortcut("q")
            .help("Quit Matchday (⌘Q)")
        }
        .foregroundStyle(Theme.dim)
    }
}

#Preview {
    @Previewable @State var tab = PanelTab.following
    @Previewable @State var scroll = ScrollPosition(edge: .top)
    PanelShell(summary: "NEXT RMA V RBL · TODAY 9:00 PM", location: "Madrid, Spain",
               isRefreshing: false, tab: $tab, scrollPosition: $scroll, onRefresh: {}) {
        Text(verbatim: "\(tab.title) content")
            .foregroundStyle(Theme.dim)
    }
}
