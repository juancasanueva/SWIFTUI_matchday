//
//  FakeAppUpdater.swift
//  matchdayTests
//

import Foundation
import Observation
@testable import matchday

/// In-memory updater that counts checks and writes and never reaches the network.
@MainActor
@Observable
final class FakeAppUpdater: AppUpdating {
    var canCheckForUpdates: Bool
    private(set) var lastUpdateCheckDate: Date?
    private(set) var checkCount = 0
    /// How many times the automatic flag was written, not just its final value.
    @ObservationIgnored private(set) var automaticWriteCount = 0
    @ObservationIgnored private var storedAutomaticChecks: Bool

    var automaticallyChecksForUpdates: Bool {
        get { storedAutomaticChecks }
        set {
            storedAutomaticChecks = newValue
            automaticWriteCount += 1
        }
    }

    init(canCheckForUpdates: Bool = true, automaticallyChecksForUpdates: Bool = false) {
        self.canCheckForUpdates = canCheckForUpdates
        storedAutomaticChecks = automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        checkCount += 1
    }

    func recordCheck(at date: Date) {
        lastUpdateCheckDate = date
    }
}
