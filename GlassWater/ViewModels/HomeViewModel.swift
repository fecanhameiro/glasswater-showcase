//
//  HomeViewModel.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    nonisolated deinit {}
    @ObservationIgnored private let services: AppServices
    private let calendar: Calendar
    private var isObservingHealth = false
    private var settings: UserSettings?
    private var undoTask: Task<Void, Never>?
    private var isLoading = false

    var todayTotalMl: Int = 0
    var todayEntries: [WaterEntry] = []
    var dailyGoalMl: Int = AppConstants.defaultDailyGoalMl
    var customAmountMl: Int = AppConstants.defaultCustomAmountMl
    var healthStatus: HealthAccessStatus = .unknown
    var goalReached: Bool = false
    var streakCount: Int = 0
    var hapticsEnabled: Bool = true
    var swimmingDuckEnabled: Bool = false
    var canUndo: Bool = false
    var recentlyAdded: Bool = false
    var shouldRequestReview: Bool = false
    var hasTipped: Bool = false
    /// Central coordinator for goal-reached → celebration → duck award lifecycle.
    let sequencer: GoalReachedSequencer
    private var lastAddedEntryId: UUID?
    private var recentlyAddedTask: Task<Void, Never>?
    private var duckSoundTask: Task<Void, Never>?
    /// Debounce task for external refresh (collapses rapid CloudKit/Darwin notifications)
    private var externalRefreshTask: Task<Void, Never>?
    /// Tracks whether the app is in foreground (set by HomeView on scenePhase changes)
    var isInForeground: Bool = false

    init(services: AppServices, calendar: Calendar = .autoupdatingCurrent) {
        self.services = services
        self.calendar = calendar
        self.sequencer = GoalReachedSequencer(
            settingsStore: services.settingsStore,
            sounds: services.sounds,
            crashReporter: services.crashReporter,
            analytics: services.analytics,
            calendar: calendar
        )
    }

    var progress: Double {
        guard dailyGoalMl > 0 else { return 0 }
        return min(Double(todayTotalMl) / Double(dailyGoalMl), 1)
    }

    var quickAddOptions: [QuickAddOption] {
        QuickAddOptions.options(forGoalMl: dailyGoalMl)
    }

    var hydrationStatus: HydrationStatus {
        guard let settings else { return .outsideWindow }
        return HydrationStatusCalculator.status(
            progress: progress,
            goalReached: goalReached,
            reminderStartMinutes: settings.reminderStartMinutes,
            reminderEndMinutes: settings.reminderEndMinutes,
            calendar: calendar
        )
    }

    /// Lightweight refresh triggered by external changes (widget, LA, watch).
    /// Debounced to collapse rapid CloudKit/Darwin notifications (can fire 80+ times per session).
    /// Fire-and-forget — callers should NOT rely on `await` to mean "refresh is done".
    func refreshFromExternalChange() {
        externalRefreshTask?.cancel()
        externalRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await refreshAndApplySideEffects(source: .external)
        }
    }

    /// Refresh triggered by in-app History edits (delete/edit).
    func refreshFromHistoryChange() async {
        await refreshAndApplySideEffects(source: .history)
    }

    /// Centralized refresh + side-effects handler.
    /// ALL data changes that come from outside `add()`/`deleteEntry()`/`updateEntry()`
    /// should go through this method to ensure consistent state.
    private enum RefreshSource { case external, history, healthSync }

    private func refreshAndApplySideEffects(source: RefreshSource) async {
        // Re-read goal from SwiftData to detect CloudKit sync changes
        if let freshSettings = try? services.settingsStore.loadOrCreate() {
            if freshSettings.dailyGoalMl != dailyGoalMl {
                AppLog.info("[Sync] goalMl changed: \(dailyGoalMl) → \(freshSettings.dailyGoalMl)", category: .sync)
                dailyGoalMl = freshSettings.dailyGoalMl
                self.settings = freshSettings
            }
        }

        let beforeTotal = todayTotalMl
        SyncLog.info("[Sync] refreshAndApply START (source=\(source)) — currentTotal=\(beforeTotal), goalMl=\(self.dailyGoalMl)")
        await refreshTodayEntries()

        // Side-effects depend on source.
        // DayGoalStatus handles "should I celebrate?" logic within goalReached().
        switch source {
        case .external, .healthSync:
            // External add (widget/LA/watch) or HealthKit sync — celebrate if goal newly reached
            if goalReached, let settings, isInForeground {
                sequencer.goalReached(settings: settings, swimmingDuckEnabled: swimmingDuckEnabled)
                swimmingDuckEnabled = settings.swimmingDuckEnabled
            } else if !goalReached, let settings {
                sequencer.goalUnreached(settings: settings)
            }
        case .history:
            // In-app history edit — cancel celebration if goal un-reached, but NEVER celebrate
            if !goalReached, let settings {
                sequencer.goalUnreached(settings: settings)
            }
        }
        updateStreakIfNeeded()

        SyncLog.info("[Sync] refreshAndApply DONE (source=\(source)) — finalTotal=\(self.todayTotalMl) (was \(beforeTotal)), entries=\(self.todayEntries.count), goalReached=\(self.goalReached)")
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let settings = try services.settingsStore.loadOrCreate()
            self.settings = settings
            dailyGoalMl = settings.dailyGoalMl
            hapticsEnabled = settings.hapticsEnabled
            swimmingDuckEnabled = settings.swimmingDuckEnabled
            streakCount = settings.streakCount
            hasTipped = settings.hasTipped

            // One-time migration: existing duck users (pre-update) get a count matching their history.
            // Guard on !hasDiscoveredDucks to prevent re-triggering after duck revoke.
            if swimmingDuckEnabled && settings.duckCount == 0 && settings.streakCount > 0 && !settings.hasDiscoveredDucks {
                let migrated = max(1, settings.streakCount)
                settings.duckCount = migrated
                settings.hasDiscoveredDucks = true
                try services.settingsStore.save()
            }
            // Show ducks only if enabled — toggle OFF hides them
            sequencer.setInitialDuckCount(settings.swimmingDuckEnabled ? settings.duckCount : 0)
            customAmountMl = QuickAddOptions.resolvedCustomAmount(
                forGoalMl: settings.dailyGoalMl,
                customAmountMl: settings.lastCustomAmountMl
            )
        } catch {
            services.crashReporter.record(error: error)
        }

        await refreshTodayEntries()

        // SwiftData may be stale after widget/LA intent writes. If the AppGroup snapshot
        // (written by the intent) says goalReached but SwiftData doesn't, adopt the snapshot total.
        if !goalReached {
            let snapshot = services.hydrationSnapshotStore.load()
            if let snap = snapshot, snap.goalReached,
               calendar.isDate(snap.dayStart, inSameDayAs: .now),
               snap.totalMl > todayTotalMl {
                AppLog.info("[Sync] SwiftData stale — adopting snapshot total \(snap.totalMl)", category: .sync)
                todayTotalMl = snap.totalMl
                goalReached = true
            }
        }

        // Migration: create LiveActivityState from existing data for users updating from v1.3.x
        if LiveActivityState.load() == nil {
            _ = migrateToLiveActivityState()
        }

        // DayGoalStatus is the single source of truth.
        // goalReached() reads the status and decides the next step automatically.
        if goalReached, let settings, isInForeground {
            sequencer.goalReached(settings: settings, swimmingDuckEnabled: swimmingDuckEnabled)
            swimmingDuckEnabled = settings.swimmingDuckEnabled
        }
        updateStreakIfNeeded()
        awardMissedDucksAndStreak()

        healthStatus = await services.healthService.authorizationStatus()
        if healthStatus == .authorized {
            await syncHealthEntries(for: .now, cachedEntries: todayEntries)
            await services.backfillPendingHealthEntries()
            await startHealthObserverIfNeeded()
        } else {
            await services.healthService.stopObservingWaterChanges()
            isObservingHealth = false
        }
        await updateReminders(applySmartRules: true)
        await broadcastSnapshotIfNeeded()
        syncUserProperties()
    }

    func add(amountMl: Int) async {
        guard amountMl > 0 else { return }
        Task { await services.notificationService.clearDeliveredReminders() }
        let wasGoalReached = goalReached
        SyncLog.info("[Sync] HomeVM.add START — amountMl=\(amountMl), previousTotal=\(self.todayTotalMl), goalMl=\(self.dailyGoalMl)")

        // Optimistic UI update for immediate, single animation trigger
        todayTotalMl += amountMl
        goalReached = todayTotalMl >= dailyGoalMl

        // Trigger visual feedback animation
        triggerRecentlyAdded()

        var entry: WaterEntry?
        do {
            entry = try services.waterStore.addEntry(
                amountMl: amountMl,
                date: .now,
                isFromHealth: false,
                healthSampleId: nil
            )
        } catch {
            services.crashReporter.record(error: error)
            // Revert optimistic update on failure
            await refreshTodayEntries()
            applyMutationSideEffects()
            return
        }

        guard let entry else { return }

        services.analytics.logEvent(AnalyticsEvents.waterAdded, parameters: [
            AnalyticsParams.amountMl: amountMl,
            AnalyticsParams.source: "app",
            AnalyticsParams.timeOfDay: AnalyticsTimeOfDay.current(calendar: calendar),
            AnalyticsParams.isCustom: false
        ])
        logFirstWaterAddedIfNeeded(amountMl: amountMl)

        // Update entries list without recalculating total
        await refreshTodayEntriesList()
        scheduleUndo(for: entry.id)
        triggerAddHapticsIfNeeded(wasGoalReached: wasGoalReached)
        updateStreakIfNeeded()

        // Broadcast BEFORE HealthKit for fast LA/widget update
        await updateReminders(applySmartRules: true)
        await broadcastSnapshot(source: .app)
        SyncLog.info("[Sync] HomeVM.add — broadcast done, optimistic total=\(self.todayTotalMl)")

        // HealthKit save (best effort, after broadcast)
        let status = await services.healthService.authorizationStatus()
        if status == .authorized {
            do {
                let sampleId = try await services.healthService.saveWaterIntake(amountMl: amountMl, date: entry.date)
                SyncLog.info("[Sync] HomeVM.add — HK saved sampleId=\(sampleId)")
                try services.waterStore.updateEntry(
                    entry,
                    amountMl: amountMl,
                    date: entry.date,
                    isFromHealth: true,
                    healthSampleId: sampleId
                )
                // Only update entries list, not totals (already correct from optimistic update)
                await refreshTodayEntriesList()
            } catch {
                SyncLog.error("[Sync] HomeVM.add — HK save failed: \(error.localizedDescription)")
                services.crashReporter.record(error: error)
            }
        }
        SyncLog.info("[Sync] HomeVM.add DONE — finalTotal=\(self.todayTotalMl), goalReached=\(self.goalReached)")
    }

    func addCustom(amountMl: Int) async {
        let clamped = QuickAddOptions.clampCustomAmount(amountMl)
        services.analytics.logEvent(AnalyticsEvents.customAmountSelected, parameters: [
            AnalyticsParams.amountMl: clamped
        ])
        await storeCustomAmount(clamped)
        customAmountMl = clamped
        await add(amountMl: clamped)
    }

    func undoLastEntry() async {
        guard canUndo, let lastAddedEntryId else { return }
        guard let entry = todayEntries.first(where: { $0.id == lastAddedEntryId }) else {
            clearUndo()
            return
        }
        if swimmingDuckEnabled {
            services.sounds.play(.flapping)
        }
        services.analytics.logEvent(AnalyticsEvents.waterUndone, parameters: nil)
        await deleteEntry(entry)
        clearUndo()
    }

    func deleteEntry(_ entry: WaterEntry) async {
        services.analytics.logEvent(AnalyticsEvents.waterDeleted, parameters: [
            AnalyticsParams.amountMl: entry.amountMl
        ])
        let sampleId = entry.healthSampleId
        let wasGoalReached = goalReached
        do {
            try services.waterStore.deleteEntry(entry)
        } catch {
            services.crashReporter.record(error: error)
            return // Abort — don't delete HK sample or broadcast stale data
        }

        if entry.id == lastAddedEntryId {
            clearUndo()
        }

        if let sampleId, await services.healthService.authorizationStatus() == .authorized {
            do {
                try await services.healthService.deleteWaterSample(id: sampleId)
            } catch {
                services.crashReporter.record(error: error)
            }
        }

        await refreshTodayEntries()
        applyMutationSideEffects()
        await updateReminders(applySmartRules: true)
        await broadcastSnapshot(source: .app)

        // Force widget reload on goal transition (reached ↔ un-reached)
        if wasGoalReached != goalReached {
            WidgetReloadCoordinator.shared.forceReload(source: "goalTransition(delete)")
        }
    }

    func updateEntry(_ entry: WaterEntry, amountMl: Int, date: Date) async {
        services.analytics.logEvent(AnalyticsEvents.waterEdited, parameters: [
            AnalyticsParams.oldValue: entry.amountMl,
            AnalyticsParams.newValue: amountMl
        ])
        let wasGoalReached = goalReached
        let oldDate = entry.date
        var newSampleId: UUID?
        var isFromHealth = false

        if await services.healthService.authorizationStatus() == .authorized {
            // Delete old sample FIRST to prevent permanent HK duplicates
            // if the new save succeeds but old delete fails
            if let oldSampleId = entry.healthSampleId {
                do {
                    try await services.healthService.deleteWaterSample(id: oldSampleId)
                } catch {
                    services.crashReporter.record(error: error)
                }
            }
            do {
                let savedId = try await services.healthService.saveWaterIntake(amountMl: amountMl, date: date)
                newSampleId = savedId
                isFromHealth = true
            } catch {
                services.crashReporter.record(error: error)
            }
        }

        do {
            try services.waterStore.updateEntry(
                entry,
                amountMl: amountMl,
                date: date,
                isFromHealth: isFromHealth,
                healthSampleId: newSampleId
            )
        } catch {
            services.crashReporter.record(error: error)
        }

        await refreshTodayEntries()
        applyMutationSideEffects()

        // When an entry moves between days, update the audit trail for both days
        // so that streak/duck state remains consistent.
        let oldDay = calendar.startOfDay(for: oldDate)
        let newDay = calendar.startOfDay(for: date)
        if !calendar.isDate(oldDay, inSameDayAs: newDay), let settings {
            do {
                let oldDayTotal = try services.waterStore.total(for: oldDate)
                if oldDayTotal < dailyGoalMl {
                    settings.unmarkDayCompleted(oldDay, calendar: calendar)
                }
                let newDayTotal = try services.waterStore.total(for: date)
                if newDayTotal >= dailyGoalMl {
                    settings.markDayCompleted(newDay, calendar: calendar)
                }
                settings.streakCount = settings.calculateStreak(calendar: calendar)
                streakCount = settings.streakCount
                try services.settingsStore.save()
            } catch {
                services.crashReporter.record(error: error)
            }
        }

        await updateReminders(applySmartRules: true)
        await broadcastSnapshot(source: .app)

        // Force widget reload on goal transition (reached ↔ un-reached)
        if wasGoalReached != goalReached {
            WidgetReloadCoordinator.shared.forceReload(source: "goalTransition(edit)")
        }
    }

    /// Centralized side-effects for direct mutations (add/delete/update from HomeViewModel).
    /// For external/history/health sync paths, use `refreshAndApplySideEffects(source:)` instead.
    private func applyMutationSideEffects() {
        if !goalReached, let settings {
            sequencer.goalUnreached(settings: settings)
        }
        updateStreakIfNeeded()
    }

    private func syncHealthEntries(for date: Date, cachedEntries: [WaterEntry]? = nil) async {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        SyncLog.info("[Sync] syncHealthEntries START")
        do {
            let samples = try await services.healthService.fetchWaterSamples(from: startOfDay, to: endOfDay)
            let localEntries = try cachedEntries ?? services.waterStore.entries(from: startOfDay, to: endOfDay)
            let localHealthEntries = localEntries.filter { $0.isFromHealth && $0.healthSampleId != nil }
            let localIds = Set(localHealthEntries.compactMap(\.healthSampleId))
            let sampleIds = Set(samples.map(\.id))

            var added = 0
            var removed = 0

            for sample in samples where !localIds.contains(sample.id) {
                // Skip if a non-health entry with matching amount+time exists nearby.
                // This happens when the phone saves to HK on behalf of the watch — the entry
                // exists (isFromHealth=false) but hasn't been updated with the real HK sampleId yet.
                let hasMatchingPendingEntry = localEntries.contains { entry in
                    !entry.isFromHealth &&
                    entry.healthSampleId == nil &&
                    entry.amountMl == sample.amountMl &&
                    abs(entry.date.timeIntervalSince(sample.date)) < 5
                }
                if hasMatchingPendingEntry {
                    SyncLog.info("[Sync] syncHealthEntries — SKIPPING add for sample \(sample.id) — matches pending non-health entry (amountMl=\(sample.amountMl))")
                    continue
                }
                _ = try services.waterStore.addEntry(
                    amountMl: sample.amountMl,
                    date: sample.date,
                    isFromHealth: true,
                    healthSampleId: sample.id
                )
                added += 1
            }

            // Only remove entries whose healthSampleId is missing from HealthKit
            // AND that are older than 60s. Entries from the watch arrive via
            // transferUserInfo before HealthKit cross-device sync completes (~5-30s).
            let removalCutoff = Date.now.addingTimeInterval(-60)
            for entry in localHealthEntries {
                guard let id = entry.healthSampleId else { continue }
                if !sampleIds.contains(id) {
                    if entry.date > removalCutoff {
                        SyncLog.info("[Sync] syncHealthEntries — SKIPPING removal of recent entry sampleId=\(id) (age=\(String(format: "%.0f", Date.now.timeIntervalSince(entry.date)))s, waiting for HK cross-device sync)")
                        continue
                    }
                    try services.waterStore.deleteEntry(entry)
                    removed += 1
                }
            }

            SyncLog.info("[Sync] syncHealthEntries — hkSamples=\(samples.count), localHealth=\(localHealthEntries.count), totalLocal=\(localEntries.count), added=\(added), removed=\(removed)")

            // In background, entries are reconciled in SwiftData but ViewModel
            // state is deferred to load() on foreground. This preserves the
            // pre-goal progress for the ring fill animation on return.
            // broadcastSnapshot + updateReminders (called by handleHealthUpdate
            // after this method) read from SwiftData/snapshot, not ViewModel.
            guard isInForeground else {
                SyncLog.info("[Sync] syncHealthEntries DONE (background, ViewModel deferred)")
                return
            }

            await refreshTodayEntries()
            if goalReached, let settings {
                sequencer.goalReached(settings: settings, swimmingDuckEnabled: swimmingDuckEnabled)
                swimmingDuckEnabled = settings.swimmingDuckEnabled
            } else if !goalReached, let settings {
                sequencer.goalUnreached(settings: settings)
            }
            updateStreakIfNeeded()
            SyncLog.info("[Sync] syncHealthEntries DONE — totalMl=\(self.todayTotalMl), entries=\(self.todayEntries.count)")
        } catch {
            SyncLog.error("[Sync] syncHealthEntries FAILED: \(error.localizedDescription)")
            services.crashReporter.record(error: error)
        }
    }

    private func updateReminders(applySmartRules: Bool = false) async {
        // Use cached settings — avoids redundant SwiftData read.
        // Settings are always fresh from load() or refreshAndApplySideEffects().
        await services.refreshNotifications(applySmartRules: applySmartRules)
    }

    private func storeCustomAmount(_ amountMl: Int) async {
        do {
            let settings = try services.settingsStore.loadOrCreate()
            self.settings = settings
            settings.lastCustomAmountMl = amountMl
            try services.settingsStore.save()
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    private func broadcastSnapshot(source: HydrationSnapshotSource) async {
        do {
            let snapshot = try services.hydrationSnapshotProvider.snapshot(for: .now, source: source)
            SyncLog.info("[Sync] broadcastSnapshot — source=\(source.rawValue), totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl)")
            await services.hydrationBroadcaster.broadcast(snapshot: snapshot)
        } catch {
            SyncLog.error("[Sync] broadcastSnapshot FAILED: \(error.localizedDescription)")
            services.crashReporter.record(error: error)
        }
    }

    private func startHealthObserverIfNeeded() async {
        guard !isObservingHealth else { return }
        isObservingHealth = true
        await services.healthService.startObservingWaterChanges { [weak self] in
            Task { @MainActor in
                await self?.handleHealthUpdate()
            }
        }
    }

    private func handleHealthUpdate() async {
        let beforeTotal = todayTotalMl
        SyncLog.info("[Sync] handleHealthUpdate START — currentTotal=\(beforeTotal)")
        await syncHealthEntries(for: .now)
        await updateReminders(applySmartRules: true)
        await broadcastSnapshot(source: .health)
        SyncLog.info("[Sync] handleHealthUpdate DONE — total: \(beforeTotal) -> \(self.todayTotalMl)")
    }

    private func broadcastSnapshotIfNeeded() async {
        guard services.hydrationSnapshotStore.load() == nil else { return }
        await broadcastSnapshot(source: .app)
    }

    private func refreshTodayEntries() async {
        let startOfDay = calendar.startOfDay(for: .now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? .now
        do {
            let entries = try services.waterStore.entries(from: startOfDay, to: endOfDay)
            let healthEntries = entries.filter { $0.isFromHealth }
            let localEntries = entries.filter { !$0.isFromHealth }
            todayEntries = entries.sorted(by: { $0.date > $1.date })
            todayTotalMl = entries.reduce(0) { $0 + $1.amountMl }
            goalReached = todayTotalMl >= dailyGoalMl
            SyncLog.info("[Sync] refreshTodayEntries — total=\(self.todayTotalMl), entries=\(entries.count) (health=\(healthEntries.count), local=\(localEntries.count)), goalReached=\(self.goalReached)")
        } catch {
            SyncLog.error("[Sync] refreshTodayEntries FAILED: \(error.localizedDescription)")
            services.crashReporter.record(error: error)
        }
    }

    /// Refreshes only the entries list without updating totals (for use after optimistic updates)
    private func refreshTodayEntriesList() async {
        let startOfDay = calendar.startOfDay(for: .now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? .now
        do {
            let entries = try services.waterStore.entries(from: startOfDay, to: endOfDay)
            todayEntries = entries.sorted(by: { $0.date > $1.date })
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    private func updateStreakIfNeeded() {
        guard let settings else { return }
        let today = calendar.startOfDay(for: .now)

        if goalReached {
            // Mark today as completed in the audit trail
            settings.markDayCompleted(today, calendar: calendar)

            if let lastCompleted = settings.lastCompletedDay,
               calendar.isDate(lastCompleted, inSameDayAs: today) {
                // Already counted today — recalculate from audit trail
                let newStreak = settings.calculateStreak(calendar: calendar)
                AppLog.info("[Streak] Recalculated from audit trail — \(settings.streakCount) → \(newStreak)", category: .userAction)
                settings.streakCount = newStreak
                streakCount = settings.streakCount
                do {
                    try services.settingsStore.save()
                } catch {
                    services.crashReporter.record(error: error)
                }
                return
            }

            let previousStreak = settings.streakCount
            settings.lastCompletedDay = today
            // Recalculate from audit trail. The audit trail only stores 30 days,
            // so for users with very old streaks (migrated from before the audit trail),
            // the calculated value may be lower. We use max() only when the calculated
            // streak reaches the audit trail limit (30), indicating it was likely
            // truncated — in that case, preserve the higher existing count + 1.
            let calculated = settings.calculateStreak(calendar: calendar)
            if calculated >= 30 && previousStreak >= 30 {
                settings.streakCount = previousStreak + 1
            } else {
                settings.streakCount = calculated
            }
            streakCount = settings.streakCount
            AppLog.info("[Streak] Updated — \(previousStreak) → \(streakCount) (lastCompleted=\(settings.lastCompletedDay?.description ?? "nil"))", category: .userAction)
            do {
                try services.settingsStore.save()
            } catch {
                services.crashReporter.record(error: error)
            }
            let milestones: Set<Int> = [3, 7, 14, 30, 60, 100]
            if milestones.contains(streakCount) {
                services.analytics.logEvent(AnalyticsEvents.streakMilestone, parameters: [
                    AnalyticsParams.streakDays: streakCount
                ])
            }
        } else {
            // Goal was un-reached (entry deleted/edited) — revert using audit trail
            if let lastCompleted = settings.lastCompletedDay,
               calendar.isDate(lastCompleted, inSameDayAs: today) {
                let previousStreak = settings.streakCount
                // Remove today from completed days
                settings.unmarkDayCompleted(today, calendar: calendar)
                // Recalculate streak from audit trail — no backward guessing needed
                settings.streakCount = settings.calculateStreak(calendar: calendar)
                settings.lastCompletedDay = settings.completedDays.first // most recent completed day
                streakCount = settings.streakCount
                AppLog.info("[Streak] Reverted — \(previousStreak) → \(streakCount) (goal un-reached)", category: .userAction)
                do {
                    try services.settingsStore.save()
                } catch {
                    services.crashReporter.record(error: error)
                }
            }
        }
    }

    private func triggerAddHapticsIfNeeded(wasGoalReached: Bool) {
        if hapticsEnabled {
            services.haptics.lightImpact()
        }

        if swimmingDuckEnabled {
            duckSoundTask?.cancel()
            services.sounds.play(.splash)
            duckSoundTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                guard !Task.isCancelled else { return }
                services.sounds.play(.quack)
            }
        }

        if goalReached && !wasGoalReached, let settings {
            // Write LiveActivityState FIRST so all surfaces (widget, intent, background)
            // see .goalReached immediately — before the async broadcast completes
            let dismissAt = Date.now.addingTimeInterval(
                TimeInterval(AppConstants.liveActivityGoalReachedDismissMinutes * 60)
            )
            var laState = LiveActivityState.load() ?? .idle(calendar: calendar)
            laState.transition(to: .goalReached, now: .now, calendar: calendar, celebrationDismissAt: dismissAt)

            AppLog.info("[Goal] Reached via in-app add — totalMl=\(todayTotalMl), goalMl=\(dailyGoalMl)", category: .userAction)
            if hapticsEnabled {
                services.haptics.success()
            }

            if swimmingDuckEnabled {
                duckSoundTask?.cancel()
                duckSoundTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.8))
                    guard !Task.isCancelled else { return }
                    services.sounds.play(.quack)
                    if hapticsEnabled { services.haptics.mediumImpact() }
                    try? await Task.sleep(for: .seconds(0.4))
                    guard !Task.isCancelled else { return }
                    services.sounds.play(.quack)
                    if hapticsEnabled { services.haptics.mediumImpact() }
                }
            }

            sequencer.goalReached(settings: settings, swimmingDuckEnabled: swimmingDuckEnabled)

            // Sync back — sequencer may have auto-enabled ducks on first discovery
            if settings.swimmingDuckEnabled != swimmingDuckEnabled {
                swimmingDuckEnabled = settings.swimmingDuckEnabled
            }

            // Review request fallback for users who disabled ducks — they won't see
            // the duck reward overlay, so trigger review request directly after celebration.
            if !swimmingDuckEnabled && settings.duckCount > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    checkAndRequestReview()
                }
            }

            services.analytics.logEvent(AnalyticsEvents.dailyGoalReached, parameters: [
                AnalyticsParams.goalMl: dailyGoalMl,
                AnalyticsParams.entriesCount: todayEntries.count
            ])
        }
    }

    // MARK: - LiveActivityState Migration

    /// Creates initial LiveActivityState from existing data for users updating from v1.3.x.
    /// Preserves all ducks, streaks, and settings — only creates the new state machine entry.
    private func migrateToLiveActivityState() -> LiveActivityState {
        var state = LiveActivityState.idle(calendar: calendar)

        if goalReached {
            if let lastAwarded = settings?.lastDuckAwardedDay,
               calendar.isDate(lastAwarded, inSameDayAs: .now) {
                // Goal reached + duck already awarded today → already celebrated
                state.transition(to: .dismissed, now: .now, calendar: calendar)
            } else {
                // Goal reached but no duck awarded → needs celebration
                let dismissAt = Date.now.addingTimeInterval(
                    TimeInterval(AppConstants.liveActivityGoalReachedDismissMinutes * 60)
                )
                state.transition(to: .goalReached, now: .now, calendar: calendar, celebrationDismissAt: dismissAt)
            }
        } else if todayTotalMl > 0 {
            state.transition(to: .inProgress, now: .now, calendar: calendar)
        } else {
            // Idle state — transition() wasn't called, so save explicitly
            state.save()
        }

        AppLog.info("[Migration] Created LiveActivityState from existing data — phase=\(state.phase.rawValue), goalReached=\(goalReached), duckCount=\(sequencer.visibleDuckCount), streakCount=\(streakCount)", category: .lifecycle)

        // Clean up old keys that are no longer used
        let appGroupDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        appGroupDefaults?.removeObject(forKey: "glasswater.goalReachedAt")
        appGroupDefaults?.removeObject(forKey: "glasswater.goalDismissedDay")
        UserDefaults.standard.removeObject(forKey: "glasswater.lastGoalCelebratedDay")

        return state
    }

    /// Awards ducks and updates streak for days where the goal was reached
    /// externally (widget, LA, watch) while the app was not open.
    /// Only runs in foreground to ensure correct visual sequence (celebration → duck).
    private func awardMissedDucksAndStreak() {
        guard isInForeground else {
            AppLog.info("[Duck] awardMissedDucksAndStreak DEFERRED — app not in foreground", category: .sync)
            return
        }
        guard let settings else { return }

        let today = calendar.startOfDay(for: .now)

        // Determine lookback range
        let lookbackStart: Date
        if let lastAwarded = settings.lastDuckAwardedDay {
            lookbackStart = calendar.date(byAdding: .day, value: 1, to: lastAwarded) ?? today
        } else {
            lookbackStart = today
        }
        let maxLookback = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let start = max(lookbackStart, maxLookback)
        guard start <= today else { return }

        // Collect days with goal reached but no duck awarded
        var goalReachedDays: [Date] = []
        var day = start
        while day <= today {
            let isAlreadyAwarded: Bool
            if let lastAwarded = settings.lastDuckAwardedDay {
                isAlreadyAwarded = calendar.isDate(lastAwarded, inSameDayAs: day)
            } else {
                isAlreadyAwarded = false
            }
            if !isAlreadyAwarded {
                let total = (try? services.waterStore.total(for: day)) ?? 0
                if total >= settings.dailyGoalMl {
                    goalReachedDays.append(day)
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        guard !goalReachedDays.isEmpty else { return }

        // --- Streak update (independent of duck opt-in) ---
        updateStreakRetroactively(goalReachedDays: goalReachedDays, today: today)

        // --- Duck award (delegated to sequencer) ---
        sequencer.awardMissedDucks(
            settings: settings,
            swimmingDuckEnabled: swimmingDuckEnabled,
            missedDays: goalReachedDays,
            todayGoalReached: goalReached
        )
        // Update swimmingDuckEnabled in case sequencer auto-enabled it (first discovery)
        swimmingDuckEnabled = settings.swimmingDuckEnabled
    }

    private func updateStreakRetroactively(goalReachedDays: [Date], today: Date) {
        guard let settings else { return }

        // Build set of all days with goal reached (including already-tracked ones)
        var completedDays = Set(goalReachedDays.map { calendar.startOfDay(for: $0) })

        // Also include days already counted by previous streak
        if let lastCompleted = settings.lastCompletedDay {
            var d = lastCompleted
            for _ in 0..<settings.streakCount {
                completedDays.insert(calendar.startOfDay(for: d))
                guard let prev = calendar.date(byAdding: .day, value: -1, to: d) else { break }
                d = prev
            }
        }

        // Count consecutive days backwards from the most recent completed day
        guard let mostRecent = completedDays.max() else { return }
        var streak = 0
        var checkDay = mostRecent
        while completedDays.contains(calendar.startOfDay(for: checkDay)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = prev
        }

        guard streak > 0, streak > settings.streakCount else { return }

        let previousStreakCount = settings.streakCount
        let previousLastCompletedDay = settings.lastCompletedDay

        // Flush all discovered days to the audit trail so calculateStreak()
        // produces the correct result on future relaunches
        for day in completedDays {
            settings.markDayCompleted(day, calendar: calendar)
        }

        settings.streakCount = streak
        settings.lastCompletedDay = mostRecent
        streakCount = streak
        do {
            try services.settingsStore.save()
        } catch {
            settings.streakCount = previousStreakCount
            settings.lastCompletedDay = previousLastCompletedDay
            streakCount = previousStreakCount
            services.crashReporter.record(error: error)
        }
    }

    #if DEBUG
    func debugResetDucks() {
        guard let settings else { return }
        settings.duckCount = 0
        settings.lastDuckAwardedDay = nil
        settings.swimmingDuckEnabled = false
        settings.hasDiscoveredDucks = false
        swimmingDuckEnabled = false
        sequencer.debugReset()
        sequencer.setInitialDuckCount(0)
        try? services.settingsStore.save()
    }

    func debugSetDuckCount(_ count: Int) {
        guard let settings else { return }
        settings.duckCount = count
        settings.lastDuckAwardedDay = nil
        sequencer.setInitialDuckCount(count)
        try? services.settingsStore.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    func debugTriggerDuckReward(asFirstTime: Bool) {
        guard let settings else { return }
        sequencer.debugTriggerDuckReward(asFirstTime: asFirstTime, settings: settings)
    }

    /// Resets everything for a clean first-duck test: goal=100ml, 0 ducks, 0 entries
    func debugResetForFirstDuckTest() async {
        guard let settings else { return }

        // Reset ducks
        settings.duckCount = 0
        settings.lastDuckAwardedDay = nil
        settings.swimmingDuckEnabled = false
        settings.hasDiscoveredDucks = false
        swimmingDuckEnabled = false
        sequencer.debugReset()
        sequencer.setInitialDuckCount(0)

        // Set easy goal
        settings.dailyGoalMl = 100
        dailyGoalMl = 100

        try? services.settingsStore.save()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)

        // Delete all today's entries
        let entriesToDelete = todayEntries
        for entry in entriesToDelete {
            try? services.waterStore.deleteEntry(entry)
        }
        await refreshTodayEntries()
        updateStreakIfNeeded()
        await broadcastSnapshot(source: .app)
    }
    #endif

    func dismissDuckReward() {
        let shouldReview = sequencer.dismissDuckReward()
        if shouldReview {
            checkAndRequestReview()
        }
    }

    func playDuckSound() {
        if swimmingDuckEnabled {
            services.sounds.playRandomQuackSingle()
            if hapticsEnabled {
                services.haptics.lightImpact()
            }
        }
    }

    func duckName(forDuckCount count: Int) -> String {
        guard count > 0 else { return "Milo" }
        let index = (count - 1) % SwimmingDuckOverlay.configurations.count
        if let custom = settings?.duckNicknames[count] { return custom }
        return NSLocalizedString("duck_name_\(index + 1)", comment: "")
    }

    func renameDuck(atCount count: Int, to name: String) {
        guard let settings else { return }
        var nicknames = settings.duckNicknames
        nicknames[count] = name
        settings.duckNicknames = nicknames
        do {
            try services.settingsStore.save()
        } catch {
            services.crashReporter.record(error: error)
        }
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    // MARK: - App Store Review

    private static let goalCompletionCountKey = "glasswater.goalCompletionCount"
    private static let lastReviewRequestDateKey = "glasswater.lastReviewRequestDate"
    private static let requiredCompletionsBeforeReview = 3
    private static let minimumDaysBetweenRequests = 60

    private func checkAndRequestReview() {
        #if DEBUG
        shouldRequestReview = true
        return
        #else
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: Self.goalCompletionCountKey) + 1
        defaults.set(count, forKey: Self.goalCompletionCountKey)

        guard count >= Self.requiredCompletionsBeforeReview else { return }

        if let lastRequest = defaults.object(forKey: Self.lastReviewRequestDateKey) as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: lastRequest, to: .now).day ?? 0
            guard daysSince >= Self.minimumDaysBetweenRequests else { return }
        }

        defaults.set(Date.now, forKey: Self.lastReviewRequestDateKey)
        defaults.set(0, forKey: Self.goalCompletionCountKey)
        shouldRequestReview = true
        #endif
    }

    private func scheduleUndo(for entryId: UUID) {
        lastAddedEntryId = entryId
        canUndo = true
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            clearUndo()
        }
    }

    private func clearUndo() {
        undoTask?.cancel()
        undoTask = nil
        canUndo = false
        lastAddedEntryId = nil
    }

    private func triggerRecentlyAdded() {
        recentlyAddedTask?.cancel()
        recentlyAdded = true
        recentlyAddedTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            recentlyAdded = false
        }
    }

    private func logFirstWaterAddedIfNeeded(amountMl: Int) {
        let key = "glasswater.analytics.firstWaterLogged"
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        guard defaults?.bool(forKey: key) != true else { return }
        defaults?.set(true, forKey: key)
        services.analytics.logEvent(AnalyticsEvents.firstWaterAdded, parameters: [
            AnalyticsParams.amountMl: amountMl,
            AnalyticsParams.source: "app"
        ])
    }

    func reloadDuckSetting() {
        services.settingsStore.invalidateCache()
        guard let settings = try? services.settingsStore.loadOrCreate() else { return }
        let wasEnabled = swimmingDuckEnabled
        swimmingDuckEnabled = settings.swimmingDuckEnabled
        hasTipped = settings.hasTipped
        AppLog.info("[Duck] reloadDuckSetting — wasEnabled=\(wasEnabled), nowEnabled=\(settings.swimmingDuckEnabled), duckCount=\(settings.duckCount)", category: .userAction)

        // Duck toggle changed
        if settings.swimmingDuckEnabled && !wasEnabled {
            // Toggled ON
            if settings.duckCount == 0 {
                // First duck — grant with reward overlay
                sequencer.grantFirstDuck(settings: settings)
            } else {
                // Already has ducks — show them in water
                sequencer.setInitialDuckCount(settings.duckCount)
            }
            settings.hasDiscoveredDucks = true
            try? services.settingsStore.save()
        } else if !settings.swimmingDuckEnabled && wasEnabled {
            // Toggled OFF — hide ducks from water (but keep count in SwiftData)
            sequencer.setInitialDuckCount(0)
        }
    }

    private func syncUserProperties() {
        guard let settings else { return }
        services.analytics.setUserProperty("\(dailyGoalMl)", forName: AnalyticsUserProps.dailyGoalMl)
        services.analytics.setUserProperty("\(settings.notificationsEnabled)", forName: AnalyticsUserProps.notificationsEnabled)
        services.analytics.setUserProperty("\(healthStatus == .authorized)", forName: AnalyticsUserProps.healthConnected)
        services.analytics.setUserProperty("\(settings.liveActivitiesEnabled)", forName: AnalyticsUserProps.liveActivitiesEnabled)
        services.analytics.setUserProperty("\(settings.hapticsEnabled)", forName: AnalyticsUserProps.hapticsEnabled)
        services.analytics.setUserProperty("\(streakCount)", forName: AnalyticsUserProps.currentStreak)
        services.analytics.setUserProperty("\(sequencer.visibleDuckCount)", forName: AnalyticsUserProps.duckCount)
        services.analytics.setUserProperty("\(settings.intelligentNotificationsEnabled)", forName: AnalyticsUserProps.smartNotificationsEnabled)
        services.analytics.setUserProperty("\(settings.hasCompletedOnboarding)", forName: AnalyticsUserProps.onboardingCompleted)
    }
}
