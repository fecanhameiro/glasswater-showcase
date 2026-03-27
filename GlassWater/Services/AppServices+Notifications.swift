//
//  AppServices+Notifications.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

@MainActor
extension AppServices {
    func refreshNotifications(date: Date = .now, applySmartRules: Bool = false) async {
        do {
            let settings = try settingsStore.loadOrCreate()
            let total = try waterStore.total(for: date)
            let lastEntryDate = try waterStore.latestTodayEntry(for: date)?.date
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
                date: date
            )
            if applySmartRules, settings.intelligentNotificationsEnabled {
                await notificationService.applyIntelligentRules(
                    isEnabled: settings.notificationsEnabled,
                    currentTotalMl: total,
                    dailyGoalMl: settings.dailyGoalMl,
                    reminderStartMinutes: settings.reminderStartMinutes,
                    reminderEndMinutes: settings.reminderEndMinutes,
                    lastEntryDate: lastEntryDate,
                    date: date
                )
            }
        } catch {
            crashReporter.record(error: error)
        }
    }
}
