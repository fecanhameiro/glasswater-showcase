//
//  HydrationSnapshotStore.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

protocol HydrationSnapshotStoring: Sendable {
    func load() -> HydrationSnapshot?
    func save(_ snapshot: HydrationSnapshot)
}

final class AppGroupHydrationSnapshotStore: HydrationSnapshotStoring, @unchecked Sendable {
    // UserDefaults is thread-safe, so @unchecked Sendable is appropriate
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(appGroupIdentifier: String = AppConstants.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    func load() -> HydrationSnapshot? {
        // Force re-read from disk — critical for cross-process reads
        // (widget extension may have stale cache when app process just wrote)
        defaults?.synchronize()
        guard let data = defaults?.data(forKey: AppConstants.appGroupHydrationSnapshotKey) else {
            SyncLog.info("[Sync] SnapshotStore.load — no data in AppGroup")
            return nil
        }
        do {
            let snapshot = try decoder.decode(HydrationSnapshot.self, from: data)
            SyncLog.info("[Sync] SnapshotStore.load — totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl), source=\(snapshot.source.rawValue), age=\(String(format: "%.1f", Date.now.timeIntervalSince(snapshot.updatedAt)))s")
            return snapshot
        } catch {
            SyncLog.error("[Sync] SnapshotStore.load FAILED: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ snapshot: HydrationSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            defaults?.set(data, forKey: AppConstants.appGroupHydrationSnapshotKey)
            defaults?.synchronize()
            SyncLog.info("[Sync] SnapshotStore.save — totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl), source=\(snapshot.source.rawValue), goalReached=\(snapshot.goalReached), bytes=\(data.count)")
        } catch {
            SyncLog.error("[Sync] SnapshotStore.save FAILED: \(error.localizedDescription)")
        }
    }
}

final class InMemoryHydrationSnapshotStore: HydrationSnapshotStoring, @unchecked Sendable {
    // Used only in previews with single-threaded access
    private var snapshot: HydrationSnapshot?

    func load() -> HydrationSnapshot? {
        snapshot
    }

    func save(_ snapshot: HydrationSnapshot) {
        self.snapshot = snapshot
    }
}
