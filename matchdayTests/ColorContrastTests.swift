//
//  ColorContrastTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Color contrast")
struct ColorContrastTests {
    @Test func hexParsingIsStrict() {
        #expect(ColorContrast.rgb(hex: "#1aa0e8") == 0x1AA0E8)
        #expect(ColorContrast.rgb(hex: " FFFFFF\n") == 0xFFFFFF)
        #expect(ColorContrast.rgb(hex: "+12345") == nil)
        #expect(ColorContrast.rgb(hex: "#fff") == nil)
        #expect(ColorContrast.rgb(hex: "") == nil)
    }

    @Test func luminanceSpansBlackToWhite() {
        #expect(ColorContrast.luminance(0x000000) == 0)
        #expect(abs(ColorContrast.luminance(0xFFFFFF) - 1) < 0.0001)
    }

    @Test func colorsTooCloseToTheBackgroundAreUnreadable() {
        let light: UInt32 = 0xF5F7FA, dark: UInt32 = 0x0D1724
        #expect(!ColorContrast.isReadable(0xFFFFFF, on: light))
        #expect(ColorContrast.isReadable(0xFFFFFF, on: dark))
        #expect(!ColorContrast.isReadable(0x000000, on: dark))
        #expect(ColorContrast.isReadable(0x1AA0E8, on: light) && ColorContrast.isReadable(0x1AA0E8, on: dark))
    }
}
