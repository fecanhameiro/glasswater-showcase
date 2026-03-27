//
//  LiveActivityService.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import ActivityKit
import FirebaseCrashlytics
import Foundation

protocol LiveActivityServicing {
    func update(
        currentMl: Int,
        dailyGoalMl: Int,
        lastIntakeMl: Int?,
        lastIntakeDate: Date?,
        customAmountMl: Int?,
        isSensitive: Bool,
        date: Date
    ) async
    func end() async
}

@MainActor
final class LiveActivityService: LiveActivityServicing {
    private let calendar: Calendar
    private let allowStartWhenNeeded: Bool
    private let analytics: (any AnalyticsTracking)?
    private var currentDayStart: Date?
    private var lastContentState: GlassWaterLiveActivityAttributes.ContentState?

    init(
        calendar: Calendar = .autoupdatingCurrent,
        allowStartWhenNeeded: Bool = true,
        analytics: (any AnalyticsTracking)? = nil
    ) {
        self.calendar = calendar
        self.allowStartWhenNeeded = allowStartWhenNeeded
        self.analytics = analytics
    }

    func update(
        currentMl: Int,
        dailyGoalMl: Int,
        lastIntakeMl: Int?,
        lastIntakeDate: Date?,
        customAmountMl: Int?,
        isSensitive: Bool,
        date: Date
    ) async {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            AppLog.warning("Live Activities not enabled (areActivitiesEnabled=false). Check Settings > GlassWater > Live Activities.", category: .liveActivity)
            return
        }

        let dayStart = calendar.startOfDay(for: date)
        var state = LiveActivityState.load() ?? .idle(calendar: calendar)
        let goalReached = dailyGoalMl > 0 && currentMl >= dailyGoalMl
        var dayChanged = false

        // ── Day change detection ──────────────────────────────────────
        if currentDayStart == nil {
            currentDayStart = dayStart

            // Cold-launch: check for stale activities from a PREVIOUS day
            let staleActivities = Activity<GlassWaterLiveActivityAttributes>.activities.filter {
                guard $0.activityState != .ended && $0.activityState != .dismissed else { return false }
                guard let staleDate = $0.content.staleDate else { return false }
                return staleDate <= dayStart
            }
            let aliveActivities = Activity<GlassWaterLiveActivityAttributes>.activities.filter {
                $0.activityState != .dismissed && $0.activityState != .ended
            }

            // Also detect day change from persisted state
            if !state.isToday(calendar: calendar) {
                state.transition(to: .newDay, now: date, calendar: calendar)
            }

            if !staleActivities.isEmpty {
                if !allowStartWhenNeeded {
                    AppLog.info("Cold launch (background): updating \(staleActivities.count) stale activities to new-day state", category: .liveActivity)
                    let newDayState = LiveActivityContentStateFactory.make(
                        currentMl: 0, dailyGoalMl: dailyGoalMl,
                        lastIntakeMl: nil, lastIntakeDate: nil,
                        isSensitive: isSensitive, customAmountMl: customAmountMl
                    )
                    let newDayContent = ActivityContent(state: newDayState, staleDate: endOfDay(for: dayStart))
                    for activity in staleActivities {
                        await activity.update(newDayContent)
                    }
                    if aliveActivities.isEmpty { return }
                } else {
                    AppLog.info("Cold launch: ending \(staleActivities.count) stale activities from previous day", category: .liveActivity)
                    let emptyContent = ActivityContent(
                        state: LiveActivityContentStateFactory.make(
                            currentMl: 0, dailyGoalMl: dailyGoalMl,
                            lastIntakeMl: nil, lastIntakeDate: nil,
                            isSensitive: isSensitive, customAmountMl: customAmountMl
                        ),
                        staleDate: nil
                    )
                    for activity in staleActivities {
                        await activity.end(emptyContent, dismissalPolicy: .immediate)
                    }
                    dayChanged = true
                }
            }
        } else if currentDayStart != dayStart {
            currentDayStart = dayStart
            lastContentState = nil
            state.transition(to: .newDay, now: date, calendar: calendar)

            if !allowStartWhenNeeded {
                let activities = Activity<GlassWaterLiveActivityAttributes>.activities
                if !activities.isEmpty {
                    AppLog.info("Day changed in background — updating \(activities.count) activities to new-day state", category: .liveActivity)
                    let newDayState = LiveActivityContentStateFactory.make(
                        currentMl: 0, dailyGoalMl: dailyGoalMl,
                        lastIntakeMl: nil, lastIntakeDate: nil,
                        isSensitive: isSensitive, customAmountMl: customAmountMl
                    )
                    let newDayContent = ActivityContent(state: newDayState, staleDate: endOfDay(for: dayStart))
                    for activity in activities {
                        await activity.update(newDayContent)
                    }
                    lastContentState = newDayState
                } else {
                    AppLog.info("Day changed in background — no activities to update", category: .liveActivity)
                }
                return
            }
            dayChanged = true
            analytics?.logEvent(AnalyticsEvents.liveActivityEnded, parameters: [
                AnalyticsParams.reason: "day_changed"
            ])
            await endActivities(dismissalPolicy: .immediate)
        }

