//
//  NotificationActionHandler.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationActionHandler {
    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func handle(response: UNNotificationResponse) async {
        let identifier = response.actionIdentifier

        if identifier == UNNotificationDismissActionIdentifier { return }

        if identifier == UNNotificationDefaultActionIdentifier {
            services.analytics.logEvent(AnalyticsEvents.notificationTapped, parameters: [
                AnalyticsParams.timeOfDay: AnalyticsTimeOfDay.current()
            ])
            NotificationCenter.default.post(name: .notificationTapped, object: nil)
            return
        }

        if identifier == NotificationAction.snoozeIdentifier {
            services.analytics.logEvent(AnalyticsEvents.notificationSnooze, parameters: [
                AnalyticsParams.timeOfDay: AnalyticsTimeOfDay.current()
            ])
            await scheduleSnoozeReminder()
            return
        }

        do {
            // Resolve action values at tap time using persisted settings to avoid relying on
            // immutable notification action payloads.
            let settings = try services.settingsStore.loadOrCreate()
            guard let amountMl = resolvedAmount(from: response, settings: settings) else { return }
            if shouldPersistCustomAmount(for: identifier) {
                settings.lastCustomAmountMl = amountMl
                try services.settingsStore.save()
            }
            await recordIntake(amountMl: amountMl, actionIdentifier: identifier)
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    private func resolvedAmount(from response: UNNotificationResponse, settings: UserSettings) -> Int? {
        if let percent = NotificationAction.percent(from: response.actionIdentifier) {
            return QuickAddOptions.amount(forPercent: percent, goalMl: settings.dailyGoalMl)
        }
        if response.actionIdentifier == NotificationAction.customSavedIdentifier {
            let amount = QuickAddOptions.resolvedCustomAmount(forGoalMl: settings.dailyGoalMl, customAmountMl: settings.lastCustomAmountMl)
            return QuickAddOptions.clampCustomAmount(amount)
        }
        if let customAmount = NotificationAction.customAmount(from: response.actionIdentifier) {
            return QuickAddOptions.clampCustomAmount(customAmount)
        }
        if response.actionIdentifier == NotificationAction.customInputIdentifier,
           let textResponse = response as? UNTextInputNotificationResponse,
           let inputAmount = parseAmount(from: textResponse.userText)
        {
            return QuickAddOptions.clampCustomAmount(inputAmount)
        }
        return nil
    }

    private func shouldPersistCustomAmount(for identifier: String) -> Bool {
        identifier == NotificationAction.customInputIdentifier
            || identifier == NotificationAction.customSavedIdentifier
            || NotificationAction.customAmount(from: identifier) != nil
    }

    private func parseAmount(from input: String) -> Int? {
        let digits = input.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        guard !digits.isEmpty else { return nil }
        return Int(String(String.UnicodeScalarView(digits)))
    }

    private func recordIntake(amountMl: Int, actionIdentifier: String) async {
        var entry: WaterEntry?
        do {
            entry = try services.waterStore.addEntry(
                amountMl: amountMl,
                date: .now,
                isFromHealth: false,
                healthSampleId: nil
            )
        } catch {
            services.crashReporter.record(error: error)
        }

        guard let entry else { return }

        services.analytics.logEvent(AnalyticsEvents.waterAdded, parameters: [
            AnalyticsParams.amountMl: amountMl,
            AnalyticsParams.source: "notification",
            AnalyticsParams.timeOfDay: AnalyticsTimeOfDay.current(),
            AnalyticsParams.actionType: actionTypeLabel(for: actionIdentifier)
        ])
        // Clear delivered reminders immediately, then reschedule + broadcast
        await services.notificationService.clearDeliveredReminders()
        await refreshReminders()
        await broadcastSnapshot(source: .notification)
        await syncHealth(for: entry, amountMl: amountMl)
    }

    private func actionTypeLabel(for identifier: String) -> String {
        if let percent = NotificationAction.percent(from: identifier) {
            return "percent_\(percent)"
        }
        if identifier == NotificationAction.customSavedIdentifier {
            return "custom_saved"
        }
        if identifier == NotificationAction.customInputIdentifier {
            return "custom_input"
        }
        if NotificationAction.customAmount(from: identifier) != nil {
            return "custom_amount"
        }
        return "unknown"
    }

    private func syncHealth(for entry: WaterEntry, amountMl: Int) async {
        let status = await services.healthService.authorizationStatus()
        guard status == .authorized else { return }
        do {
            let sampleId = try await services.healthService.saveWaterIntake(amountMl: amountMl, date: entry.date)
            try services.waterStore.updateEntry(
                entry,
                amountMl: amountMl,
                date: entry.date,
                isFromHealth: true,
                healthSampleId: sampleId
            )
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    private func refreshReminders() async {
        await services.refreshNotifications(applySmartRules: true)
    }

    private func broadcastSnapshot(source: HydrationSnapshotSource) async {
        do {
            let snapshot = try services.hydrationSnapshotProvider.snapshot(for: .now, source: source)
            await services.hydrationBroadcaster.broadcast(snapshot: snapshot)
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    private func scheduleSnoozeReminder() async {
        let center = UNUserNotificationCenter.current()
        do {
            let settings = try services.settingsStore.loadOrCreate()
            let total = try services.waterStore.total(for: .now)
            let progress = settings.dailyGoalMl > 0
                ? Double(total) / Double(settings.dailyGoalMl) : 0

            let snoozeDate = Date.now.addingTimeInterval(30 * 60)
            let context = NotificationContentFactory.Context(
                currentTotalMl: total,
                dailyGoalMl: settings.dailyGoalMl,
                date: snoozeDate,
                streakCount: settings.streakCount
            )
            let message = NotificationContentFactory.makeContent(context: context)

            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            content.categoryIdentifier = NotificationAction.reminderCategory
            content.interruptionLevel = .passive
            content.threadIdentifier = "glasswater.hydration"
            content.relevanceScore = max(0, min(1.0 - progress, 1))
            content.targetContentIdentifier = "home"

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)
            let request = UNNotificationRequest(
                identifier: NotificationAction.snoozeReminderIdentifier,
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        } catch {
            services.crashReporter.record(error: error)
        }
    }
}

extension Notification.Name {
    static let notificationTapped = Notification.Name("glasswater.notificationTapped")
}
