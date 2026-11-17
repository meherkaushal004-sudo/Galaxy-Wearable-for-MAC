// BudsBar – Steuerung für Samsung Galaxy Buds auf macOS
// Copyright (C) 2026 BudsBar contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOBluetooth

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
        guard candidate.isConnected() else {
            state = .disconnected
            return
        }

        state = .connecting
        if let record = candidate.getServiceRecord(for: serviceUUID) {
            openChannel(record: record)
        } else {
            // Dienst noch nicht im Cache: SDP-Abfrage starten, Ergebnis kommt in sdpQueryComplete.
            let result = candidate.performSDPQuery(self, uuids: [serviceUUID])
            if result != kIOReturnSuccess {
                state = .failed("SDP-Abfrage fehlgeschlagen (\(result))")
            }
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard device == self.device, channel == nil else { return }
        if let record = device.getServiceRecord(for: serviceUUID) {
            openChannel(record: record)
        } else {
            state = .failed("Steuerdienst nicht gefunden – wird dieses Modell unterstützt?")
        }
    }

    private func openChannel(record: IOBluetoothSDPServiceRecord) {
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess, let device else {
            state = .failed("Kein RFCOMM-Kanal")
            return
        }
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        if result == kIOReturnSuccess {
            channel = newChannel
        } else {
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
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
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
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        for message in parser.feed(bytes) {
            handle(message)
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channelClosed()
    }

    private func handle(_ message: BudsMessage) {
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
