//
//  CrestLoader.swift
//  matchday
//
//  Decoded crest images kept in memory on top of the disk `CrestCache`.
//

import AppKit

@MainActor
final class CrestLoader {
    static let shared = CrestLoader(cache: CrestCache())

    let cache: CrestCache
    private var images: [String: NSImage] = [:]

    init(cache: CrestCache) {
        self.cache = cache
    }

    /// The crest if it is already decoded; never touches the disk or network.
    func loadedImage(for team: Team, dark: Bool) -> NSImage? {
        images[key(team, dark: dark)]
    }

    /// The crest for the appearance: on dark backgrounds the `500-dark` variant
    /// when ESPN has one, else the regular crest (`logo()` in Panel.qml).
    func image(for team: Team, dark: Bool) async -> NSImage? {
        let key = key(team, dark: dark)
        if let image = images[key] { return image }
        var file: URL?
        if dark { file = await cache.file(kind: .team, id: team.id, dark: true) }
        if file == nil { file = await cache.file(kind: .team, id: team.id, dark: false) }
        guard let file, let image = NSImage(contentsOf: file) else { return nil }
        images[key] = image
        return image
    }

    private func key(_ team: Team, dark: Bool) -> String {
        "\(team.id)\(dark ? "-dark" : "")"
    }
}
