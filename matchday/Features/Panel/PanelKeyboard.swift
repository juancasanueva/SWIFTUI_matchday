//
//  PanelKeyboard.swift
//  matchday
//
//  Keyboard control of the panel (`PanelKeyCatcher` in Panel.qml): 1–4 pick
//  a tab, h/l cycle the current tab's chips, j/k scroll, r refreshes and Esc
//  closes. Also the chip selections, kept by the panel so they survive tab
//  switches and h/l always starts from what is shown.
//

import Foundation

nonisolated enum PanelTab: String, CaseIterable, Identifiable, Sendable {
    case following, matches, tables, teams

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

nonisolated enum PanelCommand: Equatable, Sendable {
    case selectTab(PanelTab)
    /// Previous (-1) or next (+1) chip.
    case cycleFilter(Int)
    /// Up (-1) or down (+1) one step.
    case scroll(Int)
    case refresh

    init?(character: Character) {
        switch character {
        case "1", "2", "3", "4":
            guard let digit = character.wholeNumberValue else { return nil }
            self = .selectTab(PanelTab.allCases[digit - 1])
        case "h": self = .cycleFilter(-1)
        case "l": self = .cycleFilter(1)
        case "j": self = .scroll(1)
        case "k": self = .scroll(-1)
        case "r", "R": self = .refresh
        default: return nil
        }
    }
}

/// The chips selected on the Matches, Tables and Teams tabs.
nonisolated struct PanelSelection: Equatable, Sendable {
    /// Distance scrolled by one j/k press.
    static let scrollStep: CGFloat = 80

    var matchFilter: MatchFilter = .all
    /// `nil` until the user picks one: Tables then shows a followed team's league.
    var tableLeague: String?
    var teamsLeague: String?

    /// Moves the chip selection of `tab` by `step` (`moveFilter`).
    mutating func cycleFilter(on tab: PanelTab, by step: Int, settings: AppSettings) {
        let leagues = settings.leagues
        switch tab {
        case .following:
            break
        case .matches:
            matchFilter = Self.cycle([.all, .mine] + leagues.map(MatchFilter.league), current: matchFilter, by: step)
        case .tables:
            let shown = Derivations.pickerLeague(selected: tableLeague, settings: settings, preferFollowed: true)
            tableLeague = Self.cycle(leagues, current: shown, by: step)
        case .teams:
            let shown = Derivations.pickerLeague(selected: teamsLeague, settings: settings, preferFollowed: false)
            teamsLeague = Self.cycle(leagues, current: shown, by: step)
        }
    }

    /// The option `step` places after `current`, wrapping around; an unknown
    /// `current` counts as the first option.
    static func cycle<Option: Equatable>(_ options: [Option], current: Option, by step: Int) -> Option {
        guard !options.isEmpty else { return current }
        let index = options.firstIndex(of: current) ?? 0
        let count = options.count
        return options[((index + step) % count + count) % count]
    }

    /// Vertical offset after scrolling `direction` steps, clamped to the content.
    static func scrollOffset(from offset: CGFloat, by direction: Int, contentHeight: CGFloat,
                             viewportHeight: CGFloat) -> CGFloat {
        let maximum = max(0, contentHeight - viewportHeight)
        return min(max(0, offset + CGFloat(direction) * scrollStep), maximum)
    }
}
