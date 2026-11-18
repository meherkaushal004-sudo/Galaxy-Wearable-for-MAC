// BudsBar – Steuerung für Samsung Galaxy Buds auf macOS
// Copyright (C) 2026 BudsBar contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreLocation
import Foundation
import os

/// Merkt sich, wo dieser Mac war, als die Buds zuletzt verbunden waren
/// (ähnlich „Zuletzt gesehen“ bei „Wo ist?“). Der Ort bleibt nur lokal auf dem Mac.
final class LastSeenTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Spot: Codable, Hashable {
        var latitude: Double
        var longitude: Double
        var accuracy: Double
        var date: Date

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    @Published private(set) var spot: Spot?
    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private let log = Logger(subsystem: "io.github.budsbar.BudsBar", category: "location")
    private let storageKey = "lastSeenSpot"
    private var refreshTimer: Timer?
    private var budsConnected = false

    var isAuthorized: Bool {
        authorization != .notDetermined && authorization != .denied && authorization != .restricted
    }

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            spot = try? JSONDecoder().decode(Spot.self, from: data)
        }
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func budsDidConnect() {
        budsConnected = true
        if authorization == .notDetermined {
            requestAccess()
        } else {
            manager.requestLocation()
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.manager.requestLocation()
        }
    }

    func budsDidDisconnect() {
        guard budsConnected else { return }
        budsConnected = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        if isAuthorized { manager.requestLocation() }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized && budsConnected { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let newSpot = Spot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            date: Date()
        )
        spot = newSpot
        if let data = try? JSONEncoder().encode(newSpot) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("Standort nicht verfügbar: \(error.localizedDescription, privacy: .public)")
    }
}
