// BudsBar – Steuerung für Samsung Galaxy Buds auf macOS
// Copyright (C) 2026 BudsBar contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOBluetooth
import os

/// Findet gekoppelte Galaxy Buds, öffnet den RFCOMM-Kanal und tauscht Nachrichten aus.
/// Alle IOBluetooth-Callbacks laufen auf dem Main-Thread.
final class BudsManager: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    enum ConnectionState: Equatable {
        case searching
        case notPaired
        case disconnected
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .searching: return "Suche …"
            case .notPaired: return "Keine Galaxy Buds gekoppelt"
            case .disconnected: return "Nicht verbunden"
            case .connecting: return "Verbinde …"
            case .connected: return "Verbunden"
            case .failed(let reason): return "Fehler: \(reason)"
            }
        }
    }

    @Published private(set) var state: ConnectionState = .searching
    @Published private(set) var deviceName: String?
    @Published private(set) var status = BudsStatus()
    @Published private(set) var isFinding = false
    /// Empfangsstärke in dBm (nur solange verbunden und wenn macOS einen Wert liefert).
    @Published private(set) var rssi: Int?

    let lastSeen = LastSeenTracker()
    let log = Logger(subsystem: "io.github.budsbar.BudsBar", category: "bluetooth")
    private var rssiTimer: Timer?
    private var attempt = 0
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = MessageParser()
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private let serviceUUID: IOBluetoothSDPUUID = BudsUUID.sppNew.withUnsafeBytes {
        IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16)
    }

    override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceDidConnect(_:device:))
        )
        DispatchQueue.main.async { self.connect() }
    }

    // MARK: Verbindung

    func connect() {
        guard channel == nil else { return }
        state = .searching

        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let buds = paired.filter { ($0.name ?? "").localizedCaseInsensitiveContains("Buds") }
        guard let candidate = buds.first(where: { $0.isConnected() }) ?? buds.first else {
            state = .notPaired
            deviceName = nil
            return
        }

        device = candidate
        deviceName = candidate.name
        log.info("Gerät: \(candidate.name ?? "?", privacy: .public) \(candidate.addressString ?? "?", privacy: .public) isConnected=\(candidate.isConnected(), privacy: .public) (von \(buds.count, privacy: .public) Buds)")

        // isConnected() meldet bei Audio-Verbindungen, die macOS selbst aufgebaut hat, oft „false“.
        // Deshalb trotzdem versuchen – das Öffnen des Kanals baut die Verbindung bei Bedarf auf.
        state = .connecting
        attempt += 1
        let thisAttempt = attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            if self.attempt == thisAttempt, self.state == .connecting {
                self.log.error("Zeitüberschreitung beim Verbinden")
                self.channel?.close()
                self.channel = nil
                self.state = .failed("Zeitüberschreitung – sind die Buds aus dem Case?")
            }
        }

        if let record = candidate.getServiceRecord(for: serviceUUID) {
            log.info("Dienst im Cache gefunden")
            openChannel(record: record)
        } else {
            log.info("Dienst nicht im Cache – starte SDP-Abfrage")
            // Ergebnis kommt in sdpQueryComplete.
            let result = candidate.performSDPQuery(self, uuids: [serviceUUID])
            if result != kIOReturnSuccess {
                log.error("SDP-Abfrage fehlgeschlagen: \(result, privacy: .public)")
                state = .failed("SDP-Abfrage fehlgeschlagen (\(result))")
            }
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        log.info("SDP fertig, Status \(status, privacy: .public), \(device.services?.count ?? 0, privacy: .public) Dienste")
        guard device == self.device, channel == nil else { return }
        if let record = device.getServiceRecord(for: serviceUUID) {
            openChannel(record: record)
        } else {
            for case let record as IOBluetoothSDPServiceRecord in device.services ?? [] {
                log.info("  Dienst: \(record.getServiceName() ?? "?", privacy: .public)")
            }
            state = .failed("Steuerdienst nicht gefunden – wird dieses Modell unterstützt?")
        }
    }

    private func openChannel(record: IOBluetoothSDPServiceRecord) {
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess, let device else {
            log.error("Kein RFCOMM-Kanal im Dienst")
            state = .failed("Kein RFCOMM-Kanal")
            return
        }
        log.info("Öffne RFCOMM-Kanal \(channelID, privacy: .public)")
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        if result == kIOReturnSuccess {
            channel = newChannel
        } else {
            log.error("openRFCOMMChannelAsync: \(result, privacy: .public)")
            state = .failed("Kanal konnte nicht geöffnet werden (\(result))")
        }
    }

    func disconnect() {
        channel?.close()
        channel = nil
    }

    @objc private func deviceDidConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard (device.name ?? "").localizedCaseInsensitiveContains("Buds"), channel == nil else { return }
        // Kurz warten, bis die Audioprofile stehen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.connect() }
    }

    @objc private func deviceDidDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        disconnectNotification = nil
        channelClosed()
    }

    private func channelClosed() {
        channel = nil
        isFinding = false
        status = BudsStatus()
        state = .disconnected
        rssiTimer?.invalidate()
        rssiTimer = nil
        rssi = nil
        lastSeen.budsDidDisconnect()
    }

    private func startSignalUpdates() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, let device = self.device else { return }
            let value = Int(device.rawRSSI())
            // 127 bedeutet „unbekannt“.
            self.rssi = (value == 127 || value == 0) ? nil : value
        }
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        log.info("Kanal geöffnet, Status \(error, privacy: .public)")
        guard error == kIOReturnSuccess else {
            channel = nil
            state = .failed("Kanal konnte nicht geöffnet werden (\(error))")
            return
        }
        state = .connected
        parser = MessageParser()
        disconnectNotification = device?.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDidDisconnect(_:device:))
        )
        send(BudsCommand.managerInfo())
        lastSeen.budsDidConnect()
        startSignalUpdates()
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        for message in parser.feed(bytes) {
            handle(message)
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log.info("Kanal geschlossen")
        channelClosed()
    }

    private func handle(_ message: BudsMessage) {
        log.debug("Empfangen: ID 0x\(String(message.id, radix: 16), privacy: .public), \(message.payload.count, privacy: .public) Byte")
        if message.id == MsgID.findMyEarbudsStop.rawValue {
            isFinding = false
            return
        }
        var updated = status
        if updated.apply(message) { status = updated }
    }

    // MARK: Befehle

    private func send(_ message: BudsMessage) {
        guard let channel, state == .connected else { return }
        var bytes = message.encoded()
        let result = bytes.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        if result != kIOReturnSuccess {
            NSLog("BudsBar: Senden fehlgeschlagen (\(result))")
        }
    }

    func setNoise(_ mode: NoiseMode) {
        send(BudsCommand.setNoise(mode))
        status.noiseMode = mode
    }

    func setEqualizer(_ preset: EqualizerPreset) {
        send(BudsCommand.setEqualizer(preset))
        status.equalizer = preset
    }

    func setTouchLocked(_ locked: Bool) {
        send(BudsCommand.lockTouch(locked))
        status.touchLocked = locked
    }

    func setTouch(left: TouchHoldAction, right: TouchHoldAction) {
        send(BudsCommand.setTouch(left: left, right: right))
        status.touchLeft = left
        status.touchRight = right
    }

    func toggleFind() {
        isFinding.toggle()
        send(BudsCommand.findEarbuds(isFinding))
    }
}
