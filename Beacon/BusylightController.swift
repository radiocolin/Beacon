//
//  BusylightController.swift
//  Beacon
//
//  Handles all HID communication with Kuando Busylight devices.
//
//  Protocol reference:
//  https://github.com/JnyJny/busylight/blob/main/docs/hardware/devices/kuando.md
//
//  64-byte packet = 7 × 8-byte steps + 8-byte control/checksum tail.
//
//  Step (8 bytes) — Jump format:
//    Byte 0: [opcode:4][target:4]  opcode 0x1 = Jump
//    Byte 1: repeat (0 = infinite)
//    Byte 2: red   PWM (0-100)
//    Byte 3: green PWM (0-100)
//    Byte 4: blue  PWM (0-100)
//    Byte 5: on-time  (0.1 s units)
//    Byte 6: off-time (0.1 s units)
//    Byte 7: [update:1][ringtone:4][volume:3]
//
//  Keep-alive step:
//    Byte 0: [0x8:4][timeout:4]
//    Bytes 1-7: 0x00
//
//  Tail (bytes 56-63):
//    56: sensitivity (0)   57: timeout (0)   58: trigger (0)
//    59-61: 0xFF 0xFF 0xFF
//    62-63: 16-bit checksum (sum of bytes 0..61)
//

import Foundation
import IOKit
import IOKit.hid

// MARK: - Notification names

extension Notification.Name {
    static let busylightConnectionChanged = Notification.Name("busylightConnectionChanged")
    static let busylightStateChanged = Notification.Name("busylightStateChanged")
    static let httpServerToggled = Notification.Name("httpServerToggled")
}

// MARK: - Controller

final class BusylightController: @unchecked Sendable {

    static let shared = BusylightController()

    private static let vendorID: Int = 0x27BB
    private static let reportSize = 64
    private static let keepAliveInterval: TimeInterval = 7.0
    private static let keepAliveTimeout: UInt8 = 15

    // MARK: - State

    private let hidManager: IOHIDManager
    private var device: IOHIDDevice?
    private let queue = DispatchQueue(label: "com.beacon.busylightcontroller", qos: .userInitiated)
    private var keepAliveTimer: Timer?
    private var soundStopTimer: Timer?

    private var currentRed: UInt8 = 0
    private var currentGreen: UInt8 = 0
    private var currentBlue: UInt8 = 0
    private var currentEffect: BusylightEffect = .solid
    private var currentStepTime: UInt8 = 3   // used for blink & pulse (0.1 s units)
    private var currentRingtone: UInt8 = 0
    private var currentVolume: UInt8 = 0
    private var audioUpdate: Bool = false

    var isConnected: Bool { device != nil }

    // MARK: - Public read-only state

    var red: UInt8 { currentRed }
    var green: UInt8 { currentGreen }
    var blue: UInt8 { currentBlue }
    var effect: BusylightEffect { currentEffect }
    var stepTime: UInt8 { currentStepTime }
    var ringtone: UInt8 { currentRingtone }
    var volumeLevel: UInt8 { currentVolume }

    // MARK: - Persistence keys

    private enum DefaultsKey {
        static let red = "bl_red"
        static let green = "bl_green"
        static let blue = "bl_blue"
        static let effect = "bl_effect"
        static let stepTime = "bl_stepTime"
        static let volume = "bl_volume"
    }

    // MARK: - Init

