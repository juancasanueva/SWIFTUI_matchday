//
//  LaunchAtLoginTests.swift
//  matchdayTests
//

import Foundation
import Testing
@testable import matchday

/// Login item that records calls and can be told to fail.
final class FakeLoginItem: LoginItemService, @unchecked Sendable {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    var status: LoginItemStatus
    var fails = false
    /// Status the system reports after a successful register (e.g. `.requiresApproval`).
    var statusAfterRegister: LoginItemStatus = .enabled
    private(set) var calls: [String] = []

    init(status: LoginItemStatus = .disabled) {
        self.status = status
    }

    func register() throws {
        calls.append("register")
        if fails { throw Failure() }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        if fails { throw Failure() }
        status = .disabled
    }
}

@MainActor
@Suite("Launch at login")
struct LaunchAtLoginTests {
    @Test func reflectsTheSystemStatus() {
        #expect(LaunchAtLogin(service: FakeLoginItem(status: .enabled)).isEnabled)
        #expect(!LaunchAtLogin(service: FakeLoginItem(status: .disabled)).isEnabled)
    }

    @Test func turningOnRegistersAndOffUnregisters() {
        let item = FakeLoginItem()
        let model = LaunchAtLogin(service: item)
        model.setEnabled(true)
        #expect(model.isEnabled)
        model.setEnabled(false)
        #expect(!model.isEnabled)
        #expect(item.calls == ["register", "unregister"])
        #expect(model.errorMessage == nil)
    }

    @Test func pendingApprovalCountsAsOnAndExplainsItself() {
        let item = FakeLoginItem()
        item.statusAfterRegister = .requiresApproval
        let model = LaunchAtLogin(service: item)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.needsApproval)
    }

    @Test func failuresKeepTheRealStatusAndReportAnError() {
        let item = FakeLoginItem()
        item.fails = true
        let model = LaunchAtLogin(service: item)
        model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.errorMessage == "Couldn't turn on launch at login: Operation not permitted")

        item.fails = false
        model.setEnabled(true)
        #expect(model.errorMessage == nil)
    }
}
