// BudsBar – Steuerung für Samsung Galaxy Buds auf macOS
// Copyright (C) 2026 BudsBar contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run() ? 0 : 1)
        }
        BudsBarApp.main()
    }
}

struct BudsBarApp: App {
    @StateObject private var buds = BudsManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(buds)
        } label: {
            Image(systemName: buds.state == .connected ? "earbuds" : "earbuds.case")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var buds: BudsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if buds.state == .connected {
                Divider()
                batteryRow
                Divider()
                controls
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "earbuds")
                .font(.title2)
                .foregroundStyle(buds.state == .connected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(buds.deviceName ?? "Galaxy Buds").font(.headline)
                Text(buds.state.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if buds.state != .connected && buds.state != .connecting {
                Button("Verbinden") { buds.connect() }
            }
        }
    }

    private var batteryRow: some View {
        HStack {
            BatteryView(title: "Links", level: buds.status.batteryLeft, charging: buds.status.chargingLeft)
            Spacer()
            BatteryView(title: "Rechts", level: buds.status.batteryRight, charging: buds.status.chargingRight)
            Spacer()
            BatteryView(title: "Case", level: buds.status.batteryCase, charging: buds.status.chargingCase)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Geräuschsteuerung").font(.subheadline.weight(.semibold))
            Picker("Geräuschsteuerung", selection: Binding(
                get: { buds.status.noiseMode ?? .off },
                set: { buds.setNoise($0) }
            )) {
                ForEach(NoiseMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Equalizer", selection: Binding(
                get: { buds.status.equalizer ?? .off },
                set: { buds.setEqualizer($0) }
            )) {
                ForEach(EqualizerPreset.allCases) { Text($0.label).tag($0) }
            }

            Toggle("Touch-Steuerung sperren", isOn: Binding(
                get: { buds.status.touchLocked ?? false },
                set: { buds.setTouchLocked($0) }
            ))

            Text("Berühren und halten").font(.subheadline.weight(.semibold))
            Picker("Links", selection: Binding(
                get: { buds.status.touchLeft ?? .noiseControl },
                set: { buds.setTouch(left: $0, right: buds.status.touchRight ?? .noiseControl) }
            )) {
                ForEach(TouchHoldAction.allCases) { Text($0.label).tag($0) }
            }
            Picker("Rechts", selection: Binding(
                get: { buds.status.touchRight ?? .noiseControl },
                set: { buds.setTouch(left: buds.status.touchLeft ?? .noiseControl, right: $0) }
            )) {
                ForEach(TouchHoldAction.allCases) { Text($0.label).tag($0) }
            }

            Button {
                buds.toggleFind()
            } label: {
                Label(buds.isFinding ? "Suche beenden" : "Ohrhörer finden (Ton abspielen)",
                      systemImage: buds.isFinding ? "speaker.slash" : "speaker.wave.3")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .tint(buds.isFinding ? .red : nil)
            .buttonStyle(.borderedProminent)
        }
    }

    private var footer: some View {
        HStack {
            Text("BudsBar · nicht von Samsung")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

struct BatteryView: View {
    let title: String
    let level: Int?
    let charging: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: symbol)
                if charging {
                    Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green)
                }
            }
            Text(level.map { "\($0) %" } ?? "–").font(.callout.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 70)
    }

    private var symbol: String {
        guard let level else { return "battery.0percent" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
