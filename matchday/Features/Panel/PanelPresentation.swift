//
//  PanelPresentation.swift
//  matchday
//
//  The bridge between the popover that hosts the panel and the panel itself:
//  the panel view lives for the app's whole life, so `onAppear` does not run
//  per open. It counts opens instead and closes the popover on Esc.
//

import Observation

@Observable
final class PanelPresentation {
    /// Bumped every time the popover opens; the panel takes keyboard focus
    /// when it changes.
    private(set) var openCount = 0

    /// Closes the popover, set by its owner.
    @ObservationIgnored var onClose: () -> Void = {}

    func didOpen() {
        openCount += 1
    }

    func close() {
        onClose()
    }
}
