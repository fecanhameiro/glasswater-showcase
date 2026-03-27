//
//  BackgroundRefreshService.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import ActivityKit
import BackgroundTasks
import Foundation
import SwiftData

final class BackgroundRefreshService {
    private let taskIdentifier: String
    private let midnightTaskIdentifier: String
    private let calendar: Calendar
    private let containerLock = NSLock()
    private var cachedContainer: ModelContainer?

    init(
        taskIdentifier: String = AppConstants.backgroundRefreshTaskIdentifier,
        midnightTaskIdentifier: String = AppConstants.backgroundMidnightRefreshTaskIdentifier,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.taskIdentifier = taskIdentifier
        self.midnightTaskIdentifier = midnightTaskIdentifier
        self.calendar = calendar
    }

    private func container() throws -> ModelContainer {
        containerLock.lock()
        defer { containerLock.unlock() }
        if let cachedContainer { return cachedContainer }
        let container = try ModelContainerFactory.makeContainer()
        cachedContainer = container
        return container
    }

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleAppRefresh(task: refreshTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: midnightTaskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleMidnightRefresh(task: refreshTask)
        }
    }

    func schedule() {
        // Regular 15-minute refresh
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = calendar.date(byAdding: .minute, value: 15, to: .now)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLog.error("Failed to schedule background refresh: \(error.localizedDescription)", category: .lifecycle)
            FirebaseCrashReportingService().record(error: error)
        }
    }

    /// Schedules a background refresh near midnight to handle day rollover.
    /// Uses a **separate task identifier** so it is not replaced by the
    /// regular 15-minute `schedule()` requests.
    func scheduleMidnightRefresh() {
        let tomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        // 2-minute buffer after midnight to ensure we're solidly in the new day
        let midnightTarget = tomorrow.addingTimeInterval(120)

        guard midnightTarget.timeIntervalSinceNow > 0,
              midnightTarget.timeIntervalSinceNow < 86_400
        else { return }

        let request = BGAppRefreshTaskRequest(identifier: midnightTaskIdentifier)
        request.earliestBeginDate = midnightTarget
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLog.info("[BGRefresh] Scheduled midnight refresh at \(midnightTarget.formatted(date: .abbreviated, time: .shortened))", category: .lifecycle)
        } catch {
            AppLog.error("Failed to schedule midnight refresh: \(error.localizedDescription)", category: .lifecycle)
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        schedule()

        let work = Task { await refreshReminders() }
        task.expirationHandler = {
            work.cancel()
        }

        Task {
            _ = await work.result
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }

    private func handleMidnightRefresh(task: BGAppRefreshTask) {
        // Re-arm for the next midnight
        scheduleMidnightRefresh()

        let work = Task { await refreshReminders() }
        task.expirationHandler = {
            work.cancel()
        }

        Task {
            _ = await work.result
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }

    @MainActor
    private func refreshReminders() async {
        AppLog.info("[BGRefresh] refreshReminders started", category: .lifecycle)
        do {
            let context = try container().mainContext
            let settingsStore = SwiftDataSettingsStore(modelContext: context)
            let waterStore = SwiftDataWaterStore(modelContext: context)
            let notificationService = NotificationService(crashReporter: FirebaseCrashReportingService())
            let settings = try settingsStore.loadOrCreate()
            let total = try waterStore.total(for: .now)
            let latestEntry = try waterStore.latestTodayEntry(for: .now)
            let lastEntryDate = latestEntry?.date
            await notificationService.updateReminders(
                isEnabled: settings.notificationsEnabled,
                currentTotalMl: total,
                dailyGoalMl: settings.dailyGoalMl,
                customAmountMl: settings.lastCustomAmountMl,
                reminderStartMinutes: settings.reminderStartMinutes,
                reminderEndMinutes: settings.reminderEndMinutes,
                reminderIntervalMinutes: settings.reminderIntervalMinutes,
                lastEntryDate: lastEntryDate,
                streakCount: settings.streakCount,
                date: .now
            )
            let snapshotStore = AppGroupHydrationSnapshotStore()
            let existingSnapshot = snapshotStore.load()
            let goalMl = settings.dailyGoalMl
            // Only fall back to existing snapshot's lastIntake if it's from today.
            // After midnight, yesterday's last intake should not carry over.
            let existingIsToday = existingSnapshot.map {
                calendar.isDate($0.dayStart, inSameDayAs: .now)
            } ?? false
            let snapshot = HydrationSnapshot(
                updatedAt: .now,
                dayStart: calendar.startOfDay(for: .now),
                totalMl: total,
                goalMl: goalMl,
                progress: goalMl > 0 ? min(Double(total) / Double(goalMl), 1) : 0,
                remainingMl: max(goalMl - total, 0),
                goalReached: goalMl > 0 && total >= goalMl,
                lastIntakeMl: latestEntry?.amountMl ?? (existingIsToday ? existingSnapshot?.lastIntakeMl : nil),
                lastIntakeDate: latestEntry?.date ?? (existingIsToday ? existingSnapshot?.lastIntakeDate : nil),
                customAmountMl: QuickAddOptions.clampCustomAmount(
                    settings.lastCustomAmountMl ?? AppConstants.defaultCustomAmountMl
                ),
                source: .background
            )
            let liveActivityService = LiveActivityService(allowStartWhenNeeded: false)
            let laState = LiveActivityState.load()
            let activityCount = Activity<GlassWaterLiveActivityAttributes>.activities.count
            AppLog.info("[BGRefresh] LA decision — totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl), goalReached=\(snapshot.goalReached), phase=\(laState?.phase.rawValue ?? "nil"), activities=\(activityCount), laEnabled=\(settings.liveActivitiesEnabled)", category: .liveActivity)

            // Use LiveActivityState as single source of truth:
            // - dismissed today → end (don't revive)
            // - goalReached + celebration expired → LiveActivityService.update() handles transition to dismissed
            // - otherwise → normal update
            let isDismissedToday = laState?.phase == .dismissed && (laState?.isToday(calendar: calendar) ?? false)
            if settings.liveActivitiesEnabled,
               !(snapshot.goalReached && isDismissedToday) {
                await liveActivityService.update(
                    currentMl: snapshot.totalMl,
                    dailyGoalMl: snapshot.goalMl,
                    lastIntakeMl: snapshot.lastIntakeMl,
                    lastIntakeDate: snapshot.lastIntakeDate,
                    customAmountMl: snapshot.customAmountMl,
                    isSensitive: settings.liveActivitySensitiveModeEnabled,
                    date: snapshot.updatedAt
                )
            } else {
                await liveActivityService.end()
            }
            snapshotStore.save(snapshot)
            WidgetReloadCoordinator.shared.requestReload(source: "backgroundRefresh")
        } catch {
            AppLog.error("Background refresh failed: \(error.localizedDescription)", category: .lifecycle)
            FirebaseCrashReportingService().record(error: error)
        }
    }
}
