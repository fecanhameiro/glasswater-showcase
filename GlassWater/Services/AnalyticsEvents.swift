//
//  AnalyticsEvents.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 08/02/26.
//

import Foundation

// MARK: - Event Names

enum AnalyticsEvents {
    // Core
    static let waterAdded = "water_added"
    static let waterDeleted = "water_deleted"
    static let waterEdited = "water_edited"
    static let waterUndone = "water_undone"

    // Milestones
    static let dailyGoalReached = "daily_goal_reached"
    static let streakMilestone = "streak_milestone"

    // Onboarding
    static let onboardingStep = "onboarding_step"
    static let onboardingCompleted = "onboarding_completed"

    // Settings
    static let settingChanged = "setting_changed"
    static let goalChanged = "goal_changed"
    static let permissionResult = "permission_result"

    // Engagement
    static let customAmountSelected = "custom_amount_selected"
    static let historyDayViewed = "history_day_viewed"

    // Session
    static let appOpen = "app_open"

    // Notifications
    static let notificationTapped = "notification_tapped"
    static let notificationSnooze = "notification_snooze"

    // Activation
    static let firstWaterAdded = "first_water_added"

    // Duck Reward
    static let duckAwarded = "duck_awarded"
    static let duckRevoked = "duck_revoked"

    // Live Activity
    static let liveActivityStarted = "live_activity_started"
    static let liveActivityEnded = "live_activity_ended"
    static let liveActivityUpdateFailed = "live_activity_update_failed"
}

// MARK: - Parameter Keys

enum AnalyticsParams {
    static let amountMl = "amount_ml"
    static let source = "source"
    static let timeOfDay = "time_of_day"
    static let goalMl = "goal_ml"
    static let entriesCount = "entries_count"
    static let streakDays = "streak_days"
    static let step = "step"
    static let stepName = "step_name"
    static let setting = "setting"
    static let enabled = "enabled"
    static let permission = "permission"
    static let result = "result"
    static let oldValue = "old_value"
    static let newValue = "new_value"
    static let isCustom = "is_custom"
    static let daysAgo = "days_ago"
    static let widgetFamily = "widget_family"
    static let actionType = "action_type"
    static let reason = "reason"
    static let progressPercent = "progress_percent"
    static let retryCount = "retry_count"
    static let duckCount = "duck_count"
}

// MARK: - User Property Keys

enum AnalyticsUserProps {
    static let dailyGoalMl = "daily_goal_ml"
    static let notificationsEnabled = "notifications_enabled"
    static let healthConnected = "health_connected"
    static let liveActivitiesEnabled = "live_activities_enabled"
    static let hapticsEnabled = "haptics_enabled"
    static let usesWidget = "uses_widget"
    static let usesWatch = "uses_watch"
    static let usesLiveActivity = "uses_live_activity"
    static let usesSiri = "uses_siri"
    static let currentStreak = "current_streak"
    static let smartNotificationsEnabled = "smart_notif_enabled"
    static let onboardingCompleted = "onboarding_completed"
    static let duckCount = "duck_count"
}

// MARK: - Helpers

enum AnalyticsTimeOfDay {
    static func current(calendar: Calendar = .autoupdatingCurrent) -> String {
        let hour = calendar.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "morning"
        case 12..<18: return "afternoon"
        default: return "evening"
        }
    }
}
