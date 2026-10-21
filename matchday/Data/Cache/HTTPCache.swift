//
//  HTTPCache.swift
//  matchday
//

import Foundation

/// Fetched ESPN JSON keyed by request, mirrored to disk so launches are instant
/// (the original plugin's `Store`). Files are `{"at", "key", "data"}` JSON
/// documents, loaded on demand.
actor HTTPCache {
    nonisolated struct Entry: Sendable {
        let fetchedAt: Date
        let data: Data
    }

    let directory: URL
    private var entries: [String: Entry] = [:]
    /// Keys already looked up on disk and not found.
    private var missing: Set<String> = []
    /// Entries fetched at or before this instant count as expired (Refresh).
    private var invalidatedAt: Date?

    init(directory: URL = HTTPCache.defaultDirectory()) {
        self.directory = directory
    }

    /// `Caches/com.juancasanueva.matchday/http` (inside the sandbox container).
    nonisolated static func defaultDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appending(path: "com.juancasanueva.matchday/http", directoryHint: .isDirectory)
    }

    nonisolated static func fileName(for key: String) -> String {
        key.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_") + ".json"
    }

    // MARK: Reading

    func entry(for key: String) -> Entry? {
        if let entry = entries[key] { return entry }
        if missing.contains(key) { return nil }
        guard let entry = readFromDisk(key) else {
            missing.insert(key)
            return nil
        }
        entries[key] = entry
        return entry
    }

    /// Seconds since `key` was fetched; infinite when absent or invalidated.
    func age(of key: String, now: Date) -> TimeInterval {
        guard let entry = entry(for: key) else { return .infinity }
        if let invalidatedAt, entry.fetchedAt <= invalidatedAt { return .infinity }
        return now.timeIntervalSince(entry.fetchedAt)
    }

    // MARK: Writing

    func store(_ data: Data, for key: String, at date: Date) {
        entries[key] = Entry(fetchedAt: date, data: data)
        missing.remove(key)
        writeToDisk(key: key, data: data, at: date)
    }

    /// Marks everything expired while keeping the data for display.
    func invalidateAll(now: Date) {
        invalidatedAt = now
    }

    /// Removes day scoreboards (`sb:` keys) that left the polling window.
    func prune(keepingScoreboards keep: Set<String>) {
        for key in entries.keys where key.hasPrefix("sb:") && !keep.contains(key) {
            entries[key] = nil
        }
        let keepFiles = Set(keep.map(Self.fileName(for:)))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for file in files where file.hasPrefix("sb_") && file.hasSuffix(".json") && !keepFiles.contains(file) {
            try? FileManager.default.removeItem(at: directory.appending(path: file))
        }
    }

    // MARK: Disk

    private func readFromDisk(_ key: String) -> Entry? {
        let url = directory.appending(path: Self.fileName(for: key))
        guard let raw = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let at = object["at"] as? Double,
              let payload = object["data"],
              let data = try? JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed)
        else { return nil }
        return Entry(fetchedAt: Date(timeIntervalSince1970: at), data: data)
    }

    private func writeToDisk(key: String, data: Data, at date: Date) {
        // Failures only cost a refetch after the next launch, so they are ignored.
        guard let payload = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return }
        let document: [String: Any] = ["at": date.timeIntervalSince1970, "key": key, "data": payload]
        guard let encoded = try? JSONSerialization.data(withJSONObject: document) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoded.write(to: directory.appending(path: Self.fileName(for: key)), options: .atomic)
        } catch {
            return
        }
    }
}
