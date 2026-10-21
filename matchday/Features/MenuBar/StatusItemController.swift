//
//  StatusItemController.swift
//  matchday
//
//  Owns the `NSStatusItem` and the popover with the panel. The button shows
//  the store's bar state (`StatusItemLook`) and is redrawn whenever the store
//  changes it; the only timer is the live dot's pulse.
//
//  It is an `NSObject` subclass because AppKit needs one: the button uses
//  target-action and the popover reports its transitions through
//  `NSPopoverDelegate`.
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

    private var look: StatusItemLook?
    private var pulseDimmed = false
    private var pulseTask: Task<Void, Never>?
    private var reduceMotionObserver: (any NSObjectProtocol)?

    init(store: MatchdayStore, launchAtLogin: LaunchAtLogin) {
        self.store = store
        presentation = PanelPresentation()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover(launchAtLogin: launchAtLogin)
        observeBar()
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
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePopover(launchAtLogin: LaunchAtLogin) {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: Theme.panelWidth, height: Theme.panelHeight)
        presentation.onClose = { [weak self] in self?.popover.performClose(nil) }
        // Hosted for the controller's whole life, so tab and chip selections
        // survive closing the panel.
        popover.contentViewController = NSHostingController(
            rootView: PanelView()
                .environment(store)
                .environment(launchAtLogin)
                .environment(presentation)
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
        togglePopover()
    }

    /// Closes the popover while it is shown instead of showing it again.
    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // An `LSUIElement` app is not active, and the panel needs key
            // status for its keyboard shortcuts.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Refreshes and focuses the panel on every open (Panel.qml:375).
    func popoverWillShow(_ notification: Notification) {
        presentation.didOpen()
        Task { await store.refreshNow() }
    }

    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeKey()
    }
}
