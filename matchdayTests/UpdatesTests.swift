//
//  UpdatesTests.swift
//  matchdayTests
//

import AppKit
import Foundation
import Testing
@testable import matchday

@MainActor
@Suite("App updating")
struct AppUpdatingTests {
    @Test func eachInvocationStartsExactlyOneCheck() {
        let updater = FakeAppUpdater()
        updater.checkForUpdates()
        #expect(updater.checkCount == 1)
        updater.checkForUpdates()
        #expect(updater.checkCount == 2)
    }

    @Test(arguments: [true, false])
    func thePersistedPreferenceIsWrittenExactlyOnce(preference: Bool) {
        // Start from an updater that disagrees, so a "write only if different" policy fails.
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: !preference)
        AutomaticUpdateChecksPolicy.apply(preference: preference, to: updater)
        #expect(updater.automaticallyChecksForUpdates == preference)
        #expect(updater.automaticWriteCount == 1)
    }

    @Test func anAgreeingPreferenceIsStillWritten() {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: false)
        AutomaticUpdateChecksPolicy.apply(preference: false, to: updater)
        #expect(updater.automaticWriteCount == 1)
    }

    @Test(arguments: [true, false])
    func theCommandIsEnabledExactlyWhileACheckCanRun(canCheck: Bool) {
        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: canCheck) == canCheck)
    }

    /// The unit-test host never builds the real updater, so Sparkle never starts in tests.
    @Test func launchingInTheTestHostNeverBuildsAnUpdater() {
        let delegate = AppDelegate()
        var built = 0
        delegate.updaterFactory = {
            built += 1
            return FakeAppUpdater()
        }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(built == 0)
        #expect(delegate.updater == nil)
    }

    @Test func theUpdaterFactoryCanBeSubstituted() {
        let delegate = AppDelegate()
        let fake = FakeAppUpdater()
        delegate.updaterFactory = { fake }
        #expect(delegate.updaterFactory() === fake)
    }
}

@Suite("Automatic update checks")
struct AutomaticUpdateChecksTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "matchday-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aFreshInstallDoesNotCheckAutomatically() {
        #expect(!AutomaticUpdateChecks(defaults: makeDefaults()).isEnabled)
    }

    @Test func theAnswerPersistsUnderItsKey() {
        let defaults = makeDefaults()
        AutomaticUpdateChecks(defaults: defaults).isEnabled = true
        #expect(defaults.bool(forKey: "updates.automaticChecksEnabled"))
        #expect(AutomaticUpdateChecks(defaults: defaults).isEnabled)
        AutomaticUpdateChecks(defaults: defaults).isEnabled = false
        #expect(!AutomaticUpdateChecks(defaults: defaults).isEnabled)
    }
}

@Suite("Update check presentation")
struct UpdateCheckPresentationTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func neverCheckedSaysSoWithoutADate() {
        #expect(UpdateCheckPresentation(lastCheck: nil, now: now).label == "Never checked")
    }

    @Test func aRecordedCheckReadsRelativeToNow() {
        let label = UpdateCheckPresentation(lastCheck: now.addingTimeInterval(-2 * 3600), now: now,
                                            locale: Locale(identifier: "en_US")).label
        #expect(label == "Last checked 2 hours ago")
    }
}

@Suite("Bundle update keys")
struct BundleUpdateKeysTests {
    /// Reads the built app (the test host), so it fails if the partial Info.plist was not merged.
    @Test func theBundleCarriesTheFeedAndThePublicKey() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["SUFeedURL"] as? String == "https://juancasanueva.github.io/SWIFTUI_matchday/appcast.xml")
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        #expect(info["LSUIElement"] as? Bool == true)
    }

    /// The Updates card promises a daily check; the bundle states it rather
    /// than leaning on Sparkle's default.
    @Test func theBundleChecksOnceADay() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86_400)
    }

    @Test func automaticChecksAreNotEnabledByTheBundle() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["SUEnableAutomaticChecks"] == nil)
        #expect(info["SUAutomaticallyUpdate"] == nil)
    }

    /// The framework stays behind one adapter.
    @Test func onlyTheAdapterImportsSparkle() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "matchday")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let importing = try files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("import Sparkle") }
            .map(\.lastPathComponent)
        #expect(importing == ["SparkleUpdateChecker.swift"])
    }
}
