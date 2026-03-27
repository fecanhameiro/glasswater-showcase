//
//  OnboardingViewModel.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    nonisolated deinit {}
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var settings: UserSettings?

    var healthStatus: HealthAccessStatus = .unknown
    var notificationsEnabled: Bool = false
    var notificationsStatus: NotificationAccessStatus = .unknown
    var isRequestingHealthAccess: Bool = false

    var dailyGoalMl: Int {
        settings?.dailyGoalMl ?? AppConstants.defaultDailyGoalMl
    }

    init(services: AppServices) {
        self.services = services
        loadSettings()
    }

    func load() async {
        healthStatus = await services.healthService.authorizationStatus()
        notificationsStatus = await services.notificationService.authorizationStatus()
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

    func updateNotifications() async {
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
    }

    func setDailyGoal(_ goalMl: Int) {
        guard let settings else { return }
        settings.dailyGoalMl = goalMl
        do {
            try services.settingsStore.save()
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    func trackStep(_ step: Int, name: String) {
        services.analytics.logEvent(AnalyticsEvents.onboardingStep, parameters: [
            AnalyticsParams.step: step,
            AnalyticsParams.stepName: name
        ])
    }

    func complete() async {
        guard let settings else { return }
        settings.hasCompletedOnboarding = true
        settings.notificationsEnabled = notificationsEnabled
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(true, forKey: AppConstants.appGroupOnboardingCompletedKey)
        WidgetReloadCoordinator.shared.requestReload(source: "onboardingCompleted")
        services.analytics.logEvent(AnalyticsEvents.onboardingCompleted, parameters: [
            AnalyticsParams.goalMl: settings.dailyGoalMl,
            "health_authorized": healthStatus == .authorized,
            "notifications_enabled": notificationsEnabled
        ])
        do {
            try services.settingsStore.save()
        } catch {
            services.crashReporter.record(error: error)
        }

        await services.broadcastCurrentSnapshot(source: .app)

        var total = 0
        var lastEntryDate: Date?
        do {
            total = try services.waterStore.total(for: .now)
            lastEntryDate = try services.waterStore.latestEntryDate()
        } catch {
            AppLog.error("Failed to load water data for onboarding completion: \(error.localizedDescription)", category: .onboarding)
        }
        await services.notificationService.updateReminders(
            isEnabled: notificationsEnabled,
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
    }

    private func loadSettings() {
        do {
            let settings = try services.settingsStore.loadOrCreate()
            self.settings = settings
            notificationsEnabled = settings.notificationsEnabled
        } catch {
            services.crashReporter.record(error: error)
        }
    }
}
