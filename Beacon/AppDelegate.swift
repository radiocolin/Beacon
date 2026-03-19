//
//  AppDelegate.swift
//  Beacon
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: MainWindowController?
    private let statusMenuController = StatusMenuController()
    private let httpServer = BeaconHTTPServer()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Hide the dock icon — this is a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Build the main menu bar (required when not using a storyboard)
        buildMainMenu()

        // Kick-start HID device discovery
        _ = BusylightController.shared

        // Set up the menu-bar item
        statusMenuController.onOpenWindow = { [weak self] in
            self?.showWindow()
        }
        statusMenuController.setup()

        // Start HTTP server if previously enabled
        if UserDefaults.standard.bool(forKey: "httpServerEnabled") {
            httpServer.start()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(httpServerToggled),
            name: .httpServerToggled, object: nil
        )
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        httpServer.stop()
        BusylightController.shared.turnOff()
    }

    @objc private func httpServerToggled() {
        let enabled = UserDefaults.standard.bool(forKey: "httpServerEnabled")
        if enabled {
            httpServer.start()
        } else {
            httpServer.stop()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        }
        return true
    }

    // MARK: - Main Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(NSMenuItem(title: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Helpers

    private func showWindow() {
        // Temporarily become a regular app so the window can receive focus
        NSApp.setActivationPolicy(.regular)

        if windowController == nil {
            windowController = MainWindowController()
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Watch for window close to go back to accessory mode
        if let window = windowController?.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidClose(_:)),
                name: NSWindow.willCloseNotification, object: window
            )
        }
    }

    @objc private func windowDidClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: notification.object)
        // Hide from dock again once the window is closed
        NSApp.setActivationPolicy(.accessory)
    }
}
