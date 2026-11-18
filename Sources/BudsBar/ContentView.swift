// BudsBar – Steuerung für Samsung Galaxy Buds auf macOS
// Copyright (C) 2026 BudsBar contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import MapKit
import SwiftUI

// MARK: - Hauptansicht

struct ContentView: View {
    @EnvironmentObject var buds: BudsManager

    var body: some View {
        VStack(spacing: 12) {
            HeaderView()
            if buds.state == .connected {
                BatteryCard()
                NoiseCard()
                SettingsCard()
            }
            FindCard()
            FooterView()
        }
        .padding(14)
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.25), value: buds.state)
    }
}

// MARK: - Bausteine

/// Abgerundete Karte wie im Kontrollzentrum.
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Kopfzeile

struct HeaderView: View {
    @EnvironmentObject var buds: BudsManager

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(buds.state == .connected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                Image(systemName: "earbuds")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(buds.deviceName ?? "Galaxy Buds")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                    Text(buds.state.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if buds.state == .connecting || buds.state == .searching {
                ProgressView().controlSize(.small)
            } else if buds.state != .connected {
                Button {
                    buds.connect()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Erneut verbinden")
            }
        }
    }

    private var dotColor: Color {
        switch buds.state {
        case .connected: return .green
        case .connecting, .searching: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
}

// MARK: - Akku

struct BatteryCard: View {
    @EnvironmentObject var buds: BudsManager

    var body: some View {
        Card {
            HStack {
                BatteryRing(title: "Links", symbol: "l.circle", level: buds.status.batteryLeft, charging: buds.status.chargingLeft)
                Spacer()
                BatteryRing(title: "Rechts", symbol: "r.circle", level: buds.status.batteryRight, charging: buds.status.chargingRight)
                Spacer()
                BatteryRing(title: "Case", symbol: "earbuds.case", level: buds.status.batteryCase, charging: buds.status.chargingCase)
            }
            .padding(.horizontal, 6)
        }
    }
}

struct BatteryRing: View {
    let title: String
    let symbol: String
    let level: Int?
    let charging: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(level == nil ? .secondary : .primary)
            }
            .frame(width: 56, height: 56)
            .animation(.easeInOut(duration: 0.4), value: level)

            HStack(spacing: 2) {
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
                Text(level.map { "\($0) %" } ?? "–")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        guard let level else { return .secondary }
        if charging { return .green }
        return level <= 20 ? .red : .green
    }
}

// MARK: - Geräuschsteuerung

struct NoiseCard: View {
    @EnvironmentObject var buds: BudsManager

    var body: some View {
        Card(title: "Geräuschsteuerung") {
            HStack(spacing: 0) {
                ForEach(NoiseMode.allCases) { mode in
                    ModeButton(mode: mode, selected: buds.status.noiseMode == mode) {
                        buds.setNoise(mode)
                    }
                }
            }
        }
    }
}

struct ModeButton: View {
    let mode: NoiseMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 46, height: 46)
                    .background(
                        Circle().fill(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    )
                    .foregroundStyle(selected ? .white : .primary)
                Text(mode.label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: selected)
    }
}

extension NoiseMode {
    var symbol: String {
        switch self {
        case .off: return "speaker.wave.2"
        case .anc: return "person.and.background.dotted"
        case .ambient: return "ear"
        }
    }
}

// MARK: - Einstellungen

struct SettingsCard: View {
    @EnvironmentObject var buds: BudsManager

