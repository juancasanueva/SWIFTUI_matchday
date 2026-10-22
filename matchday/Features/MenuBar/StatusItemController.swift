//
//  StatusItemController.swift
//  matchday
//
//  Owns the `NSStatusItem` and the popover with the panel. The button shows
//  the store's bar state (`StatusItemLook`) and is redrawn whenever the store
//  changes it; the only timer is the live dot's pulse.
//
//  A left click toggles the popover; a right click shows the context menu
//  (`ContextMenuModel`).
//
//  It is an `NSObject` subclass because AppKit needs one: the button and the
//  menu items use target-action and the popover reports its transitions
//  through `NSPopoverDelegate`.
//

import AppKit
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    /// Pulse half-period of the live dot.
    static let pulseInterval: Duration = .milliseconds(800)

    private let store: MatchdayStore
    private let presentation: PanelPresentation
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let openAbout: () -> Void
    /// `nil` in the unit-test host; the menu item is then disabled.
    private let updater: (any AppUpdating)?

    private var look: StatusItemLook?
    private var pulseDimmed = false
    private var pulseTask: Task<Void, Never>?
    private var reduceMotionObserver: (any NSObjectProtocol)?
    private var languageObserver: LanguageObserver?

    init(store: MatchdayStore, launchAtLogin: LaunchAtLogin, updater: (any AppUpdating)?,
         openAbout: @escaping () -> Void) {
        self.store = store
        self.updater = updater
        self.openAbout = openAbout
        presentation = PanelPresentation()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover(launchAtLogin: launchAtLogin)
        observeBar()
        observeAppearance()
        observeLanguage()
        // Turning Reduce Motion on stops the pulse at once.
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    isolated deinit {
        pulseTask?.cancel()
        if let reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Whether the panel is on screen.
    var isPanelOpen: Bool {
        popover.isShown
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover(launchAtLogin: LaunchAtLogin) {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: Theme.panelWidth, height: Theme.panelHeight)
        presentation.onClose = { [weak self] in self?.popover.performClose(nil) }
        presentation.onOpenAbout = openAbout
        // Hosted for the controller's whole life, so tab and chip selections
        // survive closing the panel.
        popover.contentViewController = NSHostingController(
            rootView: AppLocaleRoot { PanelView() }
                .environment(store)
                .environment(launchAtLogin)
                .environment(presentation)
                .environment(\.appUpdater, updater)
        )
    }

    // MARK: - Status item

    /// Renders the bar state and re-arms itself for the next change to it.
    private func observeBar() {
        let bar = withObservationTracking {
            store.bar
        } onChange: { [weak self] in
            // Called before the change lands; read the new value on the next turn.
            Task { @MainActor in self?.observeBar() }
        }
        render(bar: bar)
    }

    // MARK: - Appearance

    /// Themes the panel only; the status item keeps following the menu bar.
    /// Theme's dynamic colors resolve against the popover's appearance.
    private func observeAppearance() {
        let mode = withObservationTracking {
            store.settings.appearance
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAppearance() }
        }
        // Any settings change re-arms this; only an actual switch re-themes.
        let appearance = PanelAppearance.appearance(for: mode)
        guard popover.appearance?.name != appearance?.name else { return }
        popover.appearance = appearance
    }

    // MARK: - Language

    /// Points the language bundle (strings built outside SwiftUI) at the
    /// effective language on launch and on every change. The SwiftUI roots
    /// follow the store through `AppLocaleRoot`.
    private func observeLanguage() {
        languageObserver = LanguageObserver(store: store) { [weak self] language, locale in
            AppLocalization.shared.apply(language, locale: locale)
            // The bar title and tooltip are built outside SwiftUI; redraw them in the new language.
            if self?.look != nil { self?.render() }
        }
    }

    private func render(bar: BarState? = nil) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let newLook = StatusItemLook(bar: bar ?? store.bar, reduceMotion: reduceMotion)
        if newLook.pulses != look?.pulses {
            restartPulse(newLook.pulses)
        }
        look = newLook
        draw()
    }

    private func draw() {
        guard let look, let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(dot: look.dot, dimmed: look.isDimmed,
                                         dotOpacity: look.dotOpacity(pulseDimmed: pulseDimmed))
        button.title = look.title
        button.toolTip = look.tooltip
        button.setAccessibilityLabel(look.accessibilityLabel)
    }

    private func restartPulse(_ pulses: Bool) {
        pulseTask?.cancel()
        pulseTask = nil
        pulseDimmed = false
        guard pulses else { return }
        pulseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pulseInterval)
                guard let self, !Task.isCancelled else { return }
                pulseDimmed.toggle()
                draw()
            }
        }
    }

    // MARK: - Popover

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    /// Closes the popover while it is shown instead of showing it again.
    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else if presentation.shouldOpen() {
            // An `LSUIElement` app is not active, and the panel needs key
            // status for its keyboard shortcuts.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Refreshes and focuses the panel on every open (Panel.qml:375).
    func popoverWillShow(_ notification: Notification) {
        Task { await store.refreshNow() }
    }

    /// Focus goes to the panel only once its window is key.
    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeKey()
        presentation.didOpen()
    }

    /// Also fires when the transient popover closes from a click outside it.
    func popoverDidClose(_ notification: Notification) {
        presentation.didClose()
    }

    // MARK: - Context menu

    /// Attaches the menu, triggers the button, then detaches it, so the next
    /// left click reaches `handleClick` instead of opening the menu.
    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        statusItem.menu = makeContextMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in ContextMenuModel.entries(canCheckForUpdates: updater?.canCheckForUpdates ?? false) {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .item(item):
                let menuItem = NSMenuItem(title: item.title, action: #selector(performMenuAction(_:)),
                                          keyEquivalent: item.keyEquivalent)
                menuItem.target = self
                menuItem.representedObject = item.action
                menuItem.isEnabled = item.isEnabled
                menu.addItem(menuItem)
            }
        }
        return menu
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ContextMenuItem.Action else { return }
        switch action {
        case .openAbout: openAbout()
        case .checkForUpdates: handleCheckForUpdates()
        case .refresh: Task { await store.refreshNow() }
        case .quit: NSApp.terminate(nil)
        }
    }

    /// Sparkle shows its own window, so the panel gets out of the way first.
    private func handleCheckForUpdates() {
        if popover.isShown { popover.performClose(nil) }
        updater?.checkForUpdates()
    }
}
