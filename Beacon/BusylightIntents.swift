//
//  BusylightIntents.swift
//  Beacon
//
//  App Intents that expose Busylight controls to Shortcuts.
//

import AppIntents

// MARK: - Color Presets

@available(macOS 13.0, *)
enum BusylightColorAppEnum: String, AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Color")

    static var caseDisplayRepresentations: [BusylightColorAppEnum: DisplayRepresentation] = [
        .red:         DisplayRepresentation(title: "Red",          image: .init(systemName: "circle.fill")),
        .orange:      DisplayRepresentation(title: "Orange",       image: .init(systemName: "circle.fill")),
        .yellow:      DisplayRepresentation(title: "Yellow",       image: .init(systemName: "circle.fill")),
        .green:       DisplayRepresentation(title: "Green",        image: .init(systemName: "circle.fill")),
        .cyan:        DisplayRepresentation(title: "Cyan",         image: .init(systemName: "circle.fill")),
        .blue:        DisplayRepresentation(title: "Blue",         image: .init(systemName: "circle.fill")),
        .purple:      DisplayRepresentation(title: "Purple",       image: .init(systemName: "circle.fill")),
        .pink:        DisplayRepresentation(title: "Pink",         image: .init(systemName: "circle.fill")),
        .white:       DisplayRepresentation(title: "White",        image: .init(systemName: "circle.fill")),
    ]

    case red, orange, yellow, green, cyan, blue, purple, pink, white

    /// PWM values (0-100) for each preset.
    var rgb: (UInt8, UInt8, UInt8) {
        switch self {
        case .red:    return (100, 0, 0)
        case .orange: return (100, 40, 0)
        case .yellow: return (100, 100, 0)
        case .green:  return (0, 100, 0)
        case .cyan:   return (0, 100, 100)
        case .blue:   return (0, 0, 100)
        case .purple: return (60, 0, 100)
        case .pink:   return (100, 0, 60)
        case .white:  return (100, 100, 100)
        }
    }
}

// MARK: - Set Light Color

@available(macOS 13.0, *)
struct SetLightColorIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Light Color"
    static var description = IntentDescription("Sets your light to a preset color.")

    @Parameter(title: "Color")
    var color: BusylightColorAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Set light to \(\.$color)")
    }

    func perform() async throws -> some IntentResult {
        let (r, g, b) = color.rgb
        await BusylightController.shared.setColor(red: r, green: g, blue: b)
        return .result()
    }
}

// MARK: - Set Custom Light Color

@available(macOS 13.0, *)
struct SetCustomColorIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Custom Light Color"
    static var description = IntentDescription("Sets your light to a custom color using Red, Green, and Blue values from 0 to 100.")

    @Parameter(title: "Amount", default: 100, inclusiveRange: (0, 100))
    var red: Int

    @Parameter(title: "Amount", default: 0, inclusiveRange: (0, 100))
    var green: Int

    @Parameter(title: "Amount", default: 0, inclusiveRange: (0, 100))
    var blue: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set light to Red \(\.$red), Green \(\.$green), Blue \(\.$blue)")
    }

    func perform() async throws -> some IntentResult {
        await BusylightController.shared.setColor(
            red: UInt8(clamping: red),
            green: UInt8(clamping: green),
            blue: UInt8(clamping: blue)
        )
        return .result()
    }
}

// MARK: - Set Light Effect

@available(macOS 13.0, *)
struct SetLightEffectIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Light Effect"
    static var description = IntentDescription("Sets your light to solid, blink, or pulse. For blink and pulse, you can set the speed in BPM.")

    @Parameter(title: "Effect")
    var effect: BusylightEffectAppEnum

    @Parameter(title: "BPM", default: 60, inclusiveRange: (10, 600))
    var bpm: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set light to \(\.$effect) at \(\.$bpm) BPM")
    }

    func perform() async throws -> some IntentResult {
        let effect = effect.domainValue
        switch effect {
        case .solid:
            await BusylightController.shared.setEffect(.solid)
        case .blink:
            let stepTime = UInt8(clamping: Int((300.0 / Double(bpm)).rounded()))
            await BusylightController.shared.setBlink(on: max(stepTime, 1), off: max(stepTime, 1))
        case .pulse:
            let stepTime = UInt8(clamping: Int((300.0 / Double(bpm)).rounded()))
            await BusylightController.shared.setPulse(stepTime: max(stepTime, 1))
        }
        return .result()
    }
}

