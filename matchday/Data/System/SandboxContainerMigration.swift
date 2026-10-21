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
    }

    /// Set in the destination defaults once the container has been read.
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
    /// always wins, so running it again is harmless; failures are only logged.
    @discardableResult
    func run() -> Outcome {
        guard !defaults.bool(forKey: Self.markerKey) else { return .alreadyMigrated }
        guard fileManager.fileExists(atPath: containerData.path(percentEncoded: false)) else { return .noContainer }

        migratePreferences()
        for file in Self.ownedFiles {
            migrateFile(file)
        }
        defaults.set(true, forKey: Self.markerKey)
        Logger.app.info("Migrated settings from the sandbox container")
        return .migrated
    }

    private func migratePreferences() {
        let url = containerData.appending(path: "Library/Preferences/\(bundleIdentifier).plist")
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let values = try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return }
            for key in Self.ownedKeys where defaults.object(forKey: key) == nil {
                if let value = values[key] {
                    defaults.set(value, forKey: key)
                }
            }
        } catch {
            Logger.app.error("Could not read the sandbox preferences: \(error.localizedDescription)")
        }
    }

    private func migrateFile(_ relativePath: String) {
        let source = containerData.appending(path: "Library/Application Support/\(relativePath)")
        let destination = applicationSupport.appending(path: relativePath)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)),
              !fileManager.fileExists(atPath: destination.path(percentEncoded: false))
        else { return }
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            Logger.app.error("Could not copy \(relativePath) from the sandbox: \(error.localizedDescription)")
        }
    }
}
