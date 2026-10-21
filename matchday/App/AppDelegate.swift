//
//  AppDelegate.swift
//  matchday
//
//  Builds the environment, the updater, the status item and the About window
//  once the app has launched, and holds them for the life of the process.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment?
    private(set) var statusItemController: StatusItemController?
    /// The one About window, shared by the context menu and Settings.
    private(set) var aboutWindow: AboutWindowController?
    /// The one updater, shared by the context menu and Settings; `nil` in the
    /// unit-test host, where Sparkle must never start.
    private(set) var updater: (any AppUpdating)?

    /// How the updater is built; tests substitute an in-memory one.
    var updaterFactory: @MainActor () -> any AppUpdating = {
        SparkleUpdateChecker(automaticChecks: AutomaticUpdateChecks(defaults: .standard))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before the store loads the settings; never in the unit-test host.
        if !AppEnvironment.isHostingTests {
            SandboxContainerMigration.live().run()
        }
        let environment = AppEnvironment()
        self.environment = environment
        // The unit-test host gets neither polling nor a status item.
        guard !AppEnvironment.isHostingTests else { return }
        environment.start()
        let aboutWindow = AboutWindowController(
            info: AboutModel.info(bundleInfo: Bundle.main.infoDictionary ?? [:])
        )
        self.aboutWindow = aboutWindow
        let store = environment.store
        let updater = updaterFactory()
        self.updater = updater
        statusItemController = StatusItemController(
            store: store,
            launchAtLogin: environment.launchAtLogin,
            updater: updater,
            openAbout: { [aboutWindow, store] in
                aboutWindow.show(appearance: PanelAppearance.appearance(for: store.settings.appearance))
            }
        )
    }
}
