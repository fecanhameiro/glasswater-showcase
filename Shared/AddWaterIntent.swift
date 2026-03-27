//
//  AddWaterIntent.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import AppIntents
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif
import Foundation
import SwiftData

#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif
#if os(iOS)
import UIKit
#endif

#if os(watchOS)
private typealias AddWaterIntentBase = AppIntent
#else
private typealias AddWaterIntentBase = LiveActivityIntent
#endif

struct AddWaterIntent: AddWaterIntentBase {
    static var title: LocalizedStringResource = "intent_add_water_title"
    static var description = IntentDescription(LocalizedStringResource("intent_add_water_description"))

    @Parameter(title: LocalizedStringResource("intent_add_water_amount_title"), default: 250)
    var amountMl: Int

    @Parameter(title: LocalizedStringResource("intent_add_water_source_title"), default: .siri)
    var source: HydrationSnapshotSourceIntent

    @Parameter(title: "Widget Family", default: "")
    var widgetFamily: String

    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard amountMl > 0 else { return .result() }
        let now = Date.now
        let container = try ModelContainerFactory.shared ?? ModelContainerFactory.makeContainer()
        let context = container.mainContext
        let store = SwiftDataWaterStore(modelContext: context)
        let settingsStore = SwiftDataSettingsStore(modelContext: context)
        let snapshotStore = AppGroupHydrationSnapshotStore()
        let snapshotProvider = HydrationSnapshotProvider(
            waterStore: store,
            settingsStore: settingsStore
        )
        let entry = try store.addEntry(
            amountMl: amountMl,
            date: now,
            isFromHealth: false,
            healthSampleId: nil
        )

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        // Snapshot + LA update — runs first for fastest visual feedback
        do {
            let settings = try settingsStore.loadOrCreate()
            let snapshot = try snapshotProvider.snapshot(for: now, source: source.snapshotSource)
            AppLog.info("[Intent] Broadcasting — source=\(source.rawValue), totalMl=\(snapshot.totalMl), amountMl=\(amountMl)", category: .userAction)
            snapshotStore.save(snapshot)
            if settings.liveActivitiesEnabled {
                await updateLiveActivityIfPossible(
                    snapshot: snapshot,
                    settings: settings,
                    isSensitive: settings.liveActivitySensitiveModeEnabled,
                    date: snapshot.updatedAt
                )
            } else {
                await endLiveActivityIfPossible(snapshot: snapshot)
            }
        } catch {
            AppLog.error("[Intent] Snapshot/LA update failed: \(error.localizedDescription)", category: .userAction)
            #if canImport(FirebaseCrashlytics) && !DEBUG
            Crashlytics.crashlytics().record(error: error)
            #endif
        }

        // Widget reload — uses coordinator to prevent WidgetKit budget exhaustion
        WidgetReloadCoordinator.shared.requestReload(source: "intent(\(source.rawValue))")

        // Signal main app to refresh LA/DI and in-app UI
        HydrationChangeNotifier.post()

        // HealthKit — best effort, runs after visual update
        do {
            if let sampleId = try await saveHealthSampleIfPossible(amountMl: amountMl, date: entry.date) {
                try store.updateEntry(
                    entry,
                    amountMl: amountMl,
                    date: entry.date,
                    isFromHealth: true,
                    healthSampleId: sampleId
                )
            }
        } catch {
            // HealthKit failed — entry already saved to SwiftData, log for visibility
            AppLog.error("[Intent] HealthKit save failed: \(error.localizedDescription)", category: .health)
            #if canImport(FirebaseCrashlytics) && !DEBUG
            Crashlytics.crashlytics().record(error: error)
            #endif
        }

        #if canImport(FirebaseCrashlytics) && !DEBUG
        Crashlytics.crashlytics().setCustomValue(source.rawValue, forKey: "last_water_add_source")
        #endif

        var analyticsParams: [String: String] = [
            "amount_ml": "\(amountMl)",
            "source": source.rawValue,
            "time_of_day": timeOfDayForAnalytics()
        ]
        if !widgetFamily.isEmpty {
            analyticsParams["widget_family"] = widgetFamily
        }
        AnalyticsEventQueue().enqueue("water_added", parameters: analyticsParams)
        return .result()
    }

    private func timeOfDayForAnalytics() -> String {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "morning"
        case 12..<18: return "afternoon"
        default: return "evening"
        }
    }
}

@MainActor
private func saveHealthSampleIfPossible(amountMl: Int, date: Date) async throws -> UUID? {
    #if canImport(HealthKit)
    if Bundle.main.bundleURL.pathExtension == "appex" {
        return nil
    }
    guard HKHealthStore.isHealthDataAvailable(),
          let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
    else {
        return nil
    }

    let healthStore = HKHealthStore()
    let status = healthStore.authorizationStatus(for: waterType)
    guard status == .sharingAuthorized else { return nil }

    let unit = HKUnit.literUnit(with: .milli)
    let quantity = HKQuantity(unit: unit, doubleValue: Double(amountMl))
    let sample = HKQuantitySample(type: waterType, quantity: quantity, start: date, end: date)

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        healthStore.save(sample) { _, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: ())
        }
    }
    return sample.uuid
    #else
    return nil
    #endif
}

