//
//  AboutModel.swift
//  matchday
//
//  Everything the About window shows, as plain values. Identity, credits and
//  links describe the project, so they are constants; only the version comes
//  from the bundle, through the Info.plist dictionary the caller passes.
//

import Foundation

/// One row of the About card: a label and a value, optionally a link.
nonisolated struct AboutRow: Sendable, Equatable, Identifiable {
    let label: String
    /// Visible text; for a link, the address without its scheme.
    let value: String
    var url: URL?

    var id: String { label }
}

nonisolated struct AboutInfo: Sendable, Equatable {
    let appName: String
    let tagline: String
    /// Marketing version and build, for example `"1.0.0 (7)"`.
    let versionText: String
    let rows: [AboutRow]
    let footer: String
}

nonisolated enum AboutModel {
    static let appName = "Matchday"
    static let tagline = "Follow your soccer teams from the menu bar."
    static let footer = "Personal project. Not affiliated with ESPN or any league or club."

    private static let unknownVersion = "Unknown"

    private static let rows = [
        AboutRow(label: "Data", value: "ESPN public site API (unofficial)"),
        AboutRow(label: "Leagues",
                 value: "LaLiga · Serie A · Premier League · MLS · Champions League · Nations League"),
        AboutRow(label: "Based on", value: "Omarchy \u{201C}Matchday\u{201D} plugin (grivera.matchday)"),
        AboutRow(label: "Source", value: "github.com/juancasanueva/SWIFTUI_matchday",
                 url: URL(string: "https://github.com/juancasanueva/SWIFTUI_matchday")),
    ]

    /// Builds the content from an Info.plist dictionary, normally
    /// `Bundle.main.infoDictionary`.
    static func info(bundleInfo: [String: Any]) -> AboutInfo {
        AboutInfo(
            appName: appName,
            tagline: tagline,
            versionText: versionText(shortVersion: bundleInfo["CFBundleShortVersionString"] as? String,
                                     build: bundleInfo["CFBundleVersion"] as? String),
            rows: rows,
            footer: footer
        )
    }

    /// `"<version> (<build>)"`, the wording Finder's Get Info uses. A missing
    /// build leaves the bare version; a missing version reads "Unknown".
    static func versionText(shortVersion: String?, build: String?) -> String {
        guard let shortVersion, !shortVersion.isEmpty else { return unknownVersion }
        guard let build, !build.isEmpty else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }
}
