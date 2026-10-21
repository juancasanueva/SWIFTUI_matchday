//
//  StatusItemLookTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Status item look")
struct StatusItemLookTests {
    private func bar(dot: Bool = false, live: Bool = false, text: String? = nil,
                     tooltip: String = "tip", dimmed: Bool = false) -> BarState {
        BarState(showDot: dot, isLive: live, liveText: text, tooltip: tooltip, isDimmed: dimmed)
    }

    @Test func nothingFollowedShowsADimmedBallOnly() {
        let look = StatusItemLook(bar: .empty, reduceMotion: false)
        #expect(look.dot == nil)
        #expect(look.isDimmed)
        #expect(look.title.isEmpty)
        #expect(!look.pulses)
        #expect(look.tooltip == Derivations.emptyTooltip)
        #expect(look.accessibilityLabel == "Matchday")
    }

    @Test func aMatchSoonLightsTheAccentDot() {
        let look = StatusItemLook(bar: bar(dot: true), reduceMotion: false)
        #expect(look.dot == .soon)
        #expect(!look.pulses)
        #expect(look.accessibilityLabel == "Matchday, a followed team plays soon")
    }

    @Test func aLiveMatchPulsesTheRedDot() {
        let look = StatusItemLook(bar: bar(dot: true, live: true), reduceMotion: false)
        #expect(look.dot == .live)
        #expect(look.pulses)
        #expect(look.accessibilityLabel == "Matchday, a followed team is live")
    }

    @Test func reduceMotionStopsThePulse() {
        let look = StatusItemLook(bar: bar(dot: true, live: true), reduceMotion: true)
        #expect(look.dot == .live)
        #expect(!look.pulses)
    }

    @Test func liveTextReplacesTheDot() {
        let look = StatusItemLook(bar: bar(dot: true, live: true, text: "BAR 2–1 GET  67'"), reduceMotion: false)
        #expect(look.dot == nil)
        #expect(!look.pulses)
        #expect(look.title == "BAR 2–1 GET  67'")
    }

    @Test func pulseDimsOnlyTheLiveDotOnTheOffBeat() {
        let live = StatusItemLook(bar: bar(dot: true, live: true), reduceMotion: false)
        #expect(live.dotOpacity(pulseDimmed: false) == 1)
        #expect(live.dotOpacity(pulseDimmed: true) == 0.35)
        let calm = StatusItemLook(bar: bar(dot: true, live: true), reduceMotion: true)
        #expect(calm.dotOpacity(pulseDimmed: true) == 1)
    }
}
