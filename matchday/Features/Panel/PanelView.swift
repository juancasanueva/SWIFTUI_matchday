//
//  PanelView.swift
//  matchday
//
//  The menu bar panel: header, tab bar, the selected tab, and a footer.
//

import AppKit
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case following, matches, tables, teams

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// Container: reads the store and refreshes whenever the panel opens (Panel.qml:375).
struct PanelView: View {
    @Environment(MatchdayStore.self) private var store
    @State private var tab: PanelTab = .following

    var body: some View {
        PanelShell(
            summary: store.header,
            location: store.locationLabel,
            isRefreshing: store.isRefreshing,
            tab: $tab,
            onRefresh: refresh
        ) {
            content
        }
        .task { await store.refreshNow() }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .following:
            FollowingTab { tab = .teams }
        case .matches, .tables, .teams:
            ComingSoonView(title: tab.title)
        }
    }

    private func refresh() {
        Task { await store.refreshNow() }
    }
}

/// Presentational frame of the panel around the selected tab's content.
struct PanelShell<Content: View>: View {
    let summary: String
    let location: String
    let isRefreshing: Bool
    @Binding var tab: PanelTab
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "soccerball")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Matchday")
                    .font(Theme.font(.title, weight: .bold))
                Text(summary)
                    .font(Theme.font(.caption, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Label("Watching from \(location)", systemImage: "mappin.and.ellipse")
                .labelStyle(.titleAndIcon)
                .font(Theme.font(.small))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay {
                    Capsule().strokeBorder(Theme.foreground.opacity(0.35), lineWidth: 1)
                }
                .help("Where to watch uses this country")
        }
    }
}

struct PanelTabBar: View {
    @Binding var selection: PanelTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PanelTab.allCases) { tab in
                Chip(title: tab.title, isSelected: selection == tab) {
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

/// Placeholder for tabs that arrive in later tasks.
struct ComingSoonView: View {
    let title: String

    var body: some View {
        Text("\(title) arrives soon.")
            .font(Theme.font(.body))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

#Preview {
    @Previewable @State var tab = PanelTab.following
    PanelShell(summary: "NEXT RMA V RBL · TODAY 9:00 PM", location: "Madrid, Spain",
               isRefreshing: false, tab: $tab, onRefresh: {}) {
        ComingSoonView(title: tab.title)
    }
}