// MARK: - Flash Light

@available(macOS 13.0, *)
struct FlashLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Flash Light"
    static var description = IntentDescription("Flashes your light a color a number of times, then returns to its previous state. Great for notifications.")

    @Parameter(title: "Color")
    var color: BusylightColorAppEnum

    @Parameter(title: "Times", default: 3, inclusiveRange: (1, 20))
    var count: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Flash light \(\.$color), \(\.$count) times")
    }

    func perform() async throws -> some IntentResult {
        let (r, g, b) = color.rgb
        await BusylightController.shared.flash(red: r, green: g, blue: b, count: count)
        return .result()
    }
}

// MARK: - Play Sound

@available(macOS 13.0, *)
struct PlaySoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Sound"
    static var description = IntentDescription("Plays a sound on your light. Set seconds to 0 for continuous play.")

    @Parameter(title: "Sound")
    var tone: BusylightToneAppEnum

    @Parameter(title: "Seconds", default: 5, inclusiveRange: (0, 30))
    var seconds: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$tone) sound for \(\.$seconds) seconds")
    }

    func perform() async throws -> some IntentResult {
        if seconds <= 0 {
            await BusylightController.shared.startSound(tone.domainValue)
        } else {
            await BusylightController.shared.playSound(tone.domainValue, duration: TimeInterval(seconds))
        }
        return .result()
    }
}

// MARK: - Stop Sound

@available(macOS 13.0, *)
struct StopSoundIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Sound"
    static var description = IntentDescription("Stops any sound currently playing on your light.")

    static var parameterSummary: some ParameterSummary {
        Summary("Stop playing sound")
    }

    func perform() async throws -> some IntentResult {
        await BusylightController.shared.stopSound()
        return .result()
    }
}

// MARK: - Set Volume

@available(macOS 13.0, *)
struct SetVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Volume"
    static var description = IntentDescription("Sets the volume for sounds. 0 is mute, 7 is loudest.")

    @Parameter(title: "Level", default: 4, inclusiveRange: (0, 7))
    var volume: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set volume to \(\.$volume)")
    }

    func perform() async throws -> some IntentResult {
        await BusylightController.shared.setVolume(UInt8(clamping: volume))
        return .result()
    }
}

// MARK: - Turn On Light

@available(macOS 13.0, *)
struct TurnOnLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn On Light"
    static var description = IntentDescription("Turns on your light with the current color.")

    func perform() async throws -> some IntentResult {
        await BusylightController.shared.turnOn()
        return .result()
    }
}

// MARK: - Turn Off Light

@available(macOS 13.0, *)
struct TurnOffLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Off Light"
    static var description = IntentDescription("Turns off your light and stops any sound.")

    func perform() async throws -> some IntentResult {
        await BusylightController.shared.turnOff()
        return .result()
    }
}

// MARK: - App Shortcuts Provider

@available(macOS 13.0, *)
struct BeaconShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetLightColorIntent(),
            phrases: [
                "Set \(.applicationName) to \(\.$color)",
                "Change \(.applicationName) to \(\.$color)",
                "Make \(.applicationName) \(\.$color)",
            ],
            shortTitle: "Set Color",
            systemImageName: "paintpalette"
        )
        AppShortcut(
            intent: FlashLightIntent(),
            phrases: [
                "Flash \(.applicationName) \(\.$color)",
            ],
            shortTitle: "Flash Light",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: TurnOnLightIntent(),
            phrases: [
                "Turn on \(.applicationName)",
            ],
            shortTitle: "Turn On",
            systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: TurnOffLightIntent(),
            phrases: [
                "Turn off \(.applicationName)",
            ],
            shortTitle: "Turn Off",
            systemImageName: "lightbulb.slash"
        )
    }
}
