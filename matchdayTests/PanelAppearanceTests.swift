//
//  PanelAppearanceTests.swift
//  matchdayTests
//

import AppKit
import Testing
@testable import matchday

@Suite("Panel appearance")
struct PanelAppearanceTests {
    @Test func systemFollowsTheSystemAppearance() {
        #expect(PanelAppearance.appearance(for: .system) == nil)
    }

    static let fixedCases: [(AppearanceMode, NSAppearance.Name)] = [(.light, .aqua), (.dark, .darkAqua)]

    @Test(arguments: fixedCases)
    func lightAndDarkPinTheAquaAppearances(mode: AppearanceMode, expected: NSAppearance.Name) {
        #expect(PanelAppearance.appearance(for: mode)?.name == expected)
    }
}
