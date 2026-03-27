//
//  NotificationService.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import UserNotifications

protocol NotificationServicing {
    func requestAuthorization() async -> Bool
    func requestProvisionalAuthorization() async -> Bool
    func authorizationStatus() async -> NotificationAccessStatus
    func updateReminders(
        isEnabled: Bool,
        currentTotalMl: Int,
        dailyGoalMl: Int,
        customAmountMl: Int?,
        reminderStartMinutes: Int,
        reminderEndMinutes: Int,
        reminderIntervalMinutes: Int,
        lastEntryDate: Date?,
        streakCount: Int,
        date: Date
    ) async
    func applyIntelligentRules(
        isEnabled: Bool,
        currentTotalMl: Int,
        dailyGoalMl: Int,
        reminderStartMinutes: Int,
        reminderEndMinutes: Int,
        lastEntryDate: Date?,
        date: Date
    ) async
    func clearDeliveredReminders() async
}

final class NotificationService: NotificationServicing {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar
    private let postDrinkCooldownInterval = AppConstants.notificationPostDrinkCooldownSeconds
    private let nearGoalThreshold = AppConstants.notificationNearGoalThreshold
    private let intelligentCooldownInterval = AppConstants.notificationIntelligentCooldownSeconds
    private let progressAheadMargin = AppConstants.notificationProgressAheadMargin
    private let reminderIdentifierPrefix = "glasswater.reminder."
    private let catchUpBehindMargin = AppConstants.notificationCatchUpBehindMargin
    private let catchUpIdentifier = "glasswater.catchup"
    private let maxReminderSlots = AppConstants.notificationMaxReminderSlots
    private let crashReporter: any CrashReporting
    private var lastActionCacheKey: String?

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .autoupdatingCurrent,
        crashReporter: any CrashReporting = NoopCrashReportingService()
    ) {
        self.center = center
        self.calendar = calendar
        self.crashReporter = crashReporter
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            AppLog.info("Notification authorization \(granted ? "granted" : "denied")", category: .notifications)
            return granted
        } catch {
            AppLog.error("Notification authorization request failed: \(error.localizedDescription)", category: .notifications)
            crashReporter.record(error: error)
            return false
        }
    }

    func requestProvisionalAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .provisional])
            AppLog.info("Provisional notification authorization \(granted ? "granted" : "denied")", category: .notifications)
            return granted
        } catch {
            AppLog.error("Provisional notification authorization failed: \(error.localizedDescription)", category: .notifications)
            crashReporter.record(error: error)
            return false
        }
    }

    func authorizationStatus() async -> NotificationAccessStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }

    func updateReminders(
        isEnabled: Bool,
        currentTotalMl: Int,
        dailyGoalMl: Int,
        customAmountMl: Int?,
        reminderStartMinutes: Int,
        reminderEndMinutes: Int,
        reminderIntervalMinutes: Int,
        lastEntryDate: Date?,
        streakCount: Int,
        date: Date
    ) async {
        let settings = await center.notificationSettings()
        let authorization = settings.authorizationStatus
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else {
            await clearPendingReminders()
            return
        }

        await clearDeliveredReminders()
        configureInteractiveActions(dailyGoalMl: dailyGoalMl, customAmountMl: customAmountMl)
        guard isEnabled, dailyGoalMl > 0 else {
            AppLog.info("[Notif] Cleared all: reason=disabled|noGoal", category: .notifications)
            await clearPendingReminders()
            return
        }
        let progress = Double(currentTotalMl) / Double(max(1, dailyGoalMl))
        #if DEBUG
        AppLog.info("[Notif] updateReminders: total=\(currentTotalMl)ml goal=\(dailyGoalMl)ml progress=\(Int(progress * 100))% lastEntry=\(lastEntryDate?.description ?? "nil")", category: .notifications)
        #endif
        guard currentTotalMl < dailyGoalMl else {
            AppLog.info("[Notif] Cleared all: reason=goalReached", category: .notifications)
            await clearPendingReminders()
            return
        }
        guard progress < nearGoalThreshold else {
            AppLog.info("[Notif] Cleared all: reason=nearGoal(\(Int(progress * 100))%>=\(Int(nearGoalThreshold * 100))%)", category: .notifications)
            await clearPendingReminders()
            return
        }

        let remainingMl = max(0, dailyGoalMl - currentTotalMl)

        // Today's reminders — filtered by last entry cooldown
        let todayDates = ReminderSchedule.scheduleDates(
            referenceDate: date,
            startMinutes: reminderStartMinutes,
            endMinutes: reminderEndMinutes,
            intervalMinutes: reminderIntervalMinutes
        )
        let filteredTodayDates = todayDates.filter { reminderDate in
            guard let lastEntryDate else { return true }
            let timeFromNow = reminderDate.timeIntervalSince(date)
            // Only evaluate cooldown for imminent reminders
            guard timeFromNow < postDrinkCooldownInterval else { return true }
            return reminderDate.timeIntervalSince(lastEntryDate) >= postDrinkCooldownInterval
        }
        let suppressedByCooldown = todayDates.count - filteredTodayDates.count
        if suppressedByCooldown > 0 {
            #if DEBUG
            AppLog.info("[Notif] Cooldown: suppressed \(suppressedByCooldown)/\(todayDates.count) today slots", category: .notifications)
            #endif
        }

        // Catch-up: if user is significantly behind schedule, add one extra reminder
        await scheduleCatchUpIfNeeded(
            filteredTodayDates: filteredTodayDates,
            date: date,
            progress: progress,
            remainingMl: remainingMl,
            dailyGoalMl: dailyGoalMl,
            streakCount: streakCount,
            reminderStartMinutes: reminderStartMinutes,
            reminderEndMinutes: reminderEndMinutes
        )

        // Tomorrow's reminders — safety net in case app doesn't open or background refresh is delayed
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let tomorrowDates = ReminderSchedule.scheduleDates(
            referenceDate: tomorrow,
            startMinutes: reminderStartMinutes,
            endMinutes: reminderEndMinutes,
            intervalMinutes: reminderIntervalMinutes
        )

        // Combine and cap at maxReminderSlots
        let todayLimited = Array(filteredTodayDates.prefix(maxReminderSlots))
        let tomorrowSlots = max(0, maxReminderSlots - todayLimited.count)
        let tomorrowLimited = Array(tomorrowDates.prefix(tomorrowSlots))

        let allDesiredDates = todayLimited + tomorrowLimited
        let desiredIdentifiers = Set(allDesiredDates.map(reminderIdentifier(for:)))
        let pendingIdentifiers = await pendingReminderIdentifiers()
        let identifiersToRemove = pendingIdentifiers.subtracting(desiredIdentifiers)

        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(identifiersToRemove))
        }

        let todayIdentifiers = Set(todayLimited.map(reminderIdentifier(for:)))
        var scheduledCount = 0

        for reminderDate in allDesiredDates {
            let identifier = reminderIdentifier(for: reminderDate)
            guard !pendingIdentifiers.contains(identifier) else { continue }

            let isToday = todayIdentifiers.contains(identifier)
            let dateContext = NotificationContentFactory.Context(
                currentTotalMl: isToday ? currentTotalMl : 0,
                dailyGoalMl: dailyGoalMl,
                date: reminderDate,
                streakCount: streakCount
            )
            let isLastTodayReminder = isToday && reminderDate == todayLimited.last
            await scheduleReminder(
                identifier: identifier,
                date: reminderDate,
                contentContext: dateContext,
                remainingMl: isToday ? remainingMl : dailyGoalMl,
                progress: isToday ? progress : 0,
                isLastReminder: isLastTodayReminder
            )
            scheduledCount += 1
        }
        if scheduledCount > 0 || !identifiersToRemove.isEmpty {
            #if DEBUG
            AppLog.info("[Notif] Result: \(scheduledCount) new, \(identifiersToRemove.count) removed, today=\(todayLimited.count) tomorrow=\(tomorrowLimited.count)", category: .notifications)
            #endif
        }
        crashReporter.setCustomValue("\(todayLimited.count)+\(tomorrowLimited.count)", forKey: "notif_scheduled")
        crashReporter.setCustomValue(Int(progress * 100), forKey: "notif_hydration_pct")
    }

    func applyIntelligentRules(
        isEnabled: Bool,
        currentTotalMl: Int,
        dailyGoalMl: Int,
        reminderStartMinutes: Int,
        reminderEndMinutes: Int,
        lastEntryDate: Date?,
        date: Date
    ) async {
        guard isEnabled, dailyGoalMl > 0 else { return }

        let pendingRequests = await center.pendingNotificationRequests()

        // Sort by trigger date so we process closest-first
        let sortedRequests = pendingRequests
            .filter { $0.identifier.hasPrefix(reminderIdentifierPrefix) }
            .compactMap { request -> (UNNotificationRequest, Date)? in
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let nextDate = trigger.nextTriggerDate(),
                      nextDate >= date
                else { return nil }
                return (request, nextDate)
            }
            .sorted { $0.1 < $1.1 }

        var identifiersToRemove: [String] = []
        var didSuppressForProgress = false
        var cooldownCount = 0
        var progressCount = 0

        for (request, nextDate) in sortedRequests {
            let cooldown = shouldSuppressForCooldown(
                nextReminderDate: nextDate,
                lastEntryDate: lastEntryDate
            )

            // Only suppress ONE reminder for progress (the nearest one)
            let progress = !didSuppressForProgress && shouldSuppressForProgress(
                currentTotalMl: currentTotalMl,
                dailyGoalMl: dailyGoalMl,
                reminderStartMinutes: reminderStartMinutes,
                reminderEndMinutes: reminderEndMinutes,
                reminderDate: nextDate
            )

            if cooldown || progress {
                identifiersToRemove.append(request.identifier)
                if cooldown { cooldownCount += 1 }
                if progress {
                    progressCount += 1
                    didSuppressForProgress = true
                }
            }
        }

        if !identifiersToRemove.isEmpty {
            #if DEBUG
            AppLog.info("[Notif] IntelligentRules: suppressed \(identifiersToRemove.count) (cooldown: \(cooldownCount), progress: \(progressCount))", category: .notifications)
            #endif
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }
    }

    private func reminderIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(
            format: "%@%04d%02d%02d-%02d%02d",
            reminderIdentifierPrefix,
            year,
            month,
            day,
            hour,
            minute
        )
    }

    private func pendingReminderIdentifiers() async -> Set<String> {
        let pendingRequests = await center.pendingNotificationRequests()
        return Set(pendingRequests.compactMap { request in
            guard request.identifier.hasPrefix(reminderIdentifierPrefix) else { return nil }
            return request.identifier
        })
    }

    private func shouldSuppressForCooldown(nextReminderDate: Date, lastEntryDate: Date?) -> Bool {
        guard let lastEntryDate else { return false }
        let interval = nextReminderDate.timeIntervalSince(lastEntryDate)
        return interval >= 0 && interval <= intelligentCooldownInterval
    }

    private func shouldSuppressForProgress(
        currentTotalMl: Int,
        dailyGoalMl: Int,
        reminderStartMinutes: Int,
        reminderEndMinutes: Int,
        reminderDate: Date
    ) -> Bool {
        guard currentTotalMl > 0, dailyGoalMl > 0 else { return false }
        let currentProgress = Double(currentTotalMl) / Double(dailyGoalMl)
        let expected = expectedProgress(
            at: reminderDate,
            startMinutes: reminderStartMinutes,
            endMinutes: reminderEndMinutes
        )
        // Only suppress if user is significantly ahead of schedule
        return currentProgress >= (expected + progressAheadMargin)
    }

    private func expectedProgress(at date: Date, startMinutes: Int, endMinutes: Int) -> Double {
        let startOfDay = calendar.startOfDay(for: date)
        let reminderMinutes = minutesFrom(date: date)
        let clampedStart = max(0, min(24 * 60 - 1, startMinutes))
        let clampedEnd = max(0, min(24 * 60 - 1, endMinutes))

        let startDate: Date
        let endDate: Date

        if clampedStart <= clampedEnd {
            startDate = calendar.date(byAdding: .minute, value: clampedStart, to: startOfDay) ?? startOfDay
            endDate = calendar.date(byAdding: .minute, value: clampedEnd, to: startOfDay) ?? startOfDay
        } else if reminderMinutes >= clampedStart {
            startDate = calendar.date(byAdding: .minute, value: clampedStart, to: startOfDay) ?? startOfDay
            let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            endDate = calendar.date(byAdding: .minute, value: clampedEnd, to: nextDay) ?? nextDay
        } else {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            startDate = calendar.date(byAdding: .minute, value: clampedStart, to: previousDay) ?? previousDay
            endDate = calendar.date(byAdding: .minute, value: clampedEnd, to: startOfDay) ?? startOfDay
        }

        let duration = endDate.timeIntervalSince(startDate)
        guard duration > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        let progress = elapsed / duration
        return min(max(progress, 0), 1)
    }

    private func minutesFrom(date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }

    private func scheduleCatchUpIfNeeded(
        filteredTodayDates: [Date],
        date: Date,
        progress: Double,
        remainingMl: Int,
        dailyGoalMl: Int,
        streakCount: Int,
        reminderStartMinutes: Int,
        reminderEndMinutes: Int
    ) async {
        guard let nextRegularDate = filteredTodayDates.first else {
            center.removePendingNotificationRequests(withIdentifiers: [catchUpIdentifier])
            return
        }
        let expected = expectedProgress(at: date, startMinutes: reminderStartMinutes, endMinutes: reminderEndMinutes)
        let isBehind = progress < (expected - catchUpBehindMargin) && expected > 0.1
        guard isBehind else {
            center.removePendingNotificationRequests(withIdentifiers: [catchUpIdentifier])
            return
        }
        let midpoint = date.addingTimeInterval(nextRegularDate.timeIntervalSince(date) / 2)
        guard midpoint.timeIntervalSince(date) >= 15 * 60 else { return }

        let context = NotificationContentFactory.Context(
            currentTotalMl: dailyGoalMl - remainingMl,
            dailyGoalMl: dailyGoalMl,
            date: midpoint,
            streakCount: streakCount
        )
        let message = NotificationContentFactory.makeContent(context: context)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.categoryIdentifier = NotificationAction.reminderCategory
        content.interruptionLevel = .active
        content.threadIdentifier = "glasswater.hydration"
        content.relevanceScore = 1.0
        content.targetContentIdentifier = "home"
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: midpoint)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: catchUpIdentifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            AppLog.info("[Notif] CatchUp: scheduled at \(midpoint) (progress \(Int(progress * 100))% vs expected \(Int(expected * 100))%)", category: .notifications)
        } catch {
            AppLog.error("Failed to schedule catch-up reminder: \(error.localizedDescription)", category: .notifications)
            crashReporter.record(error: error)
        }
    }

    private func clearPendingReminders() async {
        var identifiers = Array(await pendingReminderIdentifiers())
        identifiers.append(NotificationAction.snoozeReminderIdentifier)
        identifiers.append(catchUpIdentifier)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        await clearDeliveredReminders()
    }

    func clearDeliveredReminders() async {
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered
            .map(\.request.identifier)
            .filter { $0.hasPrefix(reminderIdentifierPrefix) || $0 == NotificationAction.snoozeReminderIdentifier }
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func scheduleReminder(
        identifier: String,
        date: Date,
        contentContext: NotificationContentFactory.Context,
        remainingMl: Int,
        progress: Double,
        isLastReminder: Bool = false
    ) async {
        let message = NotificationContentFactory.makeContent(context: contentContext)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.categoryIdentifier = NotificationAction.reminderCategory
        content.interruptionLevel = resolveInterruptionLevel(progress: progress, isLastReminder: isLastReminder)
        content.threadIdentifier = "glasswater.hydration"
        content.relevanceScore = max(0, min(1.0 - progress, 1))
        content.targetContentIdentifier = "home"

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            AppLog.error("Failed to schedule notification reminder: \(error.localizedDescription)", category: .notifications)
            crashReporter.record(error: error)
        }
    }

    private func resolveInterruptionLevel(progress: Double, isLastReminder: Bool) -> UNNotificationInterruptionLevel {
        // Last reminder of the day with low progress — break through Focus Mode
        if isLastReminder && progress < 0.5 {
            return .timeSensitive
        }
        return .passive
    }

    private func configureInteractiveActions(dailyGoalMl: Int, customAmountMl: Int?) {
        let cacheKey = "\(dailyGoalMl)-\(customAmountMl ?? 0)"
        guard cacheKey != lastActionCacheKey else { return }

        // NOTE: Actions are immutable per delivered notification. We keep identifiers stable and
        // resolve any amounts at tap time inside NotificationActionHandler to avoid stale values.
        // Labels show absolute mL for clarity (e.g. "Add 250 ml" instead of "Add 10%").

        // Always include 10% and 15%
        let firstTwoPercents = AppConstants.quickAddPercents.prefix(2)
        let allPercentAmounts = AppConstants.quickAddPercents.map { QuickAddOptions.amount(forPercent: $0, goalMl: dailyGoalMl) }

        var actions: [UNNotificationAction] = firstTwoPercents.map { percent in
            let amountMl = QuickAddOptions.amount(forPercent: percent, goalMl: dailyGoalMl)
            let label = VolumeFormatters.string(fromMl: amountMl)
            return UNNotificationAction(
                identifier: NotificationAction.percentIdentifier(percent),
                title: String(format: String(localized: "notification_action_add %@"), label),
                options: []
            )
        }

        // 3rd button: custom amount if different from all percent options, otherwise 25%
        if let saved = customAmountMl, !allPercentAmounts.contains(saved) {
            let label = VolumeFormatters.string(fromMl: saved)
            actions.append(UNNotificationAction(
                identifier: NotificationAction.customSavedIdentifier,
                title: String(format: String(localized: "notification_action_add %@"), label),
                options: []
            ))
        } else if let lastPercent = AppConstants.quickAddPercents.last {
            let amountMl = QuickAddOptions.amount(forPercent: lastPercent, goalMl: dailyGoalMl)
            let label = VolumeFormatters.string(fromMl: amountMl)
            actions.append(UNNotificationAction(
                identifier: NotificationAction.percentIdentifier(lastPercent),
                title: String(format: String(localized: "notification_action_add %@"), label),
                options: []
            ))
        }

        // 4th button: snooze
        actions.append(UNNotificationAction(
            identifier: NotificationAction.snoozeIdentifier,
            title: String(localized: "notification_action_snooze"),
            options: []
        ))

        // iOS displays up to 4 actions in the expanded notification view
        let reminderCategory = UNNotificationCategory(
            identifier: NotificationAction.reminderCategory,
            actions: Array(actions.prefix(4)),
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([reminderCategory])
        lastActionCacheKey = cacheKey
    }
}
