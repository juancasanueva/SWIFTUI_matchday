//
//  AboutWindowController.swift
//  matchday
//
//  Owns the single "About Matchday" window. It is created on the first
//  `show()` and kept (`isReleasedWhenClosed = false`), so closing hides it
//  and the next `show()` brings the same window back. Its content and its
//  title follow the app language live, even while the window is open.
//

import AppKit
import SwiftUI

final class AboutWindowController {
    private let info: AboutInfo
    /// Supplies the app language to the hosted view.
    private let store: MatchdayStore
    /// The bundle carrying the `.lproj` folders the title is looked up in.
    private let base: Bundle
    private var window: NSWindow?
    private var languageObserver: LanguageObserver?
    private var title = ""

    init(info: AboutInfo, store: MatchdayStore, base: Bundle = .main) {
        self.info = info
        self.store = store
        self.base = base
        languageObserver = LanguageObserver(store: store) { [weak self] language, locale in
            self?.retitle(language: language, locale: locale)
        }
    }

    /// Brings the app forward and the window to the front. An `LSUIElement`
    /// app is not active when the user picks About, and an inactive app's
    /// window would open behind the frontmost one.
    ///
    /// `appearance` follows the panel's Appearance setting; `nil` follows the
    /// system. Theme's dynamic colors resolve against it.
    func show(appearance: NSAppearance? = nil) {
        let window = loadWindow()
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

    var windowTitle: String? {
        window?.title
    }

    /// The window, built on first use, without showing it.
    @discardableResult
    func loadWindow() -> NSWindow {
        if let window { return window }
        let window = makeWindow()
        window.title = title
        self.window = window
        return window
    }

    /// The title is built outside SwiftUI, so it is set again on every language change.
    private func retitle(language: AppLanguage, locale: Locale) {
        title = String(appLocalized: "About \(info.appName)", bundle: AppLocalization.bundle(for: language, in: base),
                       locale: locale, comment: "Title of the About window. The argument is the app name.")
        window?.title = title
    }

    /// Sizes the content from the hosted view: a hosting controller never sets
    /// `preferredContentSize` on its own, so a window built with
    /// `contentRect: .zero` would keep a zero-sized content area.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Theme.background)

        let hosting = NSHostingController(
            rootView: AppLocaleRoot { AboutRootView(info: info) }
                .environment(store)
        )
        window.contentViewController = hosting
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(CGSize(width: AboutView.width, height: hosting.view.fittingSize.height))
        return window
    }
}