    private init() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        restoreState()
        setupDeviceMatching()
    }

    // MARK: - State persistence

    private func saveState() {
        let d = UserDefaults.standard
        d.set(Int(currentRed), forKey: DefaultsKey.red)
        d.set(Int(currentGreen), forKey: DefaultsKey.green)
        d.set(Int(currentBlue), forKey: DefaultsKey.blue)
        d.set(currentEffect.rawValue, forKey: DefaultsKey.effect)
        d.set(Int(currentStepTime), forKey: DefaultsKey.stepTime)
        d.set(Int(currentVolume), forKey: DefaultsKey.volume)
    }

    private func restoreState() {
        let d = UserDefaults.standard
        // Only restore if we've saved before (check for the red key existing)
        guard d.object(forKey: DefaultsKey.red) != nil else { return }
        currentRed = UInt8(clamping: d.integer(forKey: DefaultsKey.red))
        currentGreen = UInt8(clamping: d.integer(forKey: DefaultsKey.green))
        currentBlue = UInt8(clamping: d.integer(forKey: DefaultsKey.blue))
        if let effectName = d.string(forKey: DefaultsKey.effect),
           let effect = BusylightEffect(rawValue: effectName) {
            currentEffect = effect
        }
        currentStepTime = UInt8(clamping: d.integer(forKey: DefaultsKey.stepTime))
        if currentStepTime == 0 { currentStepTime = 3 }
        currentVolume = UInt8(clamping: d.integer(forKey: DefaultsKey.volume))
    }

    // MARK: - Device matching

    private func setupDeviceMatching() {
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: BusylightController.vendorID
        ]
        IOHIDManagerSetDeviceMatching(hidManager, matchDict as CFDictionary)

        let connectCallback: IOHIDDeviceCallback = { context, result, sender, hidDevice in
            guard let context = context else { return }
            let controller = Unmanaged<BusylightController>.fromOpaque(context).takeUnretainedValue()
            controller.deviceConnected(hidDevice)
        }

        let disconnectCallback: IOHIDDeviceCallback = { context, result, sender, hidDevice in
            guard let context = context else { return }
            let controller = Unmanaged<BusylightController>.fromOpaque(context).takeUnretainedValue()
            controller.deviceDisconnected(hidDevice)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, connectCallback, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, disconnectCallback, selfPtr)

        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func deviceConnected(_ hidDevice: IOHIDDevice) {
        queue.sync { self.device = hidDevice }
        DispatchQueue.main.async {
            self.startKeepAlive()
            // Re-send the persisted state to the device so it resumes
            if self.currentRed > 0 || self.currentGreen > 0 || self.currentBlue > 0 {
                self.audioUpdate = false
                self.sendCurrentState()
            }
            NotificationCenter.default.post(name: .busylightConnectionChanged, object: nil)
        }
    }

    private func deviceDisconnected(_ hidDevice: IOHIDDevice) {
        queue.sync {
            if self.device === hidDevice { self.device = nil }
        }
        DispatchQueue.main.async {
            self.stopKeepAlive()
            NotificationCenter.default.post(name: .busylightConnectionChanged, object: nil)
        }
    }

    // MARK: - Keep-alive

    private func startKeepAlive() {
        stopKeepAlive()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: BusylightController.keepAliveInterval, repeats: true) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private func sendKeepAlive() {
        var packet = [UInt8](repeating: 0, count: BusylightController.reportSize)
        packet[0] = (0x8 << 4) | (BusylightController.keepAliveTimeout & 0x0F)
        finalizeAndSend(&packet)
    }

    // MARK: - Packet helpers

    /// Write a jump step into the packet at the given step index (0-6).
    /// - Parameters:
    ///   - packet: The 64-byte buffer.
    ///   - step: Step index 0-6.
    ///   - target: Jump target step (0-6). Typically the next step, or 0 to loop.
    ///   - repeat_: Repeat count (0 = infinite, 1 = once, …).
    ///   - r, g, b: PWM values 0-100.
    ///   - onTime, offTime: Durations in 0.1 s units.
    ///   - audio: Audio byte (packed update|ringtone|volume), or 0.
    private func writeJumpStep(
        _ packet: inout [UInt8], step: Int, target: UInt8,
        repeat_: UInt8 = 0,
        r: UInt8, g: UInt8, b: UInt8,
        onTime: UInt8, offTime: UInt8,
        audio: UInt8 = 0
    ) {
        let base = step * 8
        packet[base + 0] = 0x10 | (target & 0x07)  // JUMP_OP | target
        packet[base + 1] = repeat_
        packet[base + 2] = min(r, 100)
        packet[base + 3] = min(g, 100)
        packet[base + 4] = min(b, 100)
        packet[base + 5] = onTime
        packet[base + 6] = offTime
        packet[base + 7] = audio
    }

    /// Apply the tail (pad + checksum) and write the packet to the device.
    private func finalizeAndSend(_ packet: inout [UInt8]) {
        packet[59] = 0xFF
        packet[60] = 0xFF
        packet[61] = 0xFF
        var sum: UInt16 = 0
        for i in 0..<62 { sum &+= UInt16(packet[i]) }
        packet[62] = UInt8((sum >> 8) & 0xFF)
        packet[63] = UInt8(sum & 0xFF)
        writePacket(packet)
    }

    private func writePacket(_ packet: [UInt8]) {
        queue.async { [weak self] in
            guard let self, let device = self.device else { return }
            var buf = packet
            let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &buf, buf.count)
            if result != kIOReturnSuccess {
                NSLog("Beacon: HID write failed: 0x%08x", result)
            }
        }
    }

    // MARK: - Audio byte

    private func makeAudioByte() -> UInt8 {
        guard audioUpdate else { return 0 }
        return 0x80 | ((currentRingtone & 0x0F) << 3) | (currentVolume & 0x07)
    }

    // MARK: - Packet builders

    /// Solid color or blink: single step jumping to itself.
    private func sendSolidOrBlink() {
        var packet = [UInt8](repeating: 0, count: BusylightController.reportSize)
        let onTime: UInt8 = (currentEffect == .blink) ? currentStepTime : 0
        let offTime: UInt8 = (currentEffect == .blink) ? currentStepTime : 0
        writeJumpStep(&packet, step: 0, target: 0,
                      r: currentRed, g: currentGreen, b: currentBlue,
                      onTime: onTime, offTime: offTime,
                      audio: makeAudioByte())
        finalizeAndSend(&packet)
    }

    /// Pulse: 6-step brightness ramp that loops.
    ///
    /// Uses the 7 available steps to create a fade-in / fade-out cycle:
    ///   Step 0: 17% brightness  → jump to 1
    ///   Step 1: 50% brightness  → jump to 2
    ///   Step 2: 100% brightness → jump to 3
    ///   Step 3: 100% brightness → jump to 4
    ///   Step 4: 50% brightness  → jump to 5
    ///   Step 5: 17% brightness  → jump to 0 (loop)
    ///
    /// Each step holds for `currentStepTime` with off-time = 0 (always lit),
    /// so one complete cycle = 6 × stepTime.
    private func sendPulse() {
        var packet = [UInt8](repeating: 0, count: BusylightController.reportSize)
        let t = max(currentStepTime, 1)

        // Brightness levels as fractions of the current color
        let levels: [(scale: Double, target: UInt8)] = [
            (0.17, 1), // step 0 → 1
            (0.50, 2), // step 1 → 2
            (1.00, 3), // step 2 → 3
            (1.00, 4), // step 3 → 4
            (0.50, 5), // step 4 → 5
            (0.17, 0), // step 5 → 0 (loop)
        ]

        for (i, level) in levels.enumerated() {
            let r = UInt8(Double(currentRed) * level.scale)
            let g = UInt8(Double(currentGreen) * level.scale)
            let b = UInt8(Double(currentBlue) * level.scale)
            let audio: UInt8 = (i == 0) ? makeAudioByte() : 0
            writeJumpStep(&packet, step: i, target: level.target,
                          repeat_: 1,
                          r: r, g: g, b: b,
                          onTime: t, offTime: 0,
                          audio: audio)
        }

        finalizeAndSend(&packet)
    }

    private func postStateChanged() {
        saveState()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .busylightStateChanged, object: nil)
        }
    }

    private func sendCurrentState() {
        switch currentEffect {
        case .solid, .blink:
            sendSolidOrBlink()
        case .pulse:
            sendPulse()
        }
    }

    // MARK: - Public API

    /// Set light color (0-100 PWM per channel).
    func setColor(red: UInt8, green: UInt8, blue: UInt8) {
        currentRed = min(red, 100)
        currentGreen = min(green, 100)
        currentBlue = min(blue, 100)
        audioUpdate = false
        sendCurrentState()
        postStateChanged()
    }

    /// Set the effect mode.
    func setEffect(_ effect: BusylightEffect) {
        currentEffect = effect
        audioUpdate = false
        sendCurrentState()
        postStateChanged()
    }

    /// Set blink on/off timing (equal on and off, in 0.1 s units).
    func setBlink(on: UInt8, off: UInt8) {
        currentStepTime = on  // for blink, on=off; for pulse, per-ramp-step
        currentEffect = .blink
        audioUpdate = false
        sendCurrentState()
        postStateChanged()
    }

    /// Set pulse speed. `stepTime` is the duration of each ramp step in 0.1 s units.
    func setPulse(stepTime: UInt8) {
        currentStepTime = stepTime
        currentEffect = .pulse
        audioUpdate = false
        sendCurrentState()
        postStateChanged()
    }

    /// Start playing a ringtone. Loops until `stopSound()` is called.
    func startSound(_ tone: BusylightTone) {
        soundStopTimer?.invalidate()
        soundStopTimer = nil
        currentRingtone = tone.reportValue
        if currentVolume == 0 { currentVolume = 4 }
        audioUpdate = true
        sendCurrentState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.audioUpdate = false
        }
        postStateChanged()
    }

    /// Play a ringtone for a given duration in seconds, then stop automatically.
    func playSound(_ tone: BusylightTone, duration: TimeInterval) {
        startSound(tone)
        soundStopTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.stopSound()
        }
    }

    /// Stop any currently playing ringtone.
    func stopSound() {
        soundStopTimer?.invalidate()
        soundStopTimer = nil
        currentRingtone = 0
        currentVolume = 0
        audioUpdate = true
        sendCurrentState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.audioUpdate = false
        }
        postStateChanged()
    }

    /// Set volume (0-7).
    func setVolume(_ value: UInt8) {
        currentVolume = min(value, 7)
        postStateChanged()
    }

    /// Turn on with the current color (defaults to red if all zeros).
    func turnOn() {
        if currentRed == 0 && currentGreen == 0 && currentBlue == 0 {
            currentRed = 100
        }
        audioUpdate = false
        sendCurrentState()
        postStateChanged()
    }

    /// Turn off the light and stop any ringtone.
    func turnOff() {
        currentRed = 0
        currentGreen = 0
        currentBlue = 0
        currentEffect = .solid
        // Stop audio by sending ringtone=0 with update bit
        currentRingtone = 0
        currentVolume = 0
        audioUpdate = true
        sendCurrentState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.audioUpdate = false
        }
        postStateChanged()
    }

    /// Flash a color a given number of times, then restore the previous state.
    ///
    /// Each flash cycle is 0.3 s on + 0.3 s off. The method awaits until all
    /// flashes are done and the original state has been re-sent to the device.
    func flash(red: UInt8, green: UInt8, blue: UInt8, count: Int) async {
        // Snapshot current state
        let savedRed = currentRed
        let savedGreen = currentGreen
        let savedBlue = currentBlue
        let savedEffect = currentEffect
        let savedStepTime = currentStepTime
        let savedRingtone = currentRingtone
        let savedVolume = currentVolume

        let onTime: UInt8 = 3   // 0.3 s
        let offTime: UInt8 = 3  // 0.3 s
        let cycleDuration: TimeInterval = Double(onTime + offTime) * 0.1

        // Send a blink packet with a finite repeat count
        var packet = [UInt8](repeating: 0, count: BusylightController.reportSize)
        writeJumpStep(&packet, step: 0, target: 0,
                      repeat_: UInt8(clamping: count),
                      r: min(red, 100), g: min(green, 100), b: min(blue, 100),
                      onTime: onTime, offTime: offTime)
        finalizeAndSend(&packet)

        // Wait for all flashes to complete
        try? await Task.sleep(nanoseconds: UInt64(cycleDuration * Double(count) * 1_000_000_000))

        // Restore previous state
        currentRed = savedRed
        currentGreen = savedGreen
        currentBlue = savedBlue
        currentEffect = savedEffect
        currentStepTime = savedStepTime
        currentRingtone = savedRingtone
        currentVolume = savedVolume
        audioUpdate = false
        sendCurrentState()
        postStateChanged()
    }
}
