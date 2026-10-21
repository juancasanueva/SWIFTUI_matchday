//
//  PanelPresentationTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@MainActor
@Suite("Panel presentation")
struct PanelPresentationTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func tracksOpenAndClose() {
        let presentation = PanelPresentation()
        #expect(!presentation.isOpen)
        presentation.didOpen()
        #expect(presentation.isOpen)
        presentation.didClose(at: start)
        #expect(!presentation.isOpen)
    }

    /// The transient popover closes on mouse-down over the status item; the
    /// item's mouse-up toggle must not reopen it.
    @Test func ignoresAClickThatJustClosedThePanel() {
        let presentation = PanelPresentation()
        presentation.didOpen()
        presentation.didClose(at: start)
        let sameClick = start.addingTimeInterval(0.1)
        #expect(!presentation.shouldOpen(at: sameClick))
    }

    @Test func opensOnALaterClick() {
        let presentation = PanelPresentation()
        #expect(presentation.shouldOpen(at: start))
        presentation.didOpen()
        presentation.didClose(at: start)
        let laterClick = start.addingTimeInterval(1)
        #expect(presentation.shouldOpen(at: laterClick))
    }

    /// About closes the panel before the window opens, so it is not covered.
    @Test func openAboutClosesThePanelFirst() {
        let presentation = PanelPresentation()
        var calls: [String] = []
        presentation.onClose = { calls.append("close") }
        presentation.onOpenAbout = { calls.append("about") }
        presentation.openAbout()
        #expect(calls == ["close", "about"])
    }
}
