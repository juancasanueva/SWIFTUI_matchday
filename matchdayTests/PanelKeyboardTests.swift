//
//  PanelKeyboardTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Panel keyboard")
struct PanelKeyboardTests {
    static let keys: [(Character, PanelCommand?)] = [
        ("1", .selectTab(.following)), ("2", .selectTab(.matches)), ("3", .selectTab(.tables)),
        ("4", .selectTab(.teams)), ("5", nil),
        ("h", .cycleFilter(-1)), ("l", .cycleFilter(1)),
        ("j", .scroll(1)), ("k", .scroll(-1)),
        ("r", .refresh), ("R", .refresh), ("x", nil),
    ]

    @Test(arguments: keys)
    func charactersMapToCommands(character: Character, command: PanelCommand?) {
        #expect(PanelCommand(character: character) == command)
    }

    @Test func cyclingWrapsAroundBothWays() {
        let options = ["a", "b", "c"]
        #expect(PanelSelection.cycle(options, current: "a", by: 1) == "b")
        #expect(PanelSelection.cycle(options, current: "c", by: 1) == "a")
        #expect(PanelSelection.cycle(options, current: "a", by: -1) == "c")
        // An unknown value counts as the first option (Panel.qml `cycle`).
        #expect(PanelSelection.cycle(options, current: "z", by: 1) == "b")
    }

    @Test func matchesFilterCyclesThroughAllMineAndLeagues() {
        var settings = AppSettings()
        settings.setLeagues(["esp.1", "eng.1"])
        var selection = PanelSelection()
        selection.cycleFilter(on: .matches, by: 1, settings: settings)
        #expect(selection.matchFilter == .mine)
        selection.cycleFilter(on: .matches, by: 1, settings: settings)
        #expect(selection.matchFilter == .league("esp.1"))
        selection.cycleFilter(on: .matches, by: 2, settings: settings)
        #expect(selection.matchFilter == .all)
        selection.cycleFilter(on: .matches, by: -1, settings: settings)
        #expect(selection.matchFilter == .league("eng.1"))
    }

    @Test func tablesStartFromTheShownLeagueAndTeamsCycleSeparately() {
        var settings = Make.settings(following: [Make.team("359", league: "eng.1")])
        settings.setLeagues(["esp.1", "eng.1", "usa.1"])
        var selection = PanelSelection()
        // Tables shows the followed team's league first, so "l" moves on from it.
        selection.cycleFilter(on: .tables, by: 1, settings: settings)
        #expect(selection.tableLeague == "usa.1")
        selection.cycleFilter(on: .teams, by: -1, settings: settings)
        #expect(selection.teamsLeague == "usa.1")
        #expect(selection.tableLeague == "usa.1")
        selection.cycleFilter(on: .following, by: 1, settings: settings)
        #expect(selection == PanelSelection(matchFilter: .all, tableLeague: "usa.1", teamsLeague: "usa.1"))
    }

    @Test func scrollOffsetStaysInsideTheContent() {
        #expect(PanelSelection.scrollOffset(from: 0, by: 1, contentHeight: 1000, viewportHeight: 600) == 80)
        #expect(PanelSelection.scrollOffset(from: 380, by: 1, contentHeight: 1000, viewportHeight: 600) == 400)
        #expect(PanelSelection.scrollOffset(from: 40, by: -1, contentHeight: 1000, viewportHeight: 600) == 0)
        #expect(PanelSelection.scrollOffset(from: 0, by: 1, contentHeight: 300, viewportHeight: 600) == 0)
    }
}
