//
//  MainWindowController.swift
//  Beacon
//
//  Programmatic AppKit UI for controlling the Busylight.
//

import Cocoa
import ServiceManagement

final class MainWindowController: NSWindowController {

    // MARK: - Controls

    private let colorWell = NSColorWell()
    private let brightnessSlider = NSSlider()
    private let effectSegment = NSSegmentedControl()
    private let bpmSlider = NSSlider()
    private let tonePopUp = NSPopUpButton()
    private let volumeSlider = NSSlider()
    private let toneLengthSlider = NSSlider()
    private let toneLengthValueLabel = NSTextField(labelWithString: "5s")
    private let playButton = NSButton()
    private let stopSoundButton = NSButton()
    private let loginCheckbox = NSButton()
    private let httpCheckbox = NSButton()
    private let turnOnButton = NSButton()
    private let turnOffButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "No Busylight Connected")

    private let brightnessValueLabel = NSTextField(labelWithString: "100")
    private let bpmValueLabel = NSTextField(labelWithString: "120 BPM")
    private let volumeValueLabel = NSTextField(labelWithString: "4")

    /// Guard flag to prevent feedback loops when syncing UI from controller state.
    private var isUpdatingFromState = false

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Beacon"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .automatic

        self.init(window: window)
        buildUI()
        updateConnectionState()

        NotificationCenter.default.addObserver(
            self, selector: #selector(connectionChanged),
            name: .busylightConnectionChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged),
            name: .busylightStateChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(httpServerSettingChanged),
            name: .httpServerToggled, object: nil
        )
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])

        // -- Status --
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel)

        // -- Color section --
        stack.addArrangedSubview(fullWidthSeparator())
        stack.addArrangedSubview(sectionLabel("Color"))

        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.spacing = 12
        colorRow.alignment = .centerY

        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true
        colorWell.color = .red
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorRow.addArrangedSubview(colorWell)

        let brightnessLabel = NSTextField(labelWithString: "Brightness")
        brightnessLabel.font = .systemFont(ofSize: 12)
        brightnessLabel.textColor = .secondaryLabelColor
        colorRow.addArrangedSubview(brightnessLabel)

        brightnessSlider.minValue = 0
        brightnessSlider.maxValue = 100
        brightnessSlider.integerValue = 100
        brightnessSlider.isContinuous = true
        brightnessSlider.target = self
        brightnessSlider.action = #selector(colorChanged)
        brightnessSlider.translatesAutoresizingMaskIntoConstraints = false
        brightnessSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        colorRow.addArrangedSubview(brightnessSlider)

        brightnessValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        brightnessValueLabel.textColor = .secondaryLabelColor
        brightnessValueLabel.alignment = .right
        brightnessValueLabel.translatesAutoresizingMaskIntoConstraints = false
        brightnessValueLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true
        colorRow.addArrangedSubview(brightnessValueLabel)

        stack.addArrangedSubview(colorRow)

        // -- Effect section --
        stack.addArrangedSubview(fullWidthSeparator())
        stack.addArrangedSubview(sectionLabel("Effect"))

        effectSegment.segmentCount = 3
        effectSegment.setLabel("Solid", forSegment: 0)
        effectSegment.setLabel("Blink", forSegment: 1)
        effectSegment.setLabel("Pulse", forSegment: 2)
        effectSegment.segmentStyle = .automatic
        effectSegment.trackingMode = .selectOne
        effectSegment.selectedSegment = 0
        effectSegment.target = self
        effectSegment.action = #selector(effectChanged)
        stack.addArrangedSubview(effectSegment)

        let bpmRow = NSStackView()
        bpmRow.orientation = .horizontal
        bpmRow.spacing = 8
        bpmRow.alignment = .centerY

        let speedLabel = NSTextField(labelWithString: "Speed")
        speedLabel.font = .systemFont(ofSize: 12)
        speedLabel.textColor = .secondaryLabelColor
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        bpmRow.addArrangedSubview(speedLabel)

        bpmSlider.minValue = 10
        bpmSlider.maxValue = 600
        bpmSlider.doubleValue = 120
        bpmSlider.isContinuous = true
        bpmSlider.target = self
        bpmSlider.action = #selector(bpmChanged)
        bpmSlider.translatesAutoresizingMaskIntoConstraints = false
        bpmSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        bpmRow.addArrangedSubview(bpmSlider)

        bpmValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        bpmValueLabel.textColor = .secondaryLabelColor
        bpmValueLabel.alignment = .right
        bpmValueLabel.translatesAutoresizingMaskIntoConstraints = false
        bpmValueLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
        bpmRow.addArrangedSubview(bpmValueLabel)

        stack.addArrangedSubview(bpmRow)

        // Start with BPM disabled (Solid selected)
        bpmSlider.isEnabled = false
        bpmValueLabel.textColor = .tertiaryLabelColor

        // -- Sound section --
        stack.addArrangedSubview(fullWidthSeparator())
        stack.addArrangedSubview(sectionLabel("Sound"))

        tonePopUp.removeAllItems()
        for tone in BusylightTone.allCases {
            tonePopUp.addItem(withTitle: tone.rawValue)
        }
        stack.addArrangedSubview(tonePopUp)

        let volumeRow = NSStackView()
        volumeRow.orientation = .horizontal
        volumeRow.spacing = 8
        volumeRow.alignment = .centerY

        let volumeLabel = NSTextField(labelWithString: "Volume")
        volumeLabel.font = .systemFont(ofSize: 12)
        volumeLabel.textColor = .secondaryLabelColor
        volumeLabel.translatesAutoresizingMaskIntoConstraints = false
        volumeLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true
        volumeRow.addArrangedSubview(volumeLabel)

        volumeSlider.minValue = 0
        volumeSlider.maxValue = 7
        volumeSlider.integerValue = 4
        volumeSlider.numberOfTickMarks = 8
        volumeSlider.allowsTickMarkValuesOnly = true
        volumeSlider.isContinuous = true
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        volumeRow.addArrangedSubview(volumeSlider)

        volumeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        volumeValueLabel.textColor = .secondaryLabelColor
        volumeValueLabel.alignment = .right
        volumeValueLabel.translatesAutoresizingMaskIntoConstraints = false
        volumeValueLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true
        volumeRow.addArrangedSubview(volumeValueLabel)

        stack.addArrangedSubview(volumeRow)

        let lengthRow = NSStackView()
        lengthRow.orientation = .horizontal
        lengthRow.spacing = 8
        lengthRow.alignment = .centerY

        let lengthLabel = NSTextField(labelWithString: "Length")
        lengthLabel.font = .systemFont(ofSize: 12)
        lengthLabel.textColor = .secondaryLabelColor
        lengthLabel.translatesAutoresizingMaskIntoConstraints = false
        lengthLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true
        lengthRow.addArrangedSubview(lengthLabel)

        toneLengthSlider.minValue = 1
        toneLengthSlider.maxValue = 11   // 1-10 = seconds, 11 = infinite
        toneLengthSlider.integerValue = 5
        toneLengthSlider.numberOfTickMarks = 11
        toneLengthSlider.allowsTickMarkValuesOnly = true
        toneLengthSlider.isContinuous = true
        toneLengthSlider.target = self
        toneLengthSlider.action = #selector(toneLengthChanged)
        toneLengthSlider.translatesAutoresizingMaskIntoConstraints = false
        toneLengthSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        lengthRow.addArrangedSubview(toneLengthSlider)

        toneLengthValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        toneLengthValueLabel.textColor = .secondaryLabelColor
        toneLengthValueLabel.alignment = .right
        toneLengthValueLabel.translatesAutoresizingMaskIntoConstraints = false
        toneLengthValueLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true
        lengthRow.addArrangedSubview(toneLengthValueLabel)

        stack.addArrangedSubview(lengthRow)

        let soundButtonRow = NSStackView()
        soundButtonRow.orientation = .horizontal
        soundButtonRow.spacing = 12

        playButton.title = "Start Sound"
        playButton.bezelStyle = .push
        playButton.target = self
        playButton.action = #selector(startSoundPressed)
        soundButtonRow.addArrangedSubview(playButton)

        stopSoundButton.title = "Stop Sound"
        stopSoundButton.bezelStyle = .push
        stopSoundButton.target = self
        stopSoundButton.action = #selector(stopSoundPressed)
        soundButtonRow.addArrangedSubview(stopSoundButton)

        stack.addArrangedSubview(soundButtonRow)

        // -- Settings section --
        stack.addArrangedSubview(fullWidthSeparator())
        stack.addArrangedSubview(sectionLabel("Settings"))

        loginCheckbox.setButtonType(.switch)
        loginCheckbox.title = "Start at login"
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginCheckboxChanged)
        loginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        stack.addArrangedSubview(loginCheckbox)

        httpCheckbox.setButtonType(.switch)
        httpCheckbox.title = "Enable HTTP Control (port 29100)"
        httpCheckbox.target = self
        httpCheckbox.action = #selector(httpCheckboxChanged)
        httpCheckbox.state = UserDefaults.standard.bool(forKey: "httpServerEnabled") ? .on : .off
        stack.addArrangedSubview(httpCheckbox)

        // -- Power section --
        stack.addArrangedSubview(fullWidthSeparator())

        let powerRow = NSStackView()
        powerRow.orientation = .horizontal
        powerRow.spacing = 12

        turnOnButton.title = "Turn On"
        turnOnButton.bezelStyle = .push
        turnOnButton.target = self
        turnOnButton.action = #selector(turnOnPressed)
        powerRow.addArrangedSubview(turnOnButton)

        turnOffButton.title = "Turn Off"
        turnOffButton.bezelStyle = .push
        turnOffButton.target = self
        turnOffButton.action = #selector(turnOffPressed)
        powerRow.addArrangedSubview(turnOffButton)

        stack.addArrangedSubview(powerRow)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func fullWidthSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// Convert a BPM value to equal on/off durations in 0.1 s units.
    ///
    /// One full blink cycle = on + off.
    /// cycles per minute = BPM → cycle period = 60/BPM seconds.
    /// Half-period (on = off) = 30/BPM seconds → in 0.1 s units = 300/BPM.
    private func bpmToStepValue(_ bpm: Double) -> UInt8 {
        guard bpm > 0 else { return 255 }
        let steps = 300.0 / bpm
        return UInt8(clamping: Int(steps.rounded()))
    }

    // MARK: - Connection state

    @objc private func connectionChanged() {
        updateConnectionState()
    }

    private func updateConnectionState() {
        let connected = BusylightController.shared.isConnected
        statusLabel.stringValue = connected ? "Busylight Connected" : "No Busylight Connected"
        statusLabel.textColor = connected ? .systemGreen : .secondaryLabelColor

        let controls: [NSControl] = [
            colorWell, brightnessSlider, effectSegment,
            tonePopUp, volumeSlider, toneLengthSlider, playButton,
            stopSoundButton, turnOnButton, turnOffButton
        ]
        for control in controls {
            control.isEnabled = connected
        }
        let bpmEnabled = connected && effectSegment.selectedSegment != 0
        bpmSlider.isEnabled = bpmEnabled
    }

    // MARK: - State sync

    @objc private func stateChanged() {
        // Defer to the next run loop iteration to avoid recursive layout
        DispatchQueue.main.async { [weak self] in
            self?.syncUIWithControllerState()
        }
    }

    private func syncUIWithControllerState() {
        isUpdatingFromState = true
        defer { isUpdatingFromState = false }

        let ctrl = BusylightController.shared
        let r = ctrl.red
        let g = ctrl.green
        let b = ctrl.blue

        // Derive brightness as the max channel value (0-100)
        let brightness = max(r, g, b)
        brightnessSlider.integerValue = Int(brightness)
        brightnessValueLabel.stringValue = "\(brightness)"

        // Reconstruct the base color at full brightness for the color well
        if brightness > 0 {
            let scale = 1.0 / (Double(brightness) / 100.0)
            let cr = min(1.0, Double(r) / 100.0 * scale)
            let cg = min(1.0, Double(g) / 100.0 * scale)
            let cb = min(1.0, Double(b) / 100.0 * scale)
            colorWell.color = NSColor(red: cr, green: cg, blue: cb, alpha: 1.0)
        }

        // Effect
        switch ctrl.effect {
        case .solid: effectSegment.selectedSegment = 0
        case .blink: effectSegment.selectedSegment = 1
        case .pulse: effectSegment.selectedSegment = 2
        }

        let isSolid = ctrl.effect == .solid
        bpmSlider.isEnabled = !isSolid && ctrl.isConnected
        bpmValueLabel.textColor = isSolid ? .tertiaryLabelColor : .secondaryLabelColor

        // Convert stepTime back to BPM
        if ctrl.stepTime > 0 {
            let bpm = 300.0 / Double(ctrl.stepTime)
            bpmSlider.doubleValue = bpm
            bpmValueLabel.stringValue = "\(Int(bpm)) BPM"
        }

        // Volume
        volumeSlider.integerValue = Int(ctrl.volumeLevel)
        volumeValueLabel.stringValue = "\(ctrl.volumeLevel)"
    }

    // MARK: - Actions

    /// Reads the color well + brightness slider, scales to 0-100, and sends.
    @objc private func colorChanged() {
        guard !isUpdatingFromState else { return }
        let brightness = brightnessSlider.doubleValue / 100.0
        brightnessValueLabel.stringValue = "\(brightnessSlider.integerValue)"

        let c = colorWell.color.usingColorSpace(.deviceRGB) ?? colorWell.color
        let r = UInt8(min(100.0, c.redComponent * 100.0 * brightness))
        let g = UInt8(min(100.0, c.greenComponent * 100.0 * brightness))
        let b = UInt8(min(100.0, c.blueComponent * 100.0 * brightness))
        BusylightController.shared.setColor(red: r, green: g, blue: b)
    }

    @objc private func effectChanged() {
        guard !isUpdatingFromState else { return }
        let index = effectSegment.selectedSegment
        let isSolid = (index == 0)
        bpmSlider.isEnabled = !isSolid
        bpmValueLabel.textColor = isSolid ? .tertiaryLabelColor : .secondaryLabelColor

        if isSolid {
            BusylightController.shared.setEffect(.solid)
        } else {
            sendCurrentBPM()
        }
    }

    @objc private func bpmChanged() {
        guard !isUpdatingFromState else { return }
        let bpm = bpmSlider.doubleValue
        bpmValueLabel.stringValue = "\(Int(bpm)) BPM"
        bpmValueLabel.textColor = .secondaryLabelColor
        sendCurrentBPM()
    }

    /// Send the current BPM value as either blink or pulse depending on the segment.
    private func sendCurrentBPM() {
        let stepValue = bpmToStepValue(bpmSlider.doubleValue)
        if effectSegment.selectedSegment == 2 {
            BusylightController.shared.setPulse(stepTime: stepValue)
        } else {
            BusylightController.shared.setBlink(on: stepValue, off: stepValue)
        }
    }

    @objc private func volumeChanged() {
        guard !isUpdatingFromState else { return }
        let value = UInt8(volumeSlider.integerValue)
        volumeValueLabel.stringValue = "\(value)"
        BusylightController.shared.setVolume(value)
    }

    @objc private func toneLengthChanged() {
        let value = toneLengthSlider.integerValue
        toneLengthValueLabel.stringValue = value >= 11 ? "∞" : "\(value)s"
    }

    @objc private func startSoundPressed() {
        let tones = BusylightTone.allCases
        let index = tonePopUp.indexOfSelectedItem
        guard index >= 0, index < tones.count else { return }
        BusylightController.shared.setVolume(UInt8(volumeSlider.integerValue))

        let length = toneLengthSlider.integerValue
        if length >= 11 {
            BusylightController.shared.startSound(tones[index])
        } else {
            BusylightController.shared.playSound(tones[index], duration: TimeInterval(length))
        }
    }

    @objc private func stopSoundPressed() {
        BusylightController.shared.stopSound()
    }

    @objc private func loginCheckboxChanged() {
        let service = SMAppService.mainApp
        if loginCheckbox.state == .on {
            try? service.register()
            loginCheckbox.state = (service.status == .enabled) ? .on : .off
        } else {
            try? service.unregister()
            loginCheckbox.state = .off
        }
    }

    @objc private func httpCheckboxChanged() {
        let enabled = httpCheckbox.state == .on
        UserDefaults.standard.set(enabled, forKey: "httpServerEnabled")
        NotificationCenter.default.post(name: .httpServerToggled, object: nil)
    }

    @objc private func httpServerSettingChanged() {
        httpCheckbox.state = UserDefaults.standard.bool(forKey: "httpServerEnabled") ? .on : .off
    }

    @objc private func turnOnPressed() {
        // Ensure brightness is non-zero so the light actually turns on
        if brightnessSlider.integerValue == 0 {
            brightnessSlider.integerValue = 100
            brightnessValueLabel.stringValue = "100"
        }

        let brightness = brightnessSlider.doubleValue / 100.0
        let c = colorWell.color.usingColorSpace(.deviceRGB) ?? colorWell.color
        let r = UInt8(min(100.0, c.redComponent * 100.0 * brightness))
        let g = UInt8(min(100.0, c.greenComponent * 100.0 * brightness))
        let b = UInt8(min(100.0, c.blueComponent * 100.0 * brightness))
        BusylightController.shared.setColor(red: r, green: g, blue: b)
    }

    @objc private func turnOffPressed() {
        BusylightController.shared.turnOff()
    }
}
