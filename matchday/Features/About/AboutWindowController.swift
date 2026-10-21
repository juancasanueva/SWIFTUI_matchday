//
//  AboutWindowController.swift
//  matchday
//
//  Owns the single "About Matchday" window. It is created on the first
//  `show()` and kept (`isReleasedWhenClosed = false`), so closing hides it
//  and the next `show()` brings the same window back.
//

import AppKit
import SwiftUI

final class AboutWindowController {
    private let info: AboutInfo
    private var window: NSWindow?

    init(info: AboutInfo) {
        self.info = info
    }

    /// Brings the app forward and the window to the front. An `LSUIElement`
    /// app is not active when the user picks About, and an inactive app's
    /// window would open behind the frontmost one.
    ///
    /// `appearance` follows the panel's Appearance setting; `nil` follows the
    /// system. Theme's dynamic colors resolve against it.
    func show(appearance: NSAppearance? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        window.appearance = appearance
        if !window.isVisible { window.center() }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // `activate()` is cooperative and can be declined while another app is
        // in use; the window still comes to the front.
        window.orderFrontRegardless()
    }

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    /// Sizes the content from the hosted view: a hosting controller never sets
    /// `preferredContentSize` on its own, so a window built with
    /// `contentRect: .zero` would keep a zero-sized content area.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "About \(info.appName)"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Theme.background)

        let hosting = NSHostingController(rootView: AboutRootView(info: info))
        window.contentViewController = hosting
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(CGSize(width: AboutView.width, height: hosting.view.fittingSize.height))
        return window
    }
}
