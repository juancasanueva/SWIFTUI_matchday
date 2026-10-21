//
//  SandboxContainerMigration.swift
//  matchday
//
//  Matchday used to run in the App Sandbox, so its settings and notification
//  memory live in `~/Library/Containers/<bundle id>/Data`. Outside the sandbox
//  the app reads the real Library instead; this copies what it owns across
//  once. The container itself is never touched.
//

import Foundation
import OSLog

nonisolated struct SandboxContainerMigration: @unchecked Sendable {
    nonisolated enum Outcome: Sendable, Equatable {
        case noContainer
        case alreadyMigrated
        case migrated
        /// A step failed for a reason that may go away; the next launch retries.
        case incomplete
    }

    /// Set in the destination defaults once every step has finished.
    static let markerKey = "matchday.migratedFromSandboxContainer"
    /// The UserDefaults keys Matchday owns; AppKit's window state stays behind.
    static let ownedKeys = [UserDefaultsSettingsStore.key]
    /// Files under Application Support, relative to it.
    static let ownedFiles = ["com.juancasanueva.matchday/notified.json"]

    /// The old container's `Data` folder (its home directory).
    let containerData: URL
    /// The real `~/Library/Application Support`.
    let applicationSupport: URL
    let bundleIdentifier: String
    /// `UserDefaults` is thread-safe; tests inject a throwaway suite.
    let defaults: UserDefaults
    var fileManager: FileManager = .default

    /// The current user's real container and Application Support, valid outside the sandbox.
    static func live(defaults: UserDefaults = .standard) -> SandboxContainerMigration {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.juancasanueva.matchday"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appending(path: "Library/Application Support")
        return SandboxContainerMigration(
            containerData: home.appending(path: "Library/Containers/\(bundleIdentifier)/Data"),
            applicationSupport: support,
            bundleIdentifier: bundleIdentifier,
            defaults: defaults
        )
    }

    /// Copies owned preferences and files that are missing here. Existing data
    /// always wins, so running it again is harmless. The marker is set only when
    /// every step finished or had nothing it could ever do; a step that failed
    /// for a reason that may go away leaves it unset, so the next launch retries.
    @discardableResult
    func run() -> Outcome {
        guard !defaults.bool(forKey: Self.markerKey) else { return .alreadyMigrated }
        guard fileManager.fileExists(atPath: containerData.path(percentEncoded: false)) else { return .noContainer }

        var complete = migratePreferences()
        for file in Self.ownedFiles {
            complete = migrateFile(file) && complete
        }
        guard complete else {
            Logger.app.error("Sandbox container migration incomplete; it will be retried next launch")
            return .incomplete
        }
        defaults.set(true, forKey: Self.markerKey)
        Logger.app.info("Migrated settings from the sandbox container")
        return .migrated
    }

    /// `false` only when the plist could not be read; a plist that reads but
    /// does not parse is corrupt, will not fix itself, and counts as done.
    private func migratePreferences() -> Bool {
        let url = containerData.appending(path: "Library/Preferences/\(bundleIdentifier).plist")
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return true }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Logger.app.error("Could not read the sandbox preferences: \(error.localizedDescription)")
            return false
        }
        guard let values = try? PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any] else {
            Logger.app.error("The sandbox preferences are not a property list; skipping them")
            return true
        }
        for key in Self.ownedKeys where defaults.object(forKey: key) == nil {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            }
        }
        return true
    }

    /// `false` when the copy failed; nothing to copy, or data already here, is done.
    private func migrateFile(_ relativePath: String) -> Bool {
        let source = containerData.appending(path: "Library/Application Support/\(relativePath)")
        let destination = applicationSupport.appending(path: relativePath)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)),
              !fileManager.fileExists(atPath: destination.path(percentEncoded: false))
        else { return true }
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            return true
        } catch {
            Logger.app.error("Could not copy \(relativePath) from the sandbox: \(error.localizedDescription)")
            return false
        }
    }
}
