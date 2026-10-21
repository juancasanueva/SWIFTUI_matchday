//
//  CrestCache.swift
//  matchday
//
//  Crest PNGs mirrored to `Caches/com.juancasanueva.matchday/logos` (`Logos`
//  in the original). A failed download leaves a `.missing` marker so the crest
//  is not requested again for a day.
//

import Foundation

actor CrestCache {
    /// A failed crest is retried after this long.
    static let missingRetry: TimeInterval = 86_400
    /// Anything smaller is an error page, not a crest.
    static let minimumSize = 200
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])

    let directory: URL
    private let transport: any HTTPTransport
    private let clock: @Sendable () -> Date
    /// Downloads in progress, so concurrent requests share one.
    private var inFlight: [String: Task<URL?, Never>] = [:]

    init(directory: URL = CrestCache.defaultDirectory(),
         transport: any HTTPTransport = URLSessionTransport(),
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.transport = transport
        self.clock = clock
    }

    /// `Caches/com.juancasanueva.matchday/logos` (inside the sandbox container).
    nonisolated static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appending(path: "com.juancasanueva.matchday/logos", directoryHint: .isDirectory)
    }

    /// `team-86.png`, `team-86-dark.png`.
    nonisolated static func fileName(kind: Crest.Kind, id: String, dark: Bool) -> String {
        let prefix = switch kind {
        case .team: "team"
        case .league: "league"
        }
        return "\(prefix)-\(id)\(dark ? "-dark" : "").png"
    }

    /// The crest on disk, without downloading.
    func cachedFile(kind: Crest.Kind, id: String, dark: Bool) -> URL? {
        let file = fileURL(kind: kind, id: id, dark: dark)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The crest on disk, downloading it first when needed. `nil` when ESPN has
    /// none (or the download failed within the last day).
    func file(kind: Crest.Kind, id: String, dark: Bool) async -> URL? {
        guard !id.isEmpty else { return nil }
        if let file = cachedFile(kind: kind, id: id, dark: dark) { return file }
        let file = fileURL(kind: kind, id: id, dark: dark)
        if isRecentlyMissing(file) { return nil }

        let key = file.lastPathComponent
        if let task = inFlight[key] { return await task.value }
        let task = Task { await download(Crest.url(kind: kind, id: id, dark: dark), to: file) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    // MARK: Private

    private func fileURL(kind: Crest.Kind, id: String, dark: Bool) -> URL {
        directory.appending(path: Self.fileName(kind: kind, id: id, dark: dark))
    }

    private func markerURL(for file: URL) -> URL {
        file.appendingPathExtension("missing")
    }

    private func isRecentlyMissing(_ file: URL) -> Bool {
        let marker = markerURL(for: file)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: marker.path),
              let modified = attributes[.modificationDate] as? Date
        else { return false }
        return clock().timeIntervalSince(modified) < Self.missingRetry
    }

    private func download(_ url: URL, to file: URL) async -> URL? {
        let manager = FileManager.default
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await transport.get(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status == 200, data.count >= Self.minimumSize, data.starts(with: Self.pngSignature) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            try? manager.removeItem(at: markerURL(for: file))
            return file
        } catch {
            markMissing(file)
            return nil
        }
    }

    /// Creates (or touches) the `.missing` marker, dated by the cache clock.
    private func markMissing(_ file: URL) {
        let manager = FileManager.default
        let marker = markerURL(for: file)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: marker.path) {
            manager.createFile(atPath: marker.path, contents: nil)
        }
        try? manager.setAttributes([.modificationDate: clock()], ofItemAtPath: marker.path)
    }
}
