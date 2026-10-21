//
//  AppDelegate.swift
//  matchday
//
//  Builds the environment and the status item once the app has launched,
//  and holds both for the life of the process.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment?
    private(set) var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        self.environment = environment
        // The unit-test host gets neither polling nor a status item.
        guard !AppEnvironment.isHostingTests else { return }
        environment.start()
        statusItemController = StatusItemController(store: environment.store,
                                                    launchAtLogin: environment.launchAtLogin)
    }
}
