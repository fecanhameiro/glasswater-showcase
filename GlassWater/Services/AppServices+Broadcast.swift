//
//  AppServices+Broadcast.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 08/02/26.
//

import Foundation

@MainActor
extension AppServices {
    /// Coalesces rapid broadcast requests (e.g., scenePhase.active + Darwin notification
    /// + CloudKit sync all firing within the same run loop when app comes to foreground).
    static var lastBroadcastRequestDate: Date?
    static let broadcastDebounceInterval: TimeInterval = 0.3

    /// Broadcasts the current hydration state from SwiftData (single source of truth).
    /// SwiftData has ALL entries from every source (app, watch, widget, HealthKit).
    /// Watch snapshots are never used here — the watch only knows its own entries
    /// and would erase entries added from other sources.
    func broadcastCurrentSnapshot(source: HydrationSnapshotSource = .app) async {
        let now = Date()
        if let last = Self.lastBroadcastRequestDate,
           now.timeIntervalSince(last) < Self.broadcastDebounceInterval {
            SyncLog.info("[Sync] broadcastCurrentSnapshot debounced (source=\(source.rawValue), \(String(format: "%.0f", now.timeIntervalSince(last) * 1000))ms since last)")
            return
        }
        Self.lastBroadcastRequestDate = now

        do {
            let snapshot = try hydrationSnapshotProvider.snapshot(for: .now, source: source)
            SyncLog.info("[Sync] broadcastCurrentSnapshot — SwiftData totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl), source=\(source.rawValue)")
            await hydrationBroadcaster.broadcast(snapshot: snapshot)
            crashReporter.setCustomValue(snapshot.goalMl > 0 ? Int(Double(snapshot.totalMl) / Double(snapshot.goalMl) * 100) : 0, forKey: "daily_progress_pct")
        } catch {
            SyncLog.error("[Sync] broadcastCurrentSnapshot FAILED: \(error.localizedDescription)")
            crashReporter.record(error: error)
        }
    }
}
