//
//  ModelContainerFactory.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import SwiftData

// MARK: - Container Factory

enum ModelContainerFactory {
    /// Set by `GlassWaterApp.init()` so that `LiveActivityIntent` running
    /// in the app process reuses the same container (avoids dual-container issues).
    @MainActor static var shared: ModelContainer?

    /// Creates the container with graceful fallback (never crashes):
    /// 1. App Group + CloudKit sync (if requested)
    /// 2. App Group only (no CloudKit) — handles locked keychain on cold boot
    /// 3. Default local container — last resort
    /// 4. In-memory container — absolute fallback
    static func makeContainerWithFallback(cloudKitSync: Bool = false) -> ModelContainer {
        // Attempt 1: Full configuration
        if let container = try? makeContainer(cloudKitSync: cloudKitSync) {
            return container
        }

        AppLog.error("[Fatal] Container creation failed with cloudKitSync=\(cloudKitSync), retrying without CloudKit", category: .lifecycle)
        // Crashlytics logging happens in GlassWaterApp.init() caller

        // Attempt 2: App Group but no CloudKit (handles locked keychain on cold boot)
        if cloudKitSync, let container = try? makeContainer(cloudKitSync: false) {
            AppLog.warning("[Lifecycle] SwiftData container recovered with local-only mode (no CloudKit)", category: .lifecycle)
            return container
        }

        AppLog.error("[Fatal] Container creation failed even without CloudKit, using default container", category: .lifecycle)

        // Attempt 3: Plain default container (no App Group, no CloudKit)
        let schema = Schema([WaterEntry.self, UserSettings.self])
        if let container = try? ModelContainer(for: schema) {
            AppLog.warning("[Lifecycle] SwiftData container recovered with default local store (no App Group)", category: .lifecycle)
            return container
        }

        // Attempt 4: In-memory only (absolute last resort)
        // In-memory fallback — data won't persist but app won't crash
        AppLog.error("[Fatal] All container strategies failed, using in-memory store", category: .lifecycle)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// Creates the shared ModelContainer.
    /// - Parameter cloudKitSync: Pass `true` from the main app to enable iCloud sync.
    ///   Extensions (widget, intent) should pass `false` since they lack the iCloud entitlement.
    static func makeContainer(cloudKitSync: Bool = false) throws -> ModelContainer {
        let schema = Schema([WaterEntry.self, UserSettings.self])
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) {
            let storeURL = groupURL.appendingPathComponent("\(AppConstants.sharedStoreName).sqlite")
            let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = cloudKitSync
                ? .private("iCloud.com.glasswater.app")
                : .none
            let configuration = ModelConfiguration(
                AppConstants.sharedStoreName,
                schema: schema,
                url: storeURL,
                cloudKitDatabase: cloudKitDatabase
            )
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        }

        // Fallback to a local store when the App Group is unavailable (e.g. previews).
        return try ModelContainer(for: schema)
    }
}
