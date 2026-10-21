//
//  AboutModelTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("About model")
struct AboutModelTests {
    @Test func readsVersionAndBuildFromTheBundle() {
        let info = AboutModel.info(bundleInfo: [
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "42",
        ])
        #expect(info.appName == "Matchday")
        #expect(info.tagline == "Follow your soccer teams from the menu bar.")
        #expect(info.versionText == "1.2.0 (42)")
    }

    @Test func aMissingBuildLeavesTheBareVersion() {
        #expect(AboutModel.versionText(shortVersion: "1.0.0", build: nil) == "1.0.0")
        #expect(AboutModel.versionText(shortVersion: "1.0.0", build: "") == "1.0.0")
    }

    @Test func aMissingVersionReadsUnknown() {
        #expect(AboutModel.info(bundleInfo: [:]).versionText == "Unknown")
        #expect(AboutModel.versionText(shortVersion: "", build: "7") == "Unknown")
    }

    @Test func listsTheRowsInOrder() {
        let rows = AboutModel.info(bundleInfo: [:]).rows
        #expect(rows.map(\.label) == ["Data", "Leagues", "Source"])
        #expect(rows[0].value == "ESPN public site API (unofficial)")
        #expect(rows[1].value.contains("LaLiga"))
        #expect(rows[1].value.contains("Nations League"))
    }

    @Test func sourceLinksToTheRepository() throws {
        let source = try #require(AboutModel.info(bundleInfo: [:]).rows.last)
        #expect(source.url == URL(string: "https://github.com/juancasanueva/SWIFTUI_matchday"))
        #expect(source.value == "github.com/juancasanueva/SWIFTUI_matchday")
    }

    @Test func everyLinkIsHTTPSWithAHost() {
        let links = AboutModel.info(bundleInfo: [:]).rows.compactMap(\.url)
        #expect(!links.isEmpty)
        for link in links {
            #expect(link.scheme == "https")
            #expect(link.host() != nil)
        }
    }

    @Test func footerDisclaimsAffiliation() {
        #expect(AboutModel.info(bundleInfo: [:]).footer.contains("Not affiliated with ESPN"))
    }
}
