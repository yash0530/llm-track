import Cocoa
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = LLMTrackStore()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run purely as menu bar accessory (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Single clean native menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14.0, weight: .regular)
            if let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "LLM Track")?.withSymbolConfiguration(symbolConfig) {
                image.isTemplate = true
                button.image = image
            }
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Setup Popover with transient behavior (dismisses on click outside)
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverHUDView(store: store))
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Refresh Telemetry", action: #selector(refreshNow), keyEquivalent: "r"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit LLM Track", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
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
