//
//  AppConstants.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.glasswater.app"
    static let sharedStoreName = "GlassWater"
    static let widgetKind = "GlassWaterWidget"
    static let backgroundRefreshTaskIdentifier = "com.glasswater.app.refresh"
    static let backgroundMidnightRefreshTaskIdentifier = "com.glasswater.app.midnight"
    static let appGroupDailyGoalKey = "glasswater.dailyGoalMl"
    static let appGroupCustomAmountKey = "glasswater.customAmountMl"
    static let appGroupHydrationSnapshotKey = "glasswater.hydrationSnapshot"
    static let appGroupHapticsEnabledKey = "glasswater.hapticsEnabled"
    static let defaultDailyGoalMl = 2500
    static let minDailyGoalMl = 1000
    static let maxDailyGoalMl = 5000
    static let dailyGoalStepMl = 250
    static let quickAddPercents = [10, 15, 25]
    static let quickAddStepMl = 50
    static let quickAddMinMl = 100
    static let quickAddMaxMl = 1000
    static let customAmountMinMl = 50
    static let customAmountMaxMl = 1500
    static let customAmountStepMl = 50
    static let defaultCustomAmountMl = 250
    static let defaultReminderStartMinutes = 9 * 60
    static let defaultReminderEndMinutes = 21 * 60
    static let defaultReminderIntervalMinutes = 120
    static let liveActivityGoalReachedDismissMinutes = 2
    static let appGroupVolumeUnitKey = "glasswater.volumeUnit"
    static let appGroupOnboardingCompletedKey = "glasswater.onboardingCompleted"

    // MARK: - App Store

    static let appStoreId = "6757977655"

    // MARK: - Duck Reward

    static let maxVisibleDucks = 5
    static let duckRewardDelaySeconds: Double = 2.0
    static let duckRewardDismissSeconds: Double = 4.5
    static let duckRewardFirstDismissSeconds: Double = 5.5

    // MARK: - Notification Tuning

    /// Cooldown after a drink before sending the next reminder (seconds)
    static let notificationPostDrinkCooldownSeconds: TimeInterval = 60.0 * 30.0
    /// Progress threshold above which reminders are suppressed (0-1)
    static let notificationNearGoalThreshold: Double = 0.98
    /// Minimum interval for intelligent cooldown suppression (seconds)
    static let notificationIntelligentCooldownSeconds: TimeInterval = 60.0 * 15.0
    /// How far ahead of expected progress the user must be to suppress a reminder (0-1)
    static let notificationProgressAheadMargin: Double = 0.15
    /// How far behind expected progress to trigger a catch-up reminder (0-1)
    static let notificationCatchUpBehindMargin: Double = 0.20
    /// Maximum number of reminder slots scheduled per cycle
    static let notificationMaxReminderSlots = 60
}
