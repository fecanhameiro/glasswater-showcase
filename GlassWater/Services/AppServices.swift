//
//  AppServices.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

struct AppServices {
    let waterStore: any WaterStore
    let settingsStore: any SettingsStore
    let healthService: any HealthKitServicing
    let notificationService: any NotificationServicing
    let haptics: any HapticsServicing
    let liveActivity: any LiveActivityServicing
    let hydrationSnapshotStore: any HydrationSnapshotStoring
    let hydrationSnapshotProvider: any HydrationSnapshotProviding
    let hydrationBroadcaster: any HydrationUpdateBroadcasting
    let phoneConnectivity: (any PhoneConnectivityServicing)?
    let sounds: any SoundServicing
    let crashReporter: any CrashReporting
    let analytics: any AnalyticsTracking
    let tipJar: any TipJarServicing
}
