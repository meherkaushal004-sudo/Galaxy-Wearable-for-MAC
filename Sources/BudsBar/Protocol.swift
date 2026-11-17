// BudsBar – Steuerung für Samsung Galaxy Buds auf macOS
// Copyright (C) 2026 BudsBar contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Protokoll-Details nach dem Reverse Engineering von GalaxyBudsClient
// (https://github.com/timschneeb/GalaxyBudsClient, GPL-3.0).

import Foundation

/// RFCOMM-Dienst, über den Buds+ und neuere Modelle (inkl. Buds3 / Buds3 Pro) kommunizieren.
enum BudsUUID {
    static let sppNew: [UInt8] = [
        0x2e, 0x73, 0xa4, 0xad, 0x33, 0x2d, 0x41, 0xfc,
        0x90, 0xe2, 0x16, 0xbe, 0xf0, 0x65, 0x23, 0xf2,
    ]
}

enum MsgID: UInt8 {
    case statusUpdated          = 0x60
    case extendedStatusUpdated  = 0x61
    case noiseControlsUpdate    = 0x77
    case noiseControls          = 0x78
    case equalizer              = 0x86
    case managerInfo            = 0x88
    case lockTouchpad           = 0x90
    case touchUpdated           = 0x91
    case setTouchpadOption      = 0x92
    case findMyEarbudsStart     = 0xA0
    case findMyEarbudsStop      = 0xA1
}

enum NoiseMode: UInt8, CaseIterable, Identifiable {
    case off = 0, anc = 1, ambient = 2
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .off: return "Aus"
        case .anc: return "ANC"
        case .ambient: return "Umgebung"
        }
    }
}

/// Equalizer-Einstellung. 0 = aus, 1…5 = Preset (Preset-Index + 1).
enum EqualizerPreset: UInt8, CaseIterable, Identifiable {
    case off = 0, bassBoost, soft, dynamic, clear, trebleBoost
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .off: return "Aus"
        case .bassBoost: return "Bass-Boost"
        case .soft: return "Weich"
        case .dynamic: return "Dynamisch"
        case .clear: return "Klar"
        case .trebleBoost: return "Höhen-Boost"
        }
    }
}

/// Belegung von „Berühren und halten“ (StandardTouchMap der Buds3-Reihe).
enum TouchHoldAction: UInt8, CaseIterable, Identifiable {
    case voiceAssistant = 1, noiseControl = 2, volume = 3, spotify = 4
    var id: UInt8 { rawValue }
    var label: String {
        switch self {
        case .voiceAssistant: return "Sprachassistent"
        case .noiseControl: return "Geräuschsteuerung"
        case .volume: return "Lautstärke"
        case .spotify: return "Spotify"
        }
    }
}

// MARK: - CRC16 (CCITT, Polynom 0x1021, Startwert 0)

enum CRC16 {
    static func checksum<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }
}

// MARK: - Nachrichtenrahmen

struct BudsMessage: Equatable {
    static let som: UInt8 = 0xFD
    static let eom: UInt8 = 0xDD

    var id: UInt8
    var payload: [UInt8]

    init(id: UInt8, payload: [UInt8] = []) {
        self.id = id
        self.payload = payload
    }

    init(_ id: MsgID, _ payload: [UInt8] = []) {
        self.init(id: id.rawValue, payload: payload)
    }

    /// SOM | Länge (2 Byte, LE) | ID | Payload | CRC16 (LE) | EOM
    func encoded() -> [UInt8] {
        let size = UInt16(1 + payload.count + 2) & 0x3FF
        let crc = CRC16.checksum([id] + payload)
        var out: [UInt8] = [Self.som, UInt8(size & 0xFF), UInt8(size >> 8), id]
        out += payload
        out += [UInt8(crc & 0xFF), UInt8(crc >> 8), Self.eom]
        return out
    }
}

/// Setzt Nachrichten aus einem Bytestrom zusammen (Pakete können geteilt oder gebündelt ankommen).
struct MessageParser {
    private var buffer: [UInt8] = []

