//
//  GoalReachedSequencer.swift
//  GlassWater
//
//  Stateless coordinator for the daily goal → celebration → duck award lifecycle.
//  ALL decisions read from DayGoalStatus (persisted AppGroup JSON).
//  NO in-memory flags — survives process kill, background, cold launch identically.
//

import Foundation
import Observation

@MainActor
@Observable
final class GoalReachedSequencer {
    nonisolated deinit {
        celebrationTask?.cancel()
        duckRevealTask?.cancel()
    }

    // MARK: - Observable State (UI-only, consumed by HomeView)

    /// Drives the celebration ring animation (5s).
    private(set) var justReachedGoal: Bool = false
    /// Drives the DuckRewardOverlay visibility.
    private(set) var showDuckReward: Bool = false
    /// First-time duck discovery animation.
    private(set) var isFirstDuckReward: Bool = false
    /// Duck image for the reward overlay.
    private(set) var rewardDuckImageName: String = "duck_glass"
    /// Duck name for the reward overlay.
    private(set) var rewardDuckName: String = ""
    /// Duck count to render in the water (suppressed during pending reveal).
    private(set) var visibleDuckCount: Int = 0

    /// True while duck reveal is pending (between award and overlay show).
    var duckRewardPending: Bool {
        DayGoalStatus.currentStatus(calendar: calendar) == .duckAwarded && !showDuckReward
    }

    // MARK: - Dependencies

    @ObservationIgnored private let settingsStore: any SettingsStore
    @ObservationIgnored private let sounds: any SoundServicing
    @ObservationIgnored private let crashReporter: any CrashReporting
    @ObservationIgnored private let analytics: any AnalyticsTracking
    @ObservationIgnored private let calendar: Calendar

    // MARK: - Tasks

    @ObservationIgnored private var celebrationTask: Task<Void, Never>?
    @ObservationIgnored private var duckRevealTask: Task<Void, Never>?

    // MARK: - Init

    init(
        settingsStore: any SettingsStore,
        sounds: any SoundServicing,
        crashReporter: any CrashReporting,
        analytics: any AnalyticsTracking,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.settingsStore = settingsStore
        self.sounds = sounds
        self.crashReporter = crashReporter
        self.analytics = analytics
        self.calendar = calendar
    }

    // MARK: - Public API

    /// Sets the initial duck count from settings on load.
    func setInitialDuckCount(_ count: Int) {
        visibleDuckCount = count
        AppLog.info("[Sequencer] setInitialDuckCount=\(count)", category: .lifecycle)
    }

    /// Called when goal is reached (in-app or external). Reads DayGoalStatus to decide next step.
    /// This is the SINGLE entry point for all goal-reached scenarios.
    func goalReached(settings: UserSettings, swimmingDuckEnabled: Bool) {
        let status = DayGoalStatus.currentStatus(calendar: calendar)

        switch status {
        case .idle:
            // Step 1: Mark goal reached
            DayGoalStatus.transitionTo(.goalReached, calendar: calendar)
            // Step 2: Start celebration
            DayGoalStatus.transitionTo(.celebrating, calendar: calendar)
            startCelebrationAnimation()
            // Step 3: Award duck
            awardDuck(settings: settings, swimmingDuckEnabled: swimmingDuckEnabled)

        case .goalReached:
            // Intent wrote goalReached but app wasn't open → celebrate now
            DayGoalStatus.transitionTo(.celebrating, calendar: calendar)
            startCelebrationAnimation()
            awardDuck(settings: settings, swimmingDuckEnabled: swimmingDuckEnabled)

        case .celebrating:
            // Only resume if duckRevealTask is nil (process was killed during celebration).
            // If the task is still alive, let it finish naturally — don't restart.
            guard duckRevealTask == nil else {
                AppLog.info("[Sequencer] goalReached — .celebrating, duckRevealTask alive, skipping", category: .userAction)
                break
            }
            startCelebrationAnimation()
            awardDuck(settings: settings, swimmingDuckEnabled: swimmingDuckEnabled)

        case .duckAwarded:
            // Duck was awarded but overlay may not have been shown (app killed mid-reveal).
            if !showDuckReward {
                resumeDuckReveal(settings: settings)
            }

        case .completed, .dismissed:
            // Flow done for today — nothing to do
            AppLog.info("[Sequencer] goalReached SKIPPED — status=\(status)", category: .userAction)
        }
    }

