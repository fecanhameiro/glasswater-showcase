//
//  SettingsViewModel.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import Observation
import SwiftUI


@MainActor
@Observable
final class SettingsViewModel {
    nonisolated deinit {}
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var settings: UserSettings?
    private let calendar: Calendar

    var dailyGoalMl: Int = AppConstants.defaultDailyGoalMl
    var notificationsEnabled: Bool = false
    var intelligentNotificationsEnabled: Bool = true
    var notificationsStatus: NotificationAccessStatus = .unknown
    var hapticsEnabled: Bool = true
    var liveActivitiesEnabled: Bool = true
    var liveActivitySensitiveModeEnabled: Bool = false
    var swimmingDuckEnabled: Bool = false
    var duckCount: Int = 0
    var reminderStartMinutes: Int = AppConstants.defaultReminderStartMinutes
    var reminderEndMinutes: Int = AppConstants.defaultReminderEndMinutes
    var reminderIntervalMinutes: Int = AppConstants.defaultReminderIntervalMinutes
    var healthStatus: HealthAccessStatus = .unknown
    var isRequestingHealthAccess: Bool = false
    var preferredVolumeUnit: VolumeUnit = .auto
    @ObservationIgnored private var previousGoalMl: Int = AppConstants.defaultDailyGoalMl

    init(services: AppServices, calendar: Calendar = .autoupdatingCurrent) {
        self.services = services
        self.calendar = calendar
        loadSettings()
    }

    func load() async {
        reloadDuckState()
        healthStatus = await services.healthService.authorizationStatus()
        notificationsStatus = await services.notificationService.authorizationStatus()
    }

    func persistChanges() {
        guard let settings else { return }
        if dailyGoalMl != previousGoalMl {
            services.analytics.logEvent(AnalyticsEvents.goalChanged, parameters: [
                AnalyticsParams.oldValue: previousGoalMl,
                AnalyticsParams.newValue: dailyGoalMl
            ])
            previousGoalMl = dailyGoalMl
        }
        settings.dailyGoalMl = dailyGoalMl
        settings.notificationsEnabled = notificationsEnabled
        settings.intelligentNotificationsEnabled = intelligentNotificationsEnabled
        settings.hapticsEnabled = hapticsEnabled
        settings.liveActivitiesEnabled = liveActivitiesEnabled
        settings.liveActivitySensitiveModeEnabled = liveActivitySensitiveModeEnabled
        settings.swimmingDuckEnabled = swimmingDuckEnabled
        settings.reminderStartMinutes = reminderStartMinutes
        settings.reminderEndMinutes = reminderEndMinutes
        settings.reminderIntervalMinutes = reminderIntervalMinutes
        settings.preferredVolumeUnit = preferredVolumeUnit.rawValue
        do {
            try services.settingsStore.save()
        } catch {
            services.crashReporter.record(error: error)
        }

        // Send updated settings to watch via WatchConnectivity
        services.phoneConnectivity?.sendSettings(
            goalMl: dailyGoalMl,
            customAmountMl: settings.lastCustomAmountMl ?? AppConstants.defaultCustomAmountMl
        )
    }

    func updateNotifications() async {
        services.analytics.logEvent(AnalyticsEvents.settingChanged, parameters: [
            AnalyticsParams.setting: "notifications",
            AnalyticsParams.enabled: notificationsEnabled
        ])
        if notificationsEnabled {
            let granted = await services.notificationService.requestAuthorization()
            if !granted {
                notificationsEnabled = false
            }
            services.analytics.logEvent(AnalyticsEvents.permissionResult, parameters: [
                AnalyticsParams.permission: "notifications",
                AnalyticsParams.result: granted ? "authorized" : "denied"
            ])
        }
        notificationsStatus = await services.notificationService.authorizationStatus()
        var total: Int = 0
        var lastEntryDate: Date?
        do {
            total = try services.waterStore.total(for: .now)
            lastEntryDate = try services.waterStore.latestEntryDate()
        } catch {
            services.crashReporter.record(error: error)
            lastEntryDate = nil
        }
        await services.notificationService.updateReminders(
            isEnabled: notificationsEnabled,
            currentTotalMl: total,
            dailyGoalMl: dailyGoalMl,
            customAmountMl: settings?.lastCustomAmountMl,
            reminderStartMinutes: reminderStartMinutes,
            reminderEndMinutes: reminderEndMinutes,
            reminderIntervalMinutes: reminderIntervalMinutes,
            lastEntryDate: lastEntryDate,
            streakCount: settings?.streakCount ?? 0,
            date: .now
        )
        persistChanges()
    }