    mutating func feed(_ bytes: [UInt8]) -> [BudsMessage] {
        buffer += bytes
        var messages: [BudsMessage] = []

        while true {
            guard let start = buffer.firstIndex(of: BudsMessage.som) else {
                buffer.removeAll()
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 3 else { break }

            let header = UInt16(buffer[1]) | (UInt16(buffer[2]) << 8)
            let size = Int(header & 0x3FF)
            let total = 1 + 2 + size + 1
            guard size >= 3 else { buffer.removeFirst(); continue }
            guard buffer.count >= total else { break }

            guard buffer[total - 1] == BudsMessage.eom else {
                buffer.removeFirst()
                continue
            }

            let id = buffer[3]
            let payload = Array(buffer[4..<(3 + size - 2)])
            let crc = UInt16(buffer[total - 3]) | (UInt16(buffer[total - 2]) << 8)
            if CRC16.checksum([id] + payload) == crc {
                messages.append(BudsMessage(id: id, payload: payload))
            }
            buffer.removeFirst(total)
        }
        return messages
    }
}

// MARK: - Status

struct BudsStatus: Equatable {
    var batteryLeft: Int?
    var batteryRight: Int?
    var batteryCase: Int?
    var chargingLeft = false
    var chargingRight = false
    var chargingCase = false
    var noiseMode: NoiseMode?
    var equalizer: EqualizerPreset?
    var touchLocked: Bool?
    var touchLeft: TouchHoldAction?
    var touchRight: TouchHoldAction?

    /// Wendet eine empfangene Nachricht an. Gibt `true` zurück, wenn sie erkannt wurde.
    @discardableResult
    mutating func apply(_ msg: BudsMessage) -> Bool {
        let p = msg.payload
        switch MsgID(rawValue: msg.id) {
        case .statusUpdated:
            guard p.count >= 7 else { return false }
            batteryLeft = Self.battery(p[1])
            batteryRight = Self.battery(p[2])
            batteryCase = Self.battery(p[6])
            if p.count >= 8 { applyCharging(p[7]) }
            return true

        case .extendedStatusUpdated:
            guard p.count >= 8 else { return false }
            batteryLeft = Self.battery(p[2])
            batteryRight = Self.battery(p[3])
            batteryCase = Self.battery(p[7])
            if p.count > 9 { equalizer = EqualizerPreset(rawValue: p[9]) }
            if p.count > 10 { touchLocked = (p[10] & 0x80) == 0 }
            if p.count > 11 {
                touchLeft = TouchHoldAction(rawValue: (p[11] & 0xF0) >> 4)
                touchRight = TouchHoldAction(rawValue: p[11] & 0x0F)
            }
            if p.count > 12 { noiseMode = NoiseMode(rawValue: p[12]) }
            if p.count > 42 { applyCharging(p[42]) }
            return true

        case .noiseControlsUpdate:
            guard let first = p.first else { return false }
            noiseMode = NoiseMode(rawValue: first)
            return true

        default:
            return false
        }
    }

    private mutating func applyCharging(_ b: UInt8) {
        chargingLeft = (b & 0x10) != 0
        chargingRight = (b & 0x04) != 0
        chargingCase = (b & 0x01) != 0
    }

    /// Nicht verfügbare Werte (z. B. Ohrhörer nicht im Case) kommen als 0 oder > 100.
    private static func battery(_ b: UInt8) -> Int? {
        (1...100).contains(Int(b)) ? Int(b) : nil
    }
}

// MARK: - Befehle

enum BudsCommand {
    static func managerInfo() -> BudsMessage {
        // [Version 1, Client-Typ Samsung = 1, Android SDK 34]
        BudsMessage(.managerInfo, [0x01, 0x01, 34])
    }

    static func setNoise(_ mode: NoiseMode) -> BudsMessage {
        BudsMessage(.noiseControls, [mode.rawValue])
    }

    static func setEqualizer(_ preset: EqualizerPreset) -> BudsMessage {
        BudsMessage(.equalizer, [preset.rawValue])
    }

    static func lockTouch(_ locked: Bool) -> BudsMessage {
        // [!LockAll, Tap, DoubleTap, TripleTap, Hold, DoubleTapCall, HoldCall]
        BudsMessage(.lockTouchpad, [locked ? 0 : 1, 1, 1, 1, 1, 1, 1])
    }

    static func setTouch(left: TouchHoldAction, right: TouchHoldAction) -> BudsMessage {
        BudsMessage(.setTouchpadOption, [left.rawValue, right.rawValue])
    }

    static func findEarbuds(_ start: Bool) -> BudsMessage {
        BudsMessage(start ? .findMyEarbudsStart : .findMyEarbudsStop)
    }
}
