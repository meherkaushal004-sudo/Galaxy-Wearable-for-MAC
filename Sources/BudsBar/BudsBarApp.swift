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
                .environmentObject(buds.lastSeen)
        } label: {
            Image(systemName: buds.state == .connected ? "earbuds" : "earbuds.case")
        }
        .menuBarExtraStyle(.window)
    }
}
