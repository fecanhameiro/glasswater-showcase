//
//  GlassWaterWatchApp.swift
//  GlassWaterWatch Watch App
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI
import WatchConnectivity

@main
struct GlassWaterWatchApp: App {
    private let connectivityService: WatchConnectivityService?

    init() {
        if WCSession.isSupported() {
            connectivityService = WatchConnectivityService()
        } else {
            connectivityService = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(connectivityService: connectivityService)
        }
    }
}
