//
//  SparkleUpdateChecker.swift
//  matchday
//
//  `AppUpdating` backed by Sparkle — the only file that imports it. The feed
//  URL and the EdDSA public key come from the bundle's Info.plist
//  (`Resources/Matchday-Info.plist`) and cannot be changed at run time.
//

import Foundation
import Observation
import Sparkle

@Observable
final class SparkleUpdateChecker: AppUpdating {
    private(set) var canCheckForUpdates: Bool
    private(set) var lastUpdateCheckDate: Date?

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let automaticChecks: AutomaticUpdateChecks
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastCheckObservation: NSKeyValueObservation?

    /// Applies the app's preference before starting the updater, so Sparkle
    /// never asks on its own whether to check automatically.
    init(automaticChecks: AutomaticUpdateChecks) {
        self.automaticChecks = automaticChecks
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
        self.lastUpdateCheckDate = self.controller.updater.lastUpdateCheckDate

        AutomaticUpdateChecksPolicy.apply(preference: automaticChecks.isEnabled, to: self)
        controller.startUpdater()
        observeUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return automaticChecks.isEnabled
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
                automaticChecks.isEnabled = newValue
            }
        }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Sparkle changes both values on the main thread, so `assumeIsolated` holds.
    private func observeUpdater() {
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
            }
        }
        lastCheckObservation = controller.updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastUpdateCheckDate = self.controller.updater.lastUpdateCheckDate
            }
        }
    }
}
