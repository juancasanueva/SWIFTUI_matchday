//
//  Eventually.swift
//  matchdayTests
//

import Foundation

/// Waits on the main actor until `condition` holds or `timeout` passes, checking
/// every few milliseconds. Asynchronous follow-ups (observation re-arming on a
/// later turn) are awaited by their outcome, not by a guessed number of yields,
/// so they stay deterministic under load. The caller still `#expect`s afterwards.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