    var body: some View {
        Card(title: "Einstellungen") {
            SettingRow(icon: "slider.vertical.3", color: .pink, title: "Equalizer") {
                Picker("", selection: Binding(
                    get: { buds.status.equalizer ?? .off },
                    set: { buds.setEqualizer($0) }
                )) {
                    ForEach(EqualizerPreset.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider().opacity(0.5)
            SettingRow(icon: "hand.tap", color: .orange, title: "Touch sperren") {
                Toggle("", isOn: Binding(
                    get: { buds.status.touchLocked ?? false },
                    set: { buds.setTouchLocked($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            Divider().opacity(0.5)
            SettingRow(icon: "l.circle", color: .indigo, title: "Halten links") {
                touchPicker(
                    get: { buds.status.touchLeft },
                    set: { buds.setTouch(left: $0, right: buds.status.touchRight ?? .noiseControl) }
                )
            }
            SettingRow(icon: "r.circle", color: .indigo, title: "Halten rechts") {
                touchPicker(
                    get: { buds.status.touchRight },
                    set: { buds.setTouch(left: buds.status.touchLeft ?? .noiseControl, right: $0) }
                )
            }
        }
    }

    private func touchPicker(get: @escaping () -> TouchHoldAction?, set: @escaping (TouchHoldAction) -> Void) -> some View {
        Picker("", selection: Binding(get: { get() ?? .noiseControl }, set: set)) {
            ForEach(TouchHoldAction.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }
}

struct SettingRow<Control: View>: View {
    let icon: String
    let color: Color
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
            Text(title).font(.system(size: 13))
            Spacer()
            control
        }
    }
}

// MARK: - Wo ist? / Ohrhörer finden

struct FindCard: View {
    @EnvironmentObject var buds: BudsManager
    @EnvironmentObject var lastSeen: LastSeenTracker

    var body: some View {
        Card(title: "Ohrhörer finden") {
            mapArea

            if buds.state == .connected {
                HStack(spacing: 8) {
                    Image(systemName: "cellularbars", variableValue: signalLevel)
                        .foregroundStyle(Color.accentColor)
                    Text(signalText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    buds.toggleFind()
                } label: {
                    Label(buds.isFinding ? "Ton stoppen" : "Ton abspielen",
                          systemImage: buds.isFinding ? "stop.fill" : "speaker.wave.3.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(buds.isFinding ? .red : .accentColor)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder private var mapArea: some View {
        if let spot = lastSeen.spot {
            VStack(alignment: .leading, spacing: 8) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: spot.coordinate,
                    latitudinalMeters: max(400, spot.accuracy * 4),
                    longitudinalMeters: max(400, spot.accuracy * 4)
                ))) {
                    Annotation(buds.deviceName ?? "Buds", coordinate: spot.coordinate) {
                        Image(systemName: "earbuds")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Circle().fill(Color.accentColor.gradient))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .shadow(radius: 3)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .id(spot)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(buds.state == .connected ? "Bei diesem Mac" : "Zuletzt gesehen")
                            .font(.system(size: 12, weight: .semibold))
                        Text(spot.date, format: .relative(presentation: .named))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("In Karten öffnen") { openInMaps(spot) }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
        } else if !lastSeen.isAuthorized && lastSeen.authorization != .notDetermined {
            placeholder(
                icon: "location.slash",
                text: "Standortzugriff ist aus. Erlaube ihn unter Systemeinstellungen → Datenschutz & Sicherheit → Ortungsdienste."
            )
        } else if lastSeen.authorization == .notDetermined {
            VStack(alignment: .leading, spacing: 8) {
                placeholder(icon: "map", text: "Erlaube den Standortzugriff, damit BudsBar sich merkt, wo deine Buds zuletzt verbunden waren.")
                Button("Standort erlauben") { lastSeen.requestAccess() }
                    .controlSize(.small)
            }
        } else {
            placeholder(icon: "map", text: "Sobald deine Buds verbunden sind, wird ihr Ort hier gespeichert.")
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signalLevel: Double {
        guard let rssi = buds.rssi else { return 0 }
        return min(1, max(0, Double(rssi + 90) / 50))   // −90 dBm → 0, −40 dBm → 1
    }

    private var signalText: String {
        guard let rssi = buds.rssi else { return "Signalstärke wird ermittelt …" }
        switch rssi {
        case (-55)...: return "Sehr nah"
        case (-70)...: return "In der Nähe"
        default: return "Weiter entfernt"
        }
    }

    private func openInMaps(_ spot: LastSeenTracker.Spot) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: spot.coordinate))
        item.name = buds.deviceName ?? "Galaxy Buds"
        item.openInMaps()
    }
}

// MARK: - Fußzeile

struct FooterView: View {
    var body: some View {
        HStack {
            Text("BudsBar \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · nicht von Samsung")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
    }
}