    /// Awards ducks for missed days (cold launch detected goal-reached days with no duck).
    func awardMissedDucks(
        settings: UserSettings,
        swimmingDuckEnabled: Bool,
        missedDays: [Date],
        todayGoalReached: Bool
    ) {
        guard !missedDays.isEmpty else { return }

        let isFirstDiscovery = !settings.hasDiscoveredDucks && settings.duckCount == 0 && !swimmingDuckEnabled
        if isFirstDiscovery {
            settings.swimmingDuckEnabled = true
            settings.hasDiscoveredDucks = true
        } else if !swimmingDuckEnabled {
            return
        }

        let missedCount = missedDays.count
        guard let latestDay = missedDays.max() else { return }

        AppLog.info("[Sequencer] Awarding \(missedCount) missed duck(s) — isFirstDiscovery=\(isFirstDiscovery)", category: .sync)
        let previousLastAwardedDay = settings.lastDuckAwardedDay
        let previousCount = settings.duckCount
        settings.duckCount += missedCount
        settings.lastDuckAwardedDay = calendar.startOfDay(for: latestDay)

        do {
            try settingsStore.save()
        } catch {
            settings.duckCount = previousCount
            settings.lastDuckAwardedDay = previousLastAwardedDay
            if isFirstDiscovery {
                settings.swimmingDuckEnabled = false
                settings.hasDiscoveredDucks = false
            }
            AppLog.error("[Sequencer] Missed ducks save FAILED — reverted duckCount to \(previousCount)", category: .error)
            crashReporter.record(error: error)
            return
        }

        let newDuckCount = settings.duckCount
        analytics.logEvent(AnalyticsEvents.duckAwarded, parameters: [
            AnalyticsParams.duckCount: newDuckCount
        ])
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)

        // Deferred reveal: wait for load animations → celebrate (if needed) → show duck
        isFirstDuckReward = isFirstDiscovery
        prepareRewardData(settings: settings, duckCount: newDuckCount)

        duckRevealTask?.cancel()
        duckRevealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled, let self else { return }

            // Trigger celebration if today's goal is reached and not yet celebrating
            if todayGoalReached {
                let currentStatus = DayGoalStatus.currentStatus(calendar: self.calendar)
                if currentStatus < .celebrating {
                    DayGoalStatus.transitionTo(.goalReached, calendar: self.calendar)
                    DayGoalStatus.transitionTo(.celebrating, calendar: self.calendar)
                    self.startCelebrationAnimation()
                }
            }

            try? await Task.sleep(for: .seconds(AppConstants.duckRewardDelaySeconds))
            guard !Task.isCancelled else { return }

