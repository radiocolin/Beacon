//
//  BusylightEffect.swift
//  Beacon
//

import Foundation
import AppIntents

enum BusylightEffect: String, CaseIterable, Sendable {
    case solid = "Solid"
    case blink = "Blink"
    case pulse = "Pulse"

    /// The byte value sent in the HID report's "light effect" field.
    var reportValue: UInt8 {
        switch self {
        case .solid: return 0x01
        case .blink: return 0x02
        case .pulse: return 0x03
        }
    }
}

// MARK: - App Intents support

@available(macOS 13.0, *)
enum BusylightEffectAppEnum: String, AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Effect")

    static var caseDisplayRepresentations: [BusylightEffectAppEnum: DisplayRepresentation] = [
        .solid: "Solid",
        .blink: "Blink",
        .pulse: "Pulse"
    ]

    case solid, blink, pulse

    var domainValue: BusylightEffect {
        switch self {
        case .solid: return .solid
        case .blink: return .blink
        case .pulse: return .pulse
        }
    }
}
