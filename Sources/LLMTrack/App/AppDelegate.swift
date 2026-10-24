import Cocoa
import SwiftUI

public final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    public override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil so mouse clicks pass straight through to NSStatusBarButton
        return nil
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = LLMTrackStore()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent app from quitting when popover closes
        NSApp.setActivationPolicy(.accessory)

        // Setup Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let tileView = MenuBarTileView(store: store)
            let hostingView = ClickThroughHostingView(rootView: tileView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)

            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }

        // Setup Popover
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverHUDView(store: store))
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right-click: quick context menu (Refresh / Quit)
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Refresh Telemetry", action: #selector(refreshNow), keyEquivalent: "r"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit LLM Track", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil // Reset so left click still opens popover
        } else {
            togglePopover()
        }
    }

    @objc public func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func refreshNow() {
        store.refresh()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