            self.visibleDuckCount = newDuckCount
            DayGoalStatus.transitionTo(.duckAwarded, duckCount: newDuckCount, calendar: self.calendar)
            self.showDuckReward = true
            self.sounds.play(.quack)
            AppLog.info("[Sequencer] phase → duckRevealed — visibleDuckCount=\(newDuckCount)", category: .sync)
        }
    }

    /// Called when goal is un-reached (user deleted an entry).
    func goalUnreached(settings: UserSettings) {
        let status = DayGoalStatus.currentStatus(calendar: calendar)
        AppLog.info("[Sequencer] goalUnreached — status=\(status), duckCount=\(settings.duckCount)", category: .userAction)

        // If status is already idle, nothing to unreach — skip entirely.
        // This prevents revoking ducks granted by Settings toggle (not goal-based).
        guard status > .idle else { return }

        // Cancel all pending animations
        cancelAllTasks()
        justReachedGoal = false
        showDuckReward = false
        isFirstDuckReward = false

        // Reset DayGoalStatus to idle
        DayGoalStatus.resetToIdle(calendar: calendar)

        // Do NOT transition LiveActivityState here — let the broadcast →
        // LiveActivityService.update() handle it. The service has a special
        // "goal un-reached" branch that clears lastContentState and forces
        // a visual update. If we transition here first, the service misses
        // the goalReached→inProgress change and may skip the update (isDuplicate).

        // Revoke duck if it was awarded today
        guard let lastAwarded = settings.lastDuckAwardedDay,
              calendar.isDate(lastAwarded, inSameDayAs: .now),
              settings.duckCount > 0 else {
            return
        }

        AppLog.info("[Sequencer] Revoking duck — duckCount \(settings.duckCount) → \(settings.duckCount - 1)", category: .userAction)
        settings.duckCount -= 1
        settings.lastDuckAwardedDay = nil

        do {
            try settingsStore.save()
        } catch {
            settings.duckCount += 1
            settings.lastDuckAwardedDay = lastAwarded
            AppLog.error("[Sequencer] Duck revoke save FAILED", category: .error)
            crashReporter.record(error: error)
            return
        }

        visibleDuckCount = settings.duckCount
        AppLog.info("[Sequencer] Duck revoked — visibleDuckCount=\(visibleDuckCount)", category: .userAction)

        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        analytics.logEvent(AnalyticsEvents.duckRevoked, parameters: [
            AnalyticsParams.duckCount: settings.duckCount
        ])
    }

    /// Grants the first duck when user enables ducks in Settings (duckCount was 0).
    func grantFirstDuck(settings: UserSettings) {
        guard settings.duckCount == 0 else { return }
        AppLog.info("[Sequencer] Granting first duck from Settings toggle", category: .userAction)

        settings.duckCount = 1
        // Do NOT set lastDuckAwardedDay — this duck is a Settings bonus,
        // not a goal-reached award. goalUnreached checks lastDuckAwardedDay
        // to decide if a duck should be revoked.
        settings.hasDiscoveredDucks = true

        do {
            try settingsStore.save()
        } catch {
            settings.duckCount = 0
            settings.hasDiscoveredDucks = false
            crashReporter.record(error: error)
            return
        }

        isFirstDuckReward = true
        prepareRewardData(settings: settings, duckCount: 1)

        analytics.logEvent(AnalyticsEvents.duckAwarded, parameters: [
            AnalyticsParams.duckCount: 1
        ])
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)

        // Show reward overlay immediately (no celebration delay — user just toggled)
        showDuckReward = true
        sounds.play(.quack)
    }

    /// Dismisses the duck reward overlay. The new duck appears in water NOW (on dismiss).
    /// Returns true if review should be requested.
    func dismissDuckReward() -> Bool {
        duckRevealTask?.cancel()
        duckRevealTask = nil
        showDuckReward = false
        isFirstDuckReward = false
        // NOW the duck appears in water — after overlay is dismissed
        if let stored = DayGoalStatus.loadToday(calendar: calendar),
           let awardedCount = stored.duckCountAtAward {
            visibleDuckCount = awardedCount
            AppLog.info("[Sequencer] Duck appeared in water — visibleDuckCount=\(awardedCount)", category: .userAction)
        }
        rewardDuckImageName = "duck_glass"
        rewardDuckName = ""
        DayGoalStatus.transitionTo(.completed, calendar: calendar)
        AppLog.info("[Sequencer] dismissDuckReward → completed", category: .userAction)
        return true
    }

    // MARK: - Private

    private func startCelebrationAnimation() {
        celebrationTask?.cancel()
        justReachedGoal = true
        AppLog.info("[Sequencer] Celebration started (5s timer)", category: .userAction)
        celebrationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.justReachedGoal = false
        }
    }

    private func awardDuck(settings: UserSettings, swimmingDuckEnabled: Bool) {
        // Already awarded today
        if let lastAwarded = settings.lastDuckAwardedDay,
           calendar.isDate(lastAwarded, inSameDayAs: .now) {
            AppLog.info("[Sequencer] Duck already awarded today — skipping", category: .userAction)
            // Transition DayGoalStatus but do NOT set visibleDuckCount —
            // let the duckRevealTask handle it (deferred reveal after celebration)
            DayGoalStatus.transitionTo(.duckAwarded, duckCount: settings.duckCount, calendar: calendar)
            return
        }

        let isFirstDiscovery = !settings.hasDiscoveredDucks && settings.duckCount == 0 && !swimmingDuckEnabled
        AppLog.info("[Sequencer] Awarding duck — isFirst=\(isFirstDiscovery), count=\(settings.duckCount), enabled=\(swimmingDuckEnabled)", category: .userAction)

        if isFirstDiscovery {
            settings.swimmingDuckEnabled = true
            settings.hasDiscoveredDucks = true
        }

        // Always award the duck in SwiftData (even if ducks disabled).
        // When user enables ducks later, accumulated ducks appear.
        let previousLastAwardedDay = settings.lastDuckAwardedDay
        let previousCount = settings.duckCount
        settings.duckCount += 1
        settings.lastDuckAwardedDay = calendar.startOfDay(for: .now)

        do {
            try settingsStore.save()
        } catch {
            settings.duckCount = previousCount
            settings.lastDuckAwardedDay = previousLastAwardedDay
            if isFirstDiscovery {
                settings.swimmingDuckEnabled = false
                settings.hasDiscoveredDucks = false
            }
            AppLog.error("[Sequencer] Duck award save FAILED", category: .error)
            crashReporter.record(error: error)
            return
        }

        let newDuckCount = settings.duckCount

        analytics.logEvent(AnalyticsEvents.duckAwarded, parameters: [
            AnalyticsParams.duckCount: newDuckCount
        ])
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)

        // If ducks are disabled (and not first discovery), save silently — no overlay, no sound
        guard swimmingDuckEnabled || isFirstDiscovery else {
            AppLog.info("[Sequencer] Duck awarded silently (ducks disabled) — count=\(newDuckCount)", category: .userAction)
            DayGoalStatus.transitionTo(.duckAwarded, duckCount: newDuckCount, calendar: calendar)
            DayGoalStatus.transitionTo(.completed, calendar: calendar)
            return
        }

        isFirstDuckReward = isFirstDiscovery
        prepareRewardData(settings: settings, duckCount: newDuckCount)

        // Deferred reveal — wait for celebration animation (5s) to finish,
        // then show reward overlay. The duck appears in water on dismiss (not before).
        duckRevealTask?.cancel()
        duckRevealTask = Task { @MainActor [weak self] in
            // Wait for celebration ring animation to finish (5s) + buffer
            try? await Task.sleep(for: .seconds(5.5))
            guard !Task.isCancelled, let self else { return }
            DayGoalStatus.transitionTo(.duckAwarded, duckCount: newDuckCount, calendar: self.calendar)
            self.showDuckReward = true
            self.sounds.play(.quack)
            AppLog.info("[Sequencer] Reward overlay shown — duck will appear in water on dismiss", category: .userAction)
        }
    }

    private func resumeDuckReveal(settings: UserSettings) {
        guard let stored = DayGoalStatus.loadToday(calendar: calendar),
              let awardedCount = stored.duckCountAtAward else { return }
        // Don't set visibleDuckCount here — duck appears in water on dismiss
        prepareRewardData(settings: settings, duckCount: awardedCount)
        showDuckReward = true
        sounds.play(.quack)
        AppLog.info("[Sequencer] Resumed duck reveal — visibleDuckCount=\(awardedCount)", category: .lifecycle)
    }

    private func prepareRewardData(settings: UserSettings, duckCount: Int) {
        let configIndex = (duckCount - 1) % SwimmingDuckOverlay.configurations.count
        rewardDuckImageName = SwimmingDuckOverlay.configurations[configIndex].imageName
        rewardDuckName = duckName(forSettings: settings, count: duckCount)
    }

    private func duckName(forSettings settings: UserSettings, count: Int) -> String {
        guard count > 0 else { return "Milo" }
        let index = (count - 1) % SwimmingDuckOverlay.configurations.count
        if let custom = settings.duckNicknames[count] { return custom }
        return NSLocalizedString("duck_name_\(index + 1)", comment: "")
    }

    private func cancelAllTasks() {
        celebrationTask?.cancel()
        celebrationTask = nil
        duckRevealTask?.cancel()
        duckRevealTask = nil
    }

    // MARK: - Debug

    #if DEBUG
    func debugReset() {
        cancelAllTasks()
        justReachedGoal = false
        showDuckReward = false
        isFirstDuckReward = false
        visibleDuckCount = 0
        DayGoalStatus.resetToIdle(calendar: calendar)
    }

    func debugTriggerDuckReward(asFirstTime: Bool, settings: UserSettings) {
        if asFirstTime {
            isFirstDuckReward = true
            rewardDuckImageName = "duck_glass"
            rewardDuckName = duckName(forSettings: settings, count: 1)
        } else {
            isFirstDuckReward = false
            let count = max(1, visibleDuckCount)
            let configIndex = (count - 1) % SwimmingDuckOverlay.configurations.count
            rewardDuckImageName = SwimmingDuckOverlay.configurations[configIndex].imageName
            rewardDuckName = duckName(forSettings: settings, count: count)
        }
        showDuckReward = true
        sounds.play(.quack)
    }
    #endif
}
