//
//  StatusMenuController.swift
//  Beacon
//
//  Provides a menu bar status item for quick Busylight control.
//

import Cocoa
import ServiceManagement

final class StatusMenuController: NSObject {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var connectionItem: NSMenuItem!

    /// Callback invoked when the user selects "Open Controller Window".
    var onOpenWindow: (() -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "light.max", accessibilityDescription: "Beacon")
        }

        buildMenu()
        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            self, selector: #selector(connectionChanged),
            name: .busylightConnectionChanged, object: nil
        )
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.removeAllItems()

        // Connection status
        connectionItem = NSMenuItem(title: "No Busylight Connected", action: nil, keyEquivalent: "")
        connectionItem.isEnabled = false
        menu.addItem(connectionItem)
        updateConnectionStatus()

        menu.addItem(.separator())

        // Open window
        let openItem = NSMenuItem(title: "Open Controller…", action: #selector(openWindow), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // Power
        let onItem = NSMenuItem(title: "Turn On", action: #selector(turnOn), keyEquivalent: "")
        onItem.target = self
        menu.addItem(onItem)

        let offItem = NSMenuItem(title: "Turn Off", action: #selector(turnOff), keyEquivalent: "")
        offItem.target = self
        menu.addItem(offItem)

        menu.addItem(.separator())

        // Color submenu
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colorSubmenu = NSMenu()
        let colors: [(String, UInt8, UInt8, UInt8)] = [
            ("Red",    100,   0,   0),
            ("Orange", 100,  40,   0),
            ("Yellow", 100, 100,   0),
            ("Green",    0, 100,   0),
            ("Cyan",     0, 100, 100),
            ("Blue",     0,   0, 100),
            ("Purple",  60,   0, 100),
            ("Pink",   100,   0,  60),
            ("White",  100, 100, 100),
        ]
        for (index, color) in colors.enumerated() {
            let item = NSMenuItem(title: color.0, action: #selector(setColor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            colorSubmenu.addItem(item)
        }
        colorItem.submenu = colorSubmenu
        menu.addItem(colorItem)

        // Effect submenu
        let effectItem = NSMenuItem(title: "Effect", action: nil, keyEquivalent: "")
        let effectSubmenu = NSMenu()
        for (index, effect) in BusylightEffect.allCases.enumerated() {
            let item = NSMenuItem(title: effect.rawValue, action: #selector(setEffect(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            effectSubmenu.addItem(item)
        }
        effectItem.submenu = effectSubmenu
        menu.addItem(effectItem)

        // Sound submenu
        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        let soundSubmenu = NSMenu()
        for (index, tone) in BusylightTone.allCases.enumerated() {
            let item = NSMenuItem(title: tone.rawValue, action: #selector(startSound(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            soundSubmenu.addItem(item)
        }
        soundSubmenu.addItem(.separator())
        let stopSoundItem = NSMenuItem(title: "Stop Sound", action: #selector(stopSound), keyEquivalent: "")
        stopSoundItem.target = self
        soundSubmenu.addItem(stopSoundItem)
        soundItem.submenu = soundSubmenu
        menu.addItem(soundItem)

        menu.addItem(.separator())

        // HTTP server toggle
        let httpItem = NSMenuItem(title: "Enable HTTP Control", action: #selector(toggleHTTPServer(_:)), keyEquivalent: "")
        httpItem.target = self
        httpItem.state = UserDefaults.standard.bool(forKey: "httpServerEnabled") ? .on : .off
        menu.addItem(httpItem)

        // Start at Login
        let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Beacon", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Connection

    @objc private func connectionChanged() {
        updateConnectionStatus()
    }

    private func updateConnectionStatus() {
        let connected = BusylightController.shared.isConnected
        connectionItem?.title = connected ? "Busylight Connected" : "No Busylight Connected"

        if let button = statusItem?.button {
            let symbolName = connected ? "light.max" : "light.slash"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Beacon")
        }
    }

    // MARK: - Color data

    private let colorValues: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (100,   0,   0),   // Red
        (100,  40,   0),   // Orange
        (100, 100,   0),   // Yellow
        (  0, 100,   0),   // Green
        (  0, 100, 100),   // Cyan
        (  0,   0, 100),   // Blue
        ( 60,   0, 100),   // Purple
        (100,   0,  60),   // Pink
        (100, 100, 100),   // White
    ]

    // MARK: - Actions

    @objc private func openWindow() {
        onOpenWindow?()
    }

    @objc private func turnOn() {
        BusylightController.shared.turnOn()
    }

    @objc private func turnOff() {
        BusylightController.shared.turnOff()
    }

    @objc private func setColor(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < colorValues.count else { return }
        let c = colorValues[index]
        BusylightController.shared.setColor(red: c.r, green: c.g, blue: c.b)
    }

    @objc private func setEffect(_ sender: NSMenuItem) {
        let effects = BusylightEffect.allCases
        let index = sender.tag
        guard index >= 0, index < effects.count else { return }
        BusylightController.shared.setEffect(effects[index])
    }

    @objc private func startSound(_ sender: NSMenuItem) {
        let tones = BusylightTone.allCases
        let index = sender.tag
        guard index >= 0, index < tones.count else { return }
        BusylightController.shared.playSound(tones[index], duration: 5)
    }

    @objc private func stopSound() {
        BusylightController.shared.stopSound()
    }

    @objc private func toggleHTTPServer(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        sender.state = enabled ? .on : .off
        UserDefaults.standard.set(enabled, forKey: "httpServerEnabled")
        NotificationCenter.default.post(name: .httpServerToggled, object: nil)
    }

    @objc private func toggleStartAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
            sender.state = .off
        } else {
            try? service.register()
            sender.state = (service.status == .enabled) ? .on : .off
        }
    }

    @objc private func quit() {
        BusylightController.shared.turnOff()
        NSApp.terminate(nil)
    }
}
