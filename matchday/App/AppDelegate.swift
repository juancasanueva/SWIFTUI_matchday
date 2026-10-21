//
//  AppDelegate.swift
//  matchday
//
//  Builds the environment, the status item and the About window once the
//  app has launched, and holds them for the life of the process.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment?
    private(set) var statusItemController: StatusItemController?
    /// The one About window, shared by the context menu and Settings.
    private(set) var aboutWindow: AboutWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        statusItemController = StatusItemController(
            store: store,
            launchAtLogin: environment.launchAtLogin,
            openAbout: { [aboutWindow, store] in
                aboutWindow.show(appearance: PanelAppearance.appearance(for: store.settings.appearance))
            }
        )
    }
}
