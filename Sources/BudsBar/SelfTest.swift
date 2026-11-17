// BudsBar – Steuerung für Samsung Galaxy Buds auf macOS
// Copyright (C) 2026 BudsBar contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Prüft das Protokoll ohne Ohrhörer: `BudsBar --selftest`
/// (Läuft auch ohne Xcode, weil die Command Line Tools kein XCTest mitbringen.)
enum SelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print(condition ? "✓ \(name)" : "✗ \(name)")
            if !condition { failures += 1 }
        }

        // CRC-16/XMODEM-Referenzwert
        check(CRC16.checksum(Array("123456789".utf8)) == 0x31C3, "CRC16 Referenzwert")

        // Rahmenaufbau
        let msg = BudsCommand.setNoise(.anc)
        let enc = msg.encoded()
        check(enc.first == 0xFD && enc.last == 0xDD, "SOM/EOM")
        check(enc.count == 1 + 2 + 1 + 1 + 2 + 1, "Rahmenlänge")
        check(enc[1] == 4 && enc[2] == 0, "Längenfeld = ID + Payload + CRC")
        check(enc[3] == 0x78 && enc[4] == 1, "ID und Payload")

        // Roundtrip durch den Parser, auch zerstückelt und mit Müll davor
        var parser = MessageParser()
        let two = [0x00, 0x42] + enc + BudsCommand.setEqualizer(.clear).encoded()
        var parsed: [BudsMessage] = []
        for byte in two { parsed += parser.feed([byte]) }
        check(parsed == [msg, BudsCommand.setEqualizer(.clear)], "Parser Roundtrip")

        // Falsche CRC wird verworfen
        var bad = enc
        bad[5] ^= 0xFF
        var parser2 = MessageParser()
        check(parser2.feed(bad).isEmpty, "Falsche CRC verworfen")

        // Statusauswertung
        var status = BudsStatus()
        status.apply(BudsMessage(.statusUpdated, [1, 80, 75, 1, 0, 0x33, 50, 0x01]))
        check(status.batteryLeft == 80 && status.batteryRight == 75 && status.batteryCase == 50, "Akku aus STATUS_UPDATED")
        check(status.chargingCase && !status.chargingLeft, "Ladestatus")

        var ext = [UInt8](repeating: 0, count: 43)
        ext[2] = 90; ext[3] = 85; ext[7] = 40; ext[9] = 2; ext[10] = 0x0F; ext[11] = 0x23; ext[12] = 1
        status.apply(BudsMessage(.extendedStatusUpdated, ext))
        check(status.batteryLeft == 90 && status.batteryCase == 40, "Akku aus EXTENDED_STATUS")
        check(status.equalizer == .soft, "Equalizer aus EXTENDED_STATUS")
        check(status.touchLocked == true, "Touch-Sperre (Bit 7 invertiert)")
        check(status.touchLeft == .noiseControl && status.touchRight == .volume, "Touch-Belegung")
        check(status.noiseMode == .anc, "Geräuschmodus")

        print(failures == 0 ? "Alle Tests bestanden." : "\(failures) Test(s) fehlgeschlagen.")
        return failures == 0
    }
}