        // ── Build content state ───────────────────────────────────────
        let contentState = LiveActivityContentStateFactory.make(
            currentMl: currentMl,
            dailyGoalMl: dailyGoalMl,
            lastIntakeMl: lastIntakeMl,
            lastIntakeDate: lastIntakeDate,
            isSensitive: isSensitive,
            customAmountMl: customAmountMl
        )
        let isDuplicateState = lastContentState == contentState

        var activities = Activity<GlassWaterLiveActivityAttributes>.activities

        // Filter zombie activities
        let zombieCount = activities.count
        activities = activities.filter {
            $0.activityState != .ended && $0.activityState != .dismissed
        }
        if activities.count < zombieCount {
            AppLog.info("Filtered \(zombieCount - activities.count) zombie activities (ended/dismissed)", category: .liveActivity)
        }

        if dayChanged, !activities.isEmpty {
            AppLog.info("Day changed but \(activities.count) activities still present after end() — treating as empty to start fresh", category: .liveActivity)
            activities = []
        }

        // ── State machine decisions ───────────────────────────────────

        // Dismissed today → don't revive LA
        if state.phase == .dismissed && state.isToday(calendar: calendar) {
            if !goalReached {
                // User un-reached goal → allow restart
                state.transition(to: .inProgress, now: date, calendar: calendar)
                AppLog.info("Goal was dismissed but user un-reached goal — allowing LA restart", category: .liveActivity)
            } else if activities.isEmpty {
                AppLog.info("Goal already dismissed for today — skipping LA restart", category: .liveActivity)
                return
            } else {
                AppLog.warning("Goal dismissed for today but \(activities.count) activities still active — ending them", category: .liveActivity)
                await endActivities(contentState: contentState, dismissalPolicy: .immediate)
                return
            }
        }

        // Goal reached in background but celebration expired → transition to dismissed
        if state.phase == .goalReached && state.isCelebrationExpired(now: date) {
            state.transition(to: .dismissed, now: date, calendar: calendar)
            DayGoalStatus.transitionTo(.dismissed, calendar: calendar)
            AppLog.info("Celebration expired (background detected) — transitioning to dismissed", category: .liveActivity)
            await endActivities(contentState: contentState, dismissalPolicy: .immediate)
            return
        }

        SyncLog.info("[Sync] LA update — currentMl=\(currentMl), goalMl=\(dailyGoalMl), activities=\(activities.count), goalReached=\(goalReached), phase=\(state.phase.rawValue), isDuplicate=\(isDuplicateState), dayChanged=\(dayChanged)")

        if activities.contains(where: { $0.attributes.dailyGoalMl != dailyGoalMl }) {
            SyncLog.info("[Sync] LA — goal mismatch detected, ending old activities")
            await endActivities(dismissalPolicy: .immediate)
            activities = Activity<GlassWaterLiveActivityAttributes>.activities
        }

        // ── No activities → start new one ─────────────────────────────
        if activities.isEmpty {
            guard allowStartWhenNeeded else {
                AppLog.info("Skipping start: allowStartWhenNeeded=false (background context)", category: .liveActivity)
                return
            }
            guard !goalReached else {
                AppLog.info("Skipping start: goal already reached", category: .liveActivity)
                return
            }
            do {
                let attributes = GlassWaterLiveActivityAttributes(dailyGoalMl: dailyGoalMl)
                let content = ActivityContent(state: contentState, staleDate: endOfDay(for: dayStart))
                _ = try Activity.request(attributes: attributes, content: content)
                state.transition(to: .inProgress, now: date, calendar: calendar)
                AppLog.info("Live Activity started: \(currentMl)ml / \(dailyGoalMl)ml", category: .liveActivity)
                #if !DEBUG
                Crashlytics.crashlytics().setCustomValue("active", forKey: "live_activity_state")
                #endif
                analytics?.logEvent(AnalyticsEvents.liveActivityStarted, parameters: [
                    AnalyticsParams.progressPercent: dailyGoalMl > 0 ? Int(Double(currentMl) / Double(dailyGoalMl) * 100) : 0
                ])
            } catch {
                AppLog.error("Failed to start Live Activity: \(error.localizedDescription)", category: .liveActivity)
                #if !DEBUG
                Crashlytics.crashlytics().setCustomValue("start_failed", forKey: "live_activity_state")
                Crashlytics.crashlytics().record(error: error)
                #endif
                return
            }
            return
        }