@MainActor
private func updateLiveActivityIfPossible(
    snapshot: HydrationSnapshot,
    settings: UserSettings,
    isSensitive: Bool,
    date: Date
) async {
    #if canImport(ActivityKit)
    var activities = Activity<GlassWaterLiveActivityAttributes>.activities
    var retryCount = 0
    if activities.isEmpty {
        // Exponential backoff: ActivityKit can take up to ~2s to populate
        // activities on cold launch (app terminated, after app update, etc.)
        let retryDelays: [UInt64] = [100_000_000, 200_000_000, 400_000_000, 800_000_000]
        for (index, delay) in retryDelays.enumerated() {
            #if DEBUG
            AppLog.warning("[Intent] activities.isEmpty — retry \(index + 1)/\(retryDelays.count) after \(delay / 1_000_000)ms", category: .liveActivity)
            #endif
            try? await Task.sleep(nanoseconds: delay)
            activities = Activity<GlassWaterLiveActivityAttributes>.activities
            retryCount = index + 1
            if !activities.isEmpty { break }
        }
    }
    guard !activities.isEmpty else {
        AppLog.error("[Intent] activities still empty after \(retryCount) retries (~1.5s) — skipping direct LA update", category: .liveActivity)
        #if canImport(FirebaseCrashlytics) && !DEBUG
        let error = GlassWaterError.liveActivityUpdateFailed(
            reason: "activities empty after \(retryCount) retries"
        )
        Crashlytics.crashlytics().record(error: error)
        #endif
        AnalyticsEventQueue().enqueue(
            "live_activity_update_failed",
            parameters: [
                "reason": "activities_empty",
                "retry_count": "\(retryCount)"
            ]
        )
        return
    }
    if retryCount > 0 {
        AppLog.info("[Intent] activities found after \(retryCount) retries", category: .liveActivity)
    }
    let calendar = Calendar.autoupdatingCurrent
    let dayStart = calendar.startOfDay(for: date)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

    // Day-change detection: if an activity belongs to a previous day, end it
    // and let the Darwin notification trigger a fresh one for today.
    // Check both staleDate (set to endOfDay when created) and activityState.
    var hasStaleActivities = false
    for activity in activities {
        let isStaleByDate = activity.content.staleDate.map { $0 <= dayStart } ?? false
        let isDismissed = activity.activityState == .dismissed || activity.activityState == .ended
        if isStaleByDate || isDismissed {
            let reason = isDismissed ? "zombie(\(activity.activityState))" : "staleDate<=dayStart"
            AppLog.info("[Intent] Ending stale activity (staleDate=\(activity.content.staleDate?.formatted() ?? "nil"), state=\(activity.activityState), reason=\(reason))", category: .liveActivity)
            let finalState = LiveActivityContentStateFactory.make(
                currentMl: 0,
                dailyGoalMl: settings.dailyGoalMl,
                lastIntakeMl: nil,
                lastIntakeDate: nil,
                isSensitive: isSensitive,
                customAmountMl: snapshot.customAmountMl
            )
            let finalContent = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
            hasStaleActivities = true
        }
    }
    if hasStaleActivities {
        // Re-read activities after ending stale ones
        activities = Activity<GlassWaterLiveActivityAttributes>.activities
        if activities.isEmpty {
            // All activities were stale — let the Darwin notification
            // (HydrationChangeNotifier.post below) trigger the main app's
            // LiveActivityService to start a fresh activity for today.
            AppLog.info("[Intent] All stale activities ended — main app will create new one via Darwin notification", category: .liveActivity)
            return
        }
    }

    // Filter out zombie activities — ActivityKit doesn't remove them instantly
    // after end(). Updating a zombie can revive it in the Dynamic Island.
    let preFilterCount = activities.count
    let liveActivities = activities.filter {
        $0.activityState != .ended && $0.activityState != .dismissed
    }
    if liveActivities.count < preFilterCount {
        AppLog.info("[Intent] Filtered \(preFilterCount - liveActivities.count) zombie activities (ended/dismissed)", category: .liveActivity)
    }

    // Goal dismissal check — uses LiveActivityState as single source of truth.
    // Prevents reviving the LA after the 30-min celebration ended.
    let laState = LiveActivityState.load()
    if snapshot.goalReached {
        let isDismissedToday = laState?.phase == .dismissed && (laState?.isToday(calendar: calendar) ?? false)
        if isDismissedToday {
            AppLog.info("[Intent] Goal already dismissed for today — ending remaining activities", category: .liveActivity)
            let contentState = LiveActivityContentStateFactory.make(
                currentMl: snapshot.totalMl,
                dailyGoalMl: settings.dailyGoalMl,
                lastIntakeMl: snapshot.lastIntakeMl,
                lastIntakeDate: snapshot.lastIntakeDate,
                isSensitive: isSensitive,
                customAmountMl: snapshot.customAmountMl
            )
            let finalContent = ActivityContent(state: contentState, staleDate: nil)
            for activity in liveActivities {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
            return
        }

        // All activities are zombies (ended/dismissed) — mark dismissed via state machine
        if liveActivities.isEmpty {
            var newState = laState ?? .idle(calendar: calendar)
            newState.transition(to: .dismissed, now: date, calendar: calendar)
            AppLog.info("[Intent] All goal-reached activities are zombies — marked dismissed for today", category: .liveActivity)
            return
        }
    }

    activities = liveActivities
    guard !activities.isEmpty else {
        AppLog.info("[Intent] All activities are zombies — skipping direct update", category: .liveActivity)
        return
    }

    for activity in activities {
        let goal = settings.dailyGoalMl
        if activity.attributes.dailyGoalMl != goal {
            AppLog.info("[Intent] Goal mismatch (LA=\(activity.attributes.dailyGoalMl), current=\(goal)) — updating content state (main app will reconcile)", category: .liveActivity)
        }
        let contentState = LiveActivityContentStateFactory.make(
            currentMl: snapshot.totalMl,
            dailyGoalMl: goal,
            lastIntakeMl: snapshot.lastIntakeMl,
            lastIntakeDate: snapshot.lastIntakeDate,
            isSensitive: isSensitive,
            customAmountMl: snapshot.customAmountMl
        )
        let content = ActivityContent(state: contentState, staleDate: endOfDay)
        // When goal is reached, end the LA with .after(dismissAt) so the system
        // guarantees removal after 2 min — even if the app stays in background.
        // The DI disappears immediately; Lock Screen shows celebration until dismissAt.
        if contentState.goalReached {
            // Do NOT write DayGoalStatus here — the intent may have a stale goalMl
            // (from SwiftData before CloudKit sync). Let the app process handle
            // DayGoalStatus transitions using the correct goalMl.

            // Transition LiveActivityState for DI/Lock Screen display only.
            let dismissAt = date.addingTimeInterval(
                TimeInterval(AppConstants.liveActivityGoalReachedDismissMinutes * 60)
            )
            if laState?.phase != .goalReached || laState?.isToday(calendar: calendar) != true {
                var newState: LiveActivityState
                if let existing = laState, existing.isToday(calendar: calendar) {
                    newState = existing
                } else {
                    newState = .idle(calendar: calendar)
                }
                newState.transition(to: .goalReached, now: date, calendar: calendar, celebrationDismissAt: dismissAt)
            }
            let goalContent = ActivityContent(state: contentState, staleDate: nil)
            await activity.end(goalContent, dismissalPolicy: .after(dismissAt))
            AppLog.info("[Intent] Goal reached — ended LA with auto-dismiss at \(dismissAt.formatted(date: .omitted, time: .shortened))", category: .liveActivity)
            continue
        }

        AppLog.info("[Intent] Updated LA: \(snapshot.totalMl)ml / \(settings.dailyGoalMl)ml", category: .liveActivity)
        await activity.update(content)
    }
    #endif
}

@MainActor
private func endLiveActivityIfPossible(snapshot: HydrationSnapshot) async {
    #if canImport(ActivityKit)
    let calendar = Calendar.autoupdatingCurrent
    let dayStart = calendar.startOfDay(for: snapshot.updatedAt)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    let contentState = LiveActivityContentStateFactory.make(
        currentMl: snapshot.totalMl,
        dailyGoalMl: snapshot.goalMl,
        lastIntakeMl: snapshot.lastIntakeMl,
        lastIntakeDate: snapshot.lastIntakeDate,
        isSensitive: false,
        customAmountMl: snapshot.customAmountMl
    )
    let content = ActivityContent(state: contentState, staleDate: endOfDay)
    for activity in Activity<GlassWaterLiveActivityAttributes>.activities {
        await activity.end(content, dismissalPolicy: .immediate)
    }
    #endif
}

struct GlassWaterShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddWaterIntent(),
            phrases: [
                "Add water in \(.applicationName)",
                "Log water in \(.applicationName)",
                "Adicionar água no \(.applicationName)",
                "Añadir agua en \(.applicationName)",
                "Ajouter de l'eau dans \(.applicationName)",
                "Wasser hinzufügen in \(.applicationName)",
                "Aggiungi acqua in \(.applicationName)",
                "Добавить воду в \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("app_intent_add_water_short_title"),
            systemImageName: "drop.fill"
        )
    }
}