    func updateLiveActivities() async {
        services.analytics.logEvent(AnalyticsEvents.settingChanged, parameters: [
            AnalyticsParams.setting: "live_activities",
            AnalyticsParams.enabled: liveActivitiesEnabled
        ])
        persistChanges()
        if liveActivitiesEnabled {
            await broadcastSnapshot(source: .app)
        } else {
            await services.liveActivity.end()
        }
    }

    func requestHealthAccess() async {
        guard !isRequestingHealthAccess else { return }
        isRequestingHealthAccess = true
        defer { isRequestingHealthAccess = false }
        do {
            healthStatus = try await services.healthService.requestAuthorization()
            services.analytics.logEvent(AnalyticsEvents.permissionResult, parameters: [
                AnalyticsParams.permission: "health",
                AnalyticsParams.result: healthStatus == .authorized ? "authorized" : "denied"
            ])
            if healthStatus == .authorized {
                await services.backfillPendingHealthEntries()
            }
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    var healthStatusKey: LocalizedStringKey {
        switch healthStatus {
        case .authorized:
            return "settings_health_status_connected"
        case .denied:
            return "settings_health_status_denied"
        case .notDetermined:
            return "settings_health_status_not_determined"
        case .unknown:
            return "settings_health_status_unknown"
        }
    }

    private func loadSettings() {
        do {
            let settings = try services.settingsStore.loadOrCreate()
            self.settings = settings
            dailyGoalMl = settings.dailyGoalMl
            previousGoalMl = settings.dailyGoalMl
            notificationsEnabled = settings.notificationsEnabled
            intelligentNotificationsEnabled = settings.intelligentNotificationsEnabled
            hapticsEnabled = settings.hapticsEnabled
            liveActivitiesEnabled = settings.liveActivitiesEnabled
            liveActivitySensitiveModeEnabled = settings.liveActivitySensitiveModeEnabled
            swimmingDuckEnabled = settings.swimmingDuckEnabled
            duckCount = settings.duckCount
            reminderStartMinutes = settings.reminderStartMinutes
            reminderEndMinutes = settings.reminderEndMinutes
            reminderIntervalMinutes = settings.reminderIntervalMinutes
            preferredVolumeUnit = VolumeUnit(rawValue: settings.preferredVolumeUnit) ?? .auto
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    func duckName(forCount count: Int) -> String {
        guard count > 0 else { return "Milo" }
        let index = (count - 1) % SwimmingDuckOverlay.configurations.count
        if let custom = settings?.duckNicknames[count] { return custom }
        return NSLocalizedString("duck_name_\(index + 1)", comment: "")
    }

    func duckImageName(forCount count: Int) -> String {
        guard count > 0 else { return "duck_glass" }
        let index = (count - 1) % SwimmingDuckOverlay.configurations.count
        return SwimmingDuckOverlay.configurations[index].imageName
    }

    func renameDuck(atCount count: Int, to name: String) {
        guard let settings else { return }
        var nicknames = settings.duckNicknames
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nicknames.removeValue(forKey: count)
        } else {
            nicknames[count] = String(trimmed.prefix(10))
        }
        settings.duckNicknames = nicknames
        do {
            try services.settingsStore.save()
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    func reloadDuckState() {
        guard let settings = try? services.settingsStore.loadOrCreate() else { return }
        duckCount = settings.duckCount
        swimmingDuckEnabled = settings.swimmingDuckEnabled
    }

    func broadcastForUnitChange() async {
        await broadcastSnapshot(source: .app)
    }

    private func broadcastSnapshot(source: HydrationSnapshotSource) async {
        do {
            let snapshot = try services.hydrationSnapshotProvider.snapshot(for: .now, source: source)
            await services.hydrationBroadcaster.broadcast(snapshot: snapshot)
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    var reminderStartDate: Date {
        get { dateFrom(minutes: reminderStartMinutes) }
        set { reminderStartMinutes = minutesFrom(date: newValue) }
    }

    var reminderEndDate: Date {
        get { dateFrom(minutes: reminderEndMinutes) }
        set { reminderEndMinutes = minutesFrom(date: newValue) }
    }

    func trackSettingToggle(_ setting: String, enabled: Bool) {
        services.analytics.logEvent(AnalyticsEvents.settingChanged, parameters: [
            AnalyticsParams.setting: setting,
            AnalyticsParams.enabled: enabled
        ])
    }

    private func dateFrom(minutes: Int) -> Date {
        let startOfDay = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .minute, value: minutes, to: startOfDay) ?? .now
    }

    private func minutesFrom(date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return max(0, min(23 * 60 + 59, hour * 60 + minute))
    }
}
