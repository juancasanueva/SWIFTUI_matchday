//
//  PanelPresentation.swift
//  matchday
//
//  The bridge between the popover that hosts the panel and the panel itself:
//  the panel view lives for the app's whole life, so `onAppear` does not run
//  per open. It tracks whether the popover is open and closes it on Esc.
//

import Foundation
import Observation

@Observable
final class PanelPresentation {
    /// A click on the status item within this interval of a close is the same
    /// click that closed the transient popover, not a request to reopen it.
    static let reopenGuard: TimeInterval = 0.3

    /// True between the popover becoming key and closing; the panel takes
    /// keyboard focus when it turns true, and drops it on close so the next
    /// open always registers as a change.
    private(set) var isOpen = false

    @ObservationIgnored private var lastClosedAt: Date?

    /// Closes the popover, set by its owner.
    @ObservationIgnored var onClose: () -> Void = {}

    func didOpen() {
        isOpen = true
    }

    func didClose(at date: Date = .now) {
        isOpen = false
        lastClosedAt = date
    }

    /// Whether a status item click at `date` should open the panel.
    func shouldOpen(at date: Date = .now) -> Bool {
        guard let lastClosedAt else { return true }
        return date.timeIntervalSince(lastClosedAt) >= Self.reopenGuard
    }

    func close() {
        onClose()
    }
}
