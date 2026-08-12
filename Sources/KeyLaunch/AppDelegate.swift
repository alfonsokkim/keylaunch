import Cocoa
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "KeyLaunch")
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = buildMenu()

        if !KeyTap.shared.start() {
            requestAccessibility()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)
        // Poll until granted; the tap can only be created once we are trusted.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if KeyTap.shared.start() { timer.invalidate() }
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.title = "KeyLaunch"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Leaving learn mode armed after closing would swallow the next keypress.
        Store.shared.learningID = nil
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let active = Store.shared.mappings.filter { $0.isComplete }
        if active.isEmpty {
            let item = NSMenuItem(title: "No shortcuts set", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for mapping in active {
                let title = "\(mapping.trigger?.label ?? "")  →  \(mapping.appName ?? "")"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                if let url = mapping.appURL {
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))

        let launch = NSMenuItem(
            title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)

        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(title: "⚠︎ Needs Accessibility access", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = item.action == #selector(NSApp.terminate(_:)) ? nil : self
        }
    }
}
