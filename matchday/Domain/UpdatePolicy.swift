//
//  UpdatePolicy.swift
//  matchday
//
//  The two update decisions, kept free of Sparkle so tests can drive them.
//

/// What the app writes to the updater at launch.
@MainActor
enum AutomaticUpdateChecksPolicy {
    /// Writes the preference unconditionally, so a value Sparkle persisted on
    /// its own is overwritten rather than trusted.
    static func apply(preference: Bool, to updater: any AppUpdating) {
        updater.automaticallyChecksForUpdates = preference
    }
}

/// Whether "Check for Updates…" is live: an explicit request is its own
/// consent, so only a check already in flight disables it.
nonisolated enum UpdateCommandEnablement {
    static func isEnabled(canCheckForUpdates: Bool) -> Bool {
        canCheckForUpdates
    }
}