        // ── Goal reached → celebration → auto-dismiss ────────────────
        if goalReached {
            let dismissAt: Date
            if state.phase != .goalReached {
                dismissAt = date.addingTimeInterval(goalReachedDismissalInterval)
                state.transition(to: .goalReached, now: date, calendar: calendar, celebrationDismissAt: dismissAt)
                AppLog.info("Goal reached! Ending LA with auto-dismiss at \(dismissAt.formatted(date: .omitted, time: .standard)) (\(AppConstants.liveActivityGoalReachedDismissMinutes) min)", category: .liveActivity)
                analytics?.logEvent(AnalyticsEvents.liveActivityEnded, parameters: [
                    AnalyticsParams.reason: "goal_reached"
                ])
            } else {
                dismissAt = state.celebrationDismissAt ?? date.addingTimeInterval(goalReachedDismissalInterval)
            }
            lastContentState = contentState
            // end(.after(dismissAt)) guarantees the system removes the LA after 2 min,
            // even if the app stays in background. The DI disappears immediately but
            // the Lock Screen shows the celebration until dismissAt.
            let content = ActivityContent(state: contentState, staleDate: nil)
            for activity in activities {
                await activity.end(content, dismissalPolicy: .after(dismissAt))
            }
            return
        }

        // ── Goal un-reached → back to inProgress ─────────────────────
        if state.phase == .goalReached {
            lastContentState = nil
            AppLog.info("Goal un-reached (was \(state.phase.rawValue)) — force-updating Live Activity to normal state", category: .liveActivity)
            state.transition(to: .inProgress, now: date, calendar: calendar)
            let content = ActivityContent(state: contentState, staleDate: endOfDay(for: dayStart))
            for activity in activities {
                await activity.update(content)
            }
            return
        }

        // ── Update inProgress state if phase not yet set ──────────────
        if state.phase == .idle || state.phase == .newDay {
            AppLog.info("[LA State] Transition → inProgress (was \(state.phase.rawValue))", category: .liveActivity)
            state.transition(to: .inProgress, now: date, calendar: calendar)
        }

        // ── Skip duplicate ────────────────────────────────────────────
        if isDuplicateState {
            return
        }
        lastContentState = contentState

        let content = ActivityContent(state: contentState, staleDate: endOfDay(for: dayStart))
        AppLog.info("Updating \(activities.count) Live Activity(ies): \(currentMl)ml / \(dailyGoalMl)ml", category: .liveActivity)
        for activity in activities {
            await activity.update(content)
        }
    }

    func end() async {
        let finalState = lastContentState
        lastContentState = nil
        #if !DEBUG
        Crashlytics.crashlytics().setCustomValue("ended", forKey: "live_activity_state")
        #endif
        await endActivities(
            contentState: finalState ?? .init(
                progress: 0,
                currentMl: 0,
                remainingMl: 0,
                goalReached: false,
                lastIntakeMl: nil,
                lastIntakeDate: nil,
                isSensitive: false,
                customAmountMl: AppConstants.defaultCustomAmountMl
            ),
            dismissalPolicy: .immediate
        )
    }

    private func endOfDay(for dayStart: Date) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: dayStart)
    }

    private var goalReachedDismissalInterval: TimeInterval {
        TimeInterval(AppConstants.liveActivityGoalReachedDismissMinutes * 60)
    }

    private func endActivities(
        contentState: GlassWaterLiveActivityAttributes.ContentState? = nil,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        let state = contentState ?? lastContentState ?? .init(
            progress: 0, currentMl: 0, remainingMl: 0, goalReached: false,
            lastIntakeMl: nil, lastIntakeDate: nil, isSensitive: false,
            customAmountMl: AppConstants.defaultCustomAmountMl
        )
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<GlassWaterLiveActivityAttributes>.activities
            where activity.activityState != .ended && activity.activityState != .dismissed {
            await activity.end(content, dismissalPolicy: dismissalPolicy)
        }
    }
}
