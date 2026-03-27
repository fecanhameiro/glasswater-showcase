//
//  HydrationUpdateBroadcaster.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

@MainActor
protocol HydrationUpdateBroadcasting {
    func broadcast(snapshot: HydrationSnapshot) async
}

@MainActor
final class HydrationUpdateBroadcaster: HydrationUpdateBroadcasting {
    private let snapshotStore: HydrationSnapshotStoring
    private let settingsStore: SettingsStore
    private let liveActivity: LiveActivityServicing
    private let phoneConnectivity: (any PhoneConnectivityServicing)?
    private let minimumInterval: TimeInterval
    var watchStateBuilder: (() async throws -> WatchState)?

    private var lastBroadcastDate: Date?
    private var pendingSnapshot: HydrationSnapshot?
    private var throttleTask: Task<Void, Never>?

    init(
        snapshotStore: HydrationSnapshotStoring,
        settingsStore: SettingsStore,
        liveActivity: LiveActivityServicing,
        phoneConnectivity: (any PhoneConnectivityServicing)? = nil,
        minimumInterval: TimeInterval = 0.35
    ) {
        self.snapshotStore = snapshotStore
        self.settingsStore = settingsStore
        self.liveActivity = liveActivity
        self.phoneConnectivity = phoneConnectivity
        self.minimumInterval = minimumInterval
    }

    func broadcast(snapshot: HydrationSnapshot) async {
        pendingSnapshot = snapshot
        let now = Date()
        if let lastBroadcastDate,
           now.timeIntervalSince(lastBroadcastDate) < minimumInterval
        {
            #if DEBUG
            AppLog.info("[Broadcast] Throttled — source=\(snapshot.source.rawValue), totalMl=\(snapshot.totalMl)", category: .sync)
            #endif
            scheduleFlush(after: minimumInterval - now.timeIntervalSince(lastBroadcastDate))
            return
        }
        await flushPending()
    }

    private func scheduleFlush(after delay: TimeInterval) {
        guard throttleTask == nil else { return }
        let delayNs = UInt64(max(delay, 0) * 1_000_000_000)
        throttleTask = Task { @MainActor in
            await Task.sleepIgnoringCancellation(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            await flushPending()
        }
    }

    private func flushPending() async {
        throttleTask?.cancel()
        throttleTask = nil
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        await performBroadcast(snapshot)
    }

    private func performBroadcast(_ snapshot: HydrationSnapshot) async {
        SyncLog.info("[Sync][Broadcast] Performing — source=\(snapshot.source.rawValue), totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl), goalReached=\(snapshot.goalReached), lastIntakeMl=\(snapshot.lastIntakeMl ?? -1)")
        snapshotStore.save(snapshot)
        lastBroadcastDate = Date()

        // Reload widgets BEFORE async LA update — uses coordinator to prevent
        // WidgetKit budget exhaustion from rapid successive reloads
        WidgetReloadCoordinator.shared.requestReload(source: "broadcast(\(snapshot.source.rawValue))")

        var settings: UserSettings?
        do {
            settings = try settingsStore.loadOrCreate()
        } catch {
            AppLog.error("Failed to load settings for broadcast: \(error.localizedDescription)", category: .sync)
        }
        let hasCompletedOnboarding = settings?.hasCompletedOnboarding ?? false
        if !hasCompletedOnboarding || settings?.liveActivitiesEnabled == false {
            AppLog.info("[Broadcast] Ending LA: \(!hasCompletedOnboarding ? "onboarding incomplete" : "LA disabled")", category: .liveActivity)
            await liveActivity.end()
        } else {
            await liveActivity.update(
                currentMl: snapshot.totalMl,
                dailyGoalMl: snapshot.goalMl,
                lastIntakeMl: snapshot.lastIntakeMl,
                lastIntakeDate: snapshot.lastIntakeDate,
                customAmountMl: snapshot.customAmountMl,
                isSensitive: settings?.liveActivitySensitiveModeEnabled ?? false,
                date: snapshot.updatedAt
            )
        }

        // Send WatchState to watch — skip for watch source (prevents echo)
        let skipWatchSend = snapshot.source == .watch
        if !skipWatchSend, let watchStateBuilder {
            do {
                let watchState = try await watchStateBuilder()
                phoneConnectivity?.sendState(watchState)
                SyncLog.info("[Sync][Broadcast] Sent WatchState to watch (source=\(snapshot.source.rawValue), totalMl=\(watchState.totalMl))")
            } catch {
                SyncLog.error("[Sync][Broadcast] Failed to build WatchState: \(error.localizedDescription)")
            }
        } else if skipWatchSend {
            SyncLog.info("[Sync][Broadcast] Skipping watch send (source=\(snapshot.source.rawValue), preventing echo)")
        }
    }
}
