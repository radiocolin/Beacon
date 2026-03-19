//
//  BusylightTone.swift
//  Beacon
//

import Foundation
import AppIntents

enum BusylightTone: String, CaseIterable, Sendable {
    case openOffice         = "Open Office"
    case quiet              = "Quiet"
    case funky              = "Funky"
    case fairyTale          = "Fairy Tale"
    case kuandoTrain        = "Kuando Train"
    case telephoneNordic    = "Telephone Nordic"
    case telephoneOriginal  = "Telephone Original"
    case telephonePickMeUp  = "Telephone Pick Me Up"
    case buzz               = "Buzz"

    /// The byte value sent in the HID report's tone field.
    var reportValue: UInt8 {
        switch self {
        case .openOffice:          return 0x01
        case .quiet:               return 0x02
        case .funky:               return 0x03
        case .fairyTale:           return 0x04
        case .kuandoTrain:         return 0x05
        case .telephoneNordic:     return 0x06
        case .telephoneOriginal:   return 0x07
        case .telephonePickMeUp:   return 0x08
        case .buzz:                return 0x09
        }
    }
}

// MARK: - App Intents support

@available(macOS 13.0, *)
enum BusylightToneAppEnum: String, AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sound")

    static var caseDisplayRepresentations: [BusylightToneAppEnum: DisplayRepresentation] = [
        .openOffice:         "Open Office",
        .quiet:              "Quiet",
        .funky:              "Funky",
        .fairyTale:          "Fairy Tale",
        .kuandoTrain:        "Kuando Train",
        .telephoneNordic:    "Telephone Nordic",
        .telephoneOriginal:  "Telephone Original",
        .telephonePickMeUp:  "Telephone Pick Me Up",
        .buzz:               "Buzz"
    ]

    case openOffice, quiet, funky, fairyTale, kuandoTrain
    case telephoneNordic, telephoneOriginal, telephonePickMeUp, buzz

    var domainValue: BusylightTone {
        switch self {
        case .openOffice:         return .openOffice
        case .quiet:              return .quiet
        case .funky:              return .funky
        case .fairyTale:          return .fairyTale
        case .kuandoTrain:        return .kuandoTrain
        case .telephoneNordic:    return .telephoneNordic
        case .telephoneOriginal:  return .telephoneOriginal
        case .telephonePickMeUp:  return .telephonePickMeUp
        case .buzz:               return .buzz
        }
    }
}
