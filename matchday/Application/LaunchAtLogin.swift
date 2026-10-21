//
//  LaunchAtLogin.swift
//  matchday
//
//  The "Launch at login" setting. The system owns it (a login item), so it is
//  read back from the service instead of being stored in `AppSettings`.
//

import Foundation
import Observation

nonisolated enum LoginItemStatus: Sendable, Hashable {
    case enabled
    case disabled
    /// Registered, but the user still has to allow it in System Settings › Login Items.
    case requiresApproval
    /// The system cannot find the app to register (e.g. run from a temporary build folder).
    case notFound
}

/// Port for the app's login item. The `SMAppService` adapter lives in `Data/System`.
protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

@Observable
@MainActor
final class LaunchAtLogin {
    private(set) var status: LoginItemStatus
    /// Why the last change failed; cleared by the next successful one.
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: any LoginItemService

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    /// On once registered, even while waiting for the user's approval.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't turn \(enabled ? "on" : "off") launch at login: \(error.localizedDescription)"
        }
        status = service.status
    }

    /// Re-reads the status, which the user can change in System Settings at any time.
    func refreshStatus() {
        status = service.status
    }
}
