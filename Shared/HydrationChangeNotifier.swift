//
//  HydrationChangeNotifier.swift
//  GlassWater
//

import Foundation

/// Posts a Darwin notification to signal hydration data changes across processes.
/// Widget extensions, Live Activity intents, and the watch app post this notification
/// after saving data. The main app observes it to refresh LA/DI and in-app UI.
enum HydrationChangeNotifier {
    static let name = CFNotificationName("com.glasswater.hydrationChanged" as CFString)

    /// Post from any process (widget extension, watch, main app).
    /// Darwin notifications are signal-only — no data payload.
    /// The receiver reads fresh data from the shared App Group.
    static func post() {
        SyncLog.info("[Sync] Posting Darwin notification com.glasswater.hydrationChanged")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name, nil, nil, true
        )
    }
}
