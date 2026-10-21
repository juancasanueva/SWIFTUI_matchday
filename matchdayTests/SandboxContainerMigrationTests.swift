//
//  SandboxContainerMigrationTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

@Suite("Sandbox container migration")
struct SandboxContainerMigrationTests {
    /// A throwaway home: the old container under `Containers/…/Data`, the real
    /// Application Support beside it, and a fresh defaults suite.
    struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        var containerData: URL { root.appending(path: "Containers/com.juancasanueva.matchday/Data") }
        var applicationSupport: URL { root.appending(path: "Application Support") }
        var containerPreferences: URL {
            containerData.appending(path: "Library/Preferences/com.juancasanueva.matchday.plist")
        }
        var containerNotified: URL {
            containerData.appending(path: "Library/Application Support/com.juancasanueva.matchday/notified.json")
        }
        var notified: URL { applicationSupport.appending(path: "com.juancasanueva.matchday/notified.json") }

        var migration: SandboxContainerMigration {
            SandboxContainerMigration(containerData: containerData, applicationSupport: applicationSupport,
                                      bundleIdentifier: "com.juancasanueva.matchday", defaults: defaults)
        }

        init() {
            root = FileManager.default.temporaryDirectory.appending(path: "matchday-migration-\(UUID().uuidString)")
            let suite = "matchday-tests-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
        }

        /// Writes the container's preferences plist and its notification memory.
        func seedContainer(preferences: [String: Any], notified: String? = nil) throws {
            try FileManager.default.createDirectory(at: containerPreferences.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
            try data.write(to: containerPreferences)
            if let notified {
                try write(notified, to: containerNotified)
            }
        }

        func write(_ text: String, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    let settings = Data(#"{"favorites":[],"country":"ES"}"#.utf8)

    @Test func copiesOwnedSettingsAndTheNotificationMemory() throws {
        let sandbox = Sandbox()
        try sandbox.seedContainer(preferences: [UserDefaultsSettingsStore.key: settings,
                                                "NSWindow Frame Main": "0 0 10 10"],
                                  notified: #"{"kickoff":[]}"#)

        let outcome = sandbox.migration.run()

        #expect(outcome == .migrated)
        #expect(sandbox.defaults.data(forKey: UserDefaultsSettingsStore.key) == settings)
        // Only keys the app owns come across, not AppKit's window state.
        #expect(sandbox.defaults.object(forKey: "NSWindow Frame Main") == nil)
        #expect(try String(contentsOf: sandbox.notified, encoding: .utf8) == #"{"kickoff":[]}"#)
        #expect(sandbox.defaults.bool(forKey: SandboxContainerMigration.markerKey))
        // The container is left in place.
        #expect(FileManager.default.fileExists(atPath: sandbox.containerPreferences.path(percentEncoded: false)))
    }

    @Test func skipsOnceTheMarkerIsSet() throws {
        let sandbox = Sandbox()
        try sandbox.seedContainer(preferences: [UserDefaultsSettingsStore.key: settings], notified: "{}")
        sandbox.defaults.set(true, forKey: SandboxContainerMigration.markerKey)

        #expect(sandbox.migration.run() == .alreadyMigrated)
        #expect(sandbox.defaults.data(forKey: UserDefaultsSettingsStore.key) == nil)
        #expect(!FileManager.default.fileExists(atPath: sandbox.notified.path(percentEncoded: false)))
    }

    @Test func neverOverwritesExistingData() throws {
        let sandbox = Sandbox()
        try sandbox.seedContainer(preferences: [UserDefaultsSettingsStore.key: settings], notified: "old")
        let newer = Data(#"{"country":"GB"}"#.utf8)
        sandbox.defaults.set(newer, forKey: UserDefaultsSettingsStore.key)
        try sandbox.write("new", to: sandbox.notified)

        #expect(sandbox.migration.run() == .migrated)
        #expect(sandbox.defaults.data(forKey: UserDefaultsSettingsStore.key) == newer)
        #expect(try String(contentsOf: sandbox.notified, encoding: .utf8) == "new")
    }

    @Test func withoutAContainerItIsANoOp() {
        let sandbox = Sandbox()

        #expect(sandbox.migration.run() == .noContainer)
        #expect(sandbox.defaults.data(forKey: UserDefaultsSettingsStore.key) == nil)
        #expect(!sandbox.defaults.bool(forKey: SandboxContainerMigration.markerKey))
    }

    @Test func runningTwiceIsHarmless() throws {
        let sandbox = Sandbox()
        try sandbox.seedContainer(preferences: [UserDefaultsSettingsStore.key: settings])

        #expect(sandbox.migration.run() == .migrated)
        #expect(sandbox.migration.run() == .alreadyMigrated)
        #expect(sandbox.defaults.data(forKey: UserDefaultsSettingsStore.key) == settings)
    }

    /// A copy that fails for a reason that can go away (disk full, a locked
    /// volume) leaves the marker unset, so the next launch tries again.
    @Test func aFailedCopyIsRetriedOnTheNextLaunch() throws {
        let sandbox = Sandbox()
        try sandbox.seedContainer(preferences: [UserDefaultsSettingsStore.key: settings], notified: "{}")
        var failing = sandbox.migration
        failing.fileManager = FailingCopyFileManager()

        #expect(failing.run() == .incomplete)
        #expect(!sandbox.defaults.bool(forKey: SandboxContainerMigration.markerKey))
        #expect(!FileManager.default.fileExists(atPath: sandbox.notified.path(percentEncoded: false)))

        #expect(sandbox.migration.run() == .migrated)
        #expect(try String(contentsOf: sandbox.notified, encoding: .utf8) == "{}")
        #expect(sandbox.defaults.bool(forKey: SandboxContainerMigration.markerKey))
    }

    @Test func unreadablePreferencesStillMarkTheMigrationDone() throws {
        let sandbox = Sandbox()
        try sandbox.write("not a plist", to: sandbox.containerPreferences)

        #expect(sandbox.migration.run() == .migrated)
        #expect(sandbox.defaults.data(forKey: UserDefaultsSettingsStore.key) == nil)
        #expect(sandbox.defaults.bool(forKey: SandboxContainerMigration.markerKey))
    }
}

/// A file manager whose copies always fail, as a full or locked disk would.
nonisolated private final class FailingCopyFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
