//
//  UserSettings.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import SwiftData

@Model
final class UserSettings {
    var id: UUID = UUID()
    var dailyGoalMl: Int = AppConstants.defaultDailyGoalMl
    var notificationsEnabled: Bool = false
    var intelligentNotificationsEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var liveActivitiesEnabled: Bool = true
    var liveActivitySensitiveModeEnabled: Bool = false
    var reminderStartMinutes: Int = AppConstants.defaultReminderStartMinutes
    var reminderEndMinutes: Int = AppConstants.defaultReminderEndMinutes
    var reminderIntervalMinutes: Int = AppConstants.defaultReminderIntervalMinutes
    var hasCompletedOnboarding: Bool = false
    var streakCount: Int = 0
    var lastCompletedDay: Date?
    var lastCustomAmountMl: Int?
    var preferredVolumeUnit: String = "auto"
    var swimmingDuckEnabled: Bool = false
    var duckCount: Int = 0
    var lastDuckAwardedDay: Date?
    var completedDaysJSON: String = "[]"
    var duckNicknamesJSON: String = "{}"
    var hasTipped: Bool = false
    /// Persisted flag: true once the user has earned their first duck.
    /// Prevents re-triggering first-discovery animation after revoke (duckCount 1→0).
    var hasDiscoveredDucks: Bool = false
    var createdAt: Date = Date.now

    init(
        dailyGoalMl: Int = AppConstants.defaultDailyGoalMl,
        notificationsEnabled: Bool = false,
        intelligentNotificationsEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        liveActivitiesEnabled: Bool = true,
        liveActivitySensitiveModeEnabled: Bool = false,
        reminderStartMinutes: Int = AppConstants.defaultReminderStartMinutes,
        reminderEndMinutes: Int = AppConstants.defaultReminderEndMinutes,
        reminderIntervalMinutes: Int = AppConstants.defaultReminderIntervalMinutes,
        hasCompletedOnboarding: Bool = false,
        streakCount: Int = 0,
        lastCompletedDay: Date? = nil,
        lastCustomAmountMl: Int? = nil,
        preferredVolumeUnit: String = "auto",
        swimmingDuckEnabled: Bool = false,
        duckCount: Int = 0,
        lastDuckAwardedDay: Date? = nil,
        completedDaysJSON: String = "[]",
        duckNicknamesJSON: String = "{}",
        hasTipped: Bool = false,
        hasDiscoveredDucks: Bool = false,
        createdAt: Date = Date.now
    ) {
        self.dailyGoalMl = dailyGoalMl
        self.notificationsEnabled = notificationsEnabled
        self.intelligentNotificationsEnabled = intelligentNotificationsEnabled
        self.hapticsEnabled = hapticsEnabled
        self.liveActivitiesEnabled = liveActivitiesEnabled
        self.liveActivitySensitiveModeEnabled = liveActivitySensitiveModeEnabled
        self.reminderStartMinutes = reminderStartMinutes
        self.reminderEndMinutes = reminderEndMinutes
        self.reminderIntervalMinutes = reminderIntervalMinutes
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.streakCount = streakCount
        self.lastCompletedDay = lastCompletedDay
        self.lastCustomAmountMl = lastCustomAmountMl
        self.preferredVolumeUnit = preferredVolumeUnit
        self.swimmingDuckEnabled = swimmingDuckEnabled
        self.duckCount = duckCount
        self.lastDuckAwardedDay = lastDuckAwardedDay
        self.completedDaysJSON = completedDaysJSON
        self.duckNicknamesJSON = duckNicknamesJSON
        self.hasTipped = hasTipped
        self.hasDiscoveredDucks = hasDiscoveredDucks
        self.createdAt = createdAt
    }
}

// MARK: - Completed Days (Streak Audit Trail)

extension UserSettings {
    /// Recent days where the daily goal was met (last 30 days max).
    /// Used for robust streak calculation and audit trail.
    var completedDays: [Date] {
        get {
            guard let data = completedDaysJSON.data(using: .utf8),
                  let timestamps = try? JSONDecoder().decode([TimeInterval].self, from: data)
            else { return [] }
            return timestamps.map { Date(timeIntervalSince1970: $0) }
        }
        set {
            // Keep only last 30 days, sorted descending
            let calendar = Calendar.autoupdatingCurrent
            let cutoff = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
            let filtered = newValue
                .filter { $0 >= cutoff }
                .sorted(by: >)
            let timestamps = filtered.map(\.timeIntervalSince1970)
            if let data = try? JSONEncoder().encode(timestamps) {
                completedDaysJSON = String(data: data, encoding: .utf8) ?? "[]"
            }
        }
    }

    /// Adds today to completedDays if not already present.
    func markDayCompleted(_ day: Date, calendar: Calendar = .autoupdatingCurrent) {
        let dayStart = calendar.startOfDay(for: day)
        var days = completedDays
        if !days.contains(where: { calendar.isDate($0, inSameDayAs: dayStart) }) {
            days.append(dayStart)
            completedDays = days
        }
    }

    /// Removes today from completedDays.
    func unmarkDayCompleted(_ day: Date, calendar: Calendar = .autoupdatingCurrent) {
        var days = completedDays
        days.removeAll { calendar.isDate($0, inSameDayAs: day) }
        completedDays = days
    }

    /// Calculates streak from completedDays array (consecutive days ending today or yesterday).
    func calculateStreak(calendar: Calendar = .autoupdatingCurrent) -> Int {
        let today = calendar.startOfDay(for: .now)
        let allDays = completedDays
            .map { calendar.startOfDay(for: $0) }
            .sorted(by: >)
        // Deduplicate (same calendar day)
        var seen = Set<Date>()
        let sorted = allDays.filter { seen.insert($0).inserted }

        guard let first = sorted.first else { return 0 }

        // Streak must start from today or yesterday
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        guard calendar.isDate(first, inSameDayAs: today) || calendar.isDate(first, inSameDayAs: yesterday) else {
            return 0
        }

        var streak = 1
        var expectedDay = calendar.date(byAdding: .day, value: -1, to: first)!
        for day in sorted.dropFirst() {
            if calendar.isDate(day, inSameDayAs: expectedDay) {
                streak += 1
                expectedDay = calendar.date(byAdding: .day, value: -1, to: expectedDay)!
            } else if day < expectedDay {
                break // gap found
            }
            // Skip duplicate days
        }
        return streak
    }
}

// MARK: - Duck Nicknames

extension UserSettings {
    var duckNicknames: [Int: String] {
        get {
            guard let data = duckNicknamesJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return dict.reduce(into: [:]) { result, pair in
                if let key = Int(pair.key) { result[key] = pair.value }
            }
        }
        set {
            let stringDict = newValue.reduce(into: [String: String]()) { $0["\($1.key)"] = $1.value }
            if let data = try? JSONEncoder().encode(stringDict) {
                duckNicknamesJSON = String(data: data, encoding: .utf8) ?? "{}"
            }
        }
    }
}
