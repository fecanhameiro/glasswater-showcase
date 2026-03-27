//
//  SwiftDataSettingsStore.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import SwiftData

@MainActor
final class SwiftDataSettingsStore: SettingsStore {
    private let modelContext: ModelContext
    private var cachedSettings: UserSettings?
    private let appGroupDefaults: UserDefaults?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.appGroupDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    }

    func loadOrCreate() throws -> UserSettings {
        if let cachedSettings {
            return cachedSettings
        }

        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = try modelContext.fetch(descriptor).first {
            validateAndClampSettings(existing)
            cachedSettings = existing
            syncAppGroupDefaults(with: existing)
            return existing
        }

        let settings = UserSettings()
        modelContext.insert(settings)
        try modelContext.save()
        cachedSettings = settings
        syncAppGroupDefaults(with: settings)
        return settings
    }

    func save() throws {
        if let settings = cachedSettings {
            validateAndClampSettings(settings)
        }
        try modelContext.save()
        // Post-save cache refresh is best-effort — the save above succeeded,
        // so don't throw here (callers would incorrectly revert in-memory changes).
        do {
            if let settings = try cachedSettings ?? modelContext.fetch(FetchDescriptor<UserSettings>()).first {
                cachedSettings = settings
                syncAppGroupDefaults(with: settings)
            }
        } catch {
            AppLog.error("Failed to re-fetch settings after save: \(error.localizedDescription)", category: .persistence)
        }
    }

    private func validateAndClampSettings(_ settings: UserSettings) {
        // Clamp daily goal to valid range
        settings.dailyGoalMl = max(
            AppConstants.minDailyGoalMl,
            min(settings.dailyGoalMl, AppConstants.maxDailyGoalMl)
        )

        // Clamp reminder times to valid 24h range (0-1439 minutes)
        settings.reminderStartMinutes = max(0, min(settings.reminderStartMinutes, 24 * 60 - 1))
        settings.reminderEndMinutes = max(0, min(settings.reminderEndMinutes, 24 * 60 - 1))

        // Clamp reminder interval (minimum 60 minutes, maximum 240 minutes)
        settings.reminderIntervalMinutes = max(60, min(settings.reminderIntervalMinutes, 240))

        // Clamp custom amount if present
        if let customAmount = settings.lastCustomAmountMl {
            settings.lastCustomAmountMl = max(
                AppConstants.customAmountMinMl,
                min(customAmount, AppConstants.customAmountMaxMl)
            )
        }

        // Ensure streak count is non-negative
        settings.streakCount = max(0, settings.streakCount)
    }

    func invalidateCache() {
        cachedSettings = nil
    }

    private func syncAppGroupDefaults(with settings: UserSettings) {
        guard let appGroupDefaults else { return }
        appGroupDefaults.set(settings.dailyGoalMl, forKey: AppConstants.appGroupDailyGoalKey)
        if let customAmount = settings.lastCustomAmountMl {
            appGroupDefaults.set(customAmount, forKey: AppConstants.appGroupCustomAmountKey)
        } else {
            appGroupDefaults.removeObject(forKey: AppConstants.appGroupCustomAmountKey)
        }
        appGroupDefaults.set(settings.preferredVolumeUnit, forKey: AppConstants.appGroupVolumeUnitKey)
        appGroupDefaults.set(settings.hapticsEnabled, forKey: AppConstants.appGroupHapticsEnabledKey)
    }
}
