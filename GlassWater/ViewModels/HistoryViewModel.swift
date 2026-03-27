//
//  HistoryViewModel.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    nonisolated deinit {}
    @ObservationIgnored private let services: AppServices
    private let calendar: Calendar

    // MARK: - Data Properties

    var weeklyPoints: [WeeklyIntakePoint] = []
    var dailySummaries: [DailyIntakeSummary] = []
    var dailyGoalMl: Int = AppConstants.defaultDailyGoalMl

    // MARK: - Weekly Insights

    var weeklyTotalMl: Int = 0
    var weeklyAverageMl: Int = 0
    var bestDay: DailyIntakeSummary?
    var currentStreak: Int = 0
    var weeklyGoalMl: Int { dailyGoalMl * 7 }
    var weeklyProgress: Double {
        guard weeklyGoalMl > 0 else { return 0 }
        return min(Double(weeklyTotalMl) / Double(weeklyGoalMl), 1.0)
    }
    var weeklyInsight: WeeklyInsight = .none
    var daysMetGoal: Int = 0

    // MARK: - Selection State

    var selectedDate: Date?

    init(services: AppServices, calendar: Calendar = .autoupdatingCurrent) {
        self.services = services
        self.calendar = calendar
    }

    // MARK: - Load Data

    func load() async {
        do {
            // Load daily goal from settings
            let settings = try services.settingsStore.loadOrCreate()
            dailyGoalMl = settings.dailyGoalMl

            let today = calendar.startOfDay(for: .now)
            let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let rangeEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let listStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
            let didSync = await syncHealthEntries(from: listStart, to: rangeEnd)
            let listEntries = try services.waterStore.entries(from: listStart, to: rangeEnd)

            // Group entries by day
            var entriesByDay: [Date: [WaterEntry]] = [:]
            var totalsByDay: [Date: Int] = [:]
            var countsByDay: [Date: Int] = [:]

            for entry in listEntries {
                let day = calendar.startOfDay(for: entry.date)
                entriesByDay[day, default: []].append(entry)
                totalsByDay[day, default: 0] += entry.amountMl
                countsByDay[day, default: 0] += 1
            }

            // Build weekly points
            weeklyPoints = (0...6).map { offset in
                let day = weekStart.addingDays(offset, calendar: calendar)
                return WeeklyIntakePoint(date: day, amountMl: totalsByDay[day] ?? 0)
            }

            // Build daily summaries with full data
            dailySummaries = Array((0...13).map { offset in
                let day = listStart.addingDays(offset, calendar: calendar)
                let dayEntries = entriesByDay[day] ?? []
                let sortedEntries = dayEntries.sorted { $0.date > $1.date }
                return DailyIntakeSummary(
                    date: day,
                    amountMl: totalsByDay[day] ?? 0,
                    goalMl: dailyGoalMl,
                    entryCount: countsByDay[day] ?? 0,
                    entries: sortedEntries
                )
            }.reversed())

            // Calculate weekly insights
            calculateWeeklyInsights()

            // Calculate streak
            calculateStreak()

            if didSync {
                await broadcastSnapshot(source: .health)
            }
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    // MARK: - Entry Management

    func deleteEntry(_ entry: WaterEntry) async {
        let sampleId = entry.healthSampleId  // Capture BEFORE delete
        SyncLog.info("[Sync] History deleteEntry — amountMl=\(entry.amountMl), sampleId=\(sampleId?.uuidString ?? "nil")")
        do {
            try services.waterStore.deleteEntry(entry)
        } catch {
            SyncLog.error("[Sync] History deleteEntry — SwiftData delete failed: \(error.localizedDescription)")
            services.crashReporter.record(error: error)
            return
        }

        // Delete from HealthKit (best effort — matches HomeViewModel.deleteEntry pattern)
        if let sampleId, await services.healthService.authorizationStatus() == .authorized {
            do {
                try await services.healthService.deleteWaterSample(id: sampleId)
                SyncLog.info("[Sync] History deleteEntry — HK sample deleted")
            } catch {
                SyncLog.error("[Sync] History deleteEntry — HK delete failed: \(error.localizedDescription)")
                services.crashReporter.record(error: error)
            }
        }

        // Small delay to let the HK observer complete before we re-read SwiftData,
        // avoiding concurrent ModelContext access that causes "Data operation failed"
        try? await Task.sleep(for: .milliseconds(150))
        await load()
        await services.refreshNotifications(applySmartRules: false)
        await broadcastSnapshot(source: .app)
        NotificationCenter.default.post(name: .hydrationDidChangeFromHistory, object: nil)
        SyncLog.info("[Sync] History deleteEntry DONE — broadcast + notify sent")
    }

    func updateEntry(_ entry: WaterEntry, amountMl: Int, date: Date) async {
        SyncLog.info("[Sync] History updateEntry — oldAmount=\(entry.amountMl), newAmount=\(amountMl), oldSampleId=\(entry.healthSampleId?.uuidString ?? "nil")")
        var newSampleId: UUID?
        var isFromHealth = false

        if await services.healthService.authorizationStatus() == .authorized {
            do {
                let savedId = try await services.healthService.saveWaterIntake(amountMl: amountMl, date: date)
                newSampleId = savedId
                isFromHealth = true
                SyncLog.info("[Sync] History updateEntry — new HK sample saved: \(savedId)")
            } catch {
                SyncLog.error("[Sync] History updateEntry — HK save failed: \(error.localizedDescription)")
                services.crashReporter.record(error: error)
            }

            // Delete old sample independently — failure must not discard the new sample reference
            if let oldSampleId = entry.healthSampleId {
                do {
                    try await services.healthService.deleteWaterSample(id: oldSampleId)
                    SyncLog.info("[Sync] History updateEntry — old HK sample deleted: \(oldSampleId)")
                } catch {
                    SyncLog.error("[Sync] History updateEntry — old HK delete failed: \(error.localizedDescription)")
                    services.crashReporter.record(error: error)
                }
            }
        }

        do {
            try services.waterStore.updateEntry(
                entry,
                amountMl: amountMl,
                date: date,
                isFromHealth: isFromHealth,
                healthSampleId: newSampleId
            )
        } catch {
            SyncLog.error("[Sync] History updateEntry — SwiftData update failed: \(error.localizedDescription)")
            services.crashReporter.record(error: error)
        }

        // Small delay to let the HK observer complete before we re-read SwiftData
        try? await Task.sleep(for: .milliseconds(150))
        await load()
        await services.refreshNotifications(applySmartRules: false)
        await broadcastSnapshot(source: .app)
        NotificationCenter.default.post(name: .hydrationDidChangeFromHistory, object: nil)
        SyncLog.info("[Sync] History updateEntry DONE — broadcast + notify sent")
    }

    // MARK: - Private Methods

    private func calculateWeeklyInsights() {
        // Get only the last 7 days for weekly calculations
        let weekSummaries = dailySummaries.prefix(7)

        // Total and average
        weeklyTotalMl = weekSummaries.reduce(0) { $0 + $1.amountMl }
        weeklyAverageMl = weekSummaries.isEmpty ? 0 : Int((Double(weeklyTotalMl) / Double(weekSummaries.count)).rounded())

        // Best day
        bestDay = weekSummaries.max(by: { $0.amountMl < $1.amountMl })

        // Days that met goal
        daysMetGoal = weekSummaries.filter { $0.isGoalMet }.count

        // Calculate insight
        weeklyInsight = determineWeeklyInsight(from: Array(weekSummaries))
    }

    private func determineWeeklyInsight(from summaries: [DailyIntakeSummary]) -> WeeklyInsight {
        guard !summaries.isEmpty else { return .none }

        // Check if great week (5+ days met goal)
        if daysMetGoal >= 5 {
            return .greatWeek
        }

        // Check for improving trend (last 3 days better than first 3)
        if summaries.count >= 6 {
            let recentAvg = summaries.prefix(3).reduce(0) { $0 + $1.amountMl } / 3
            let olderAvg = summaries.suffix(3).reduce(0) { $0 + $1.amountMl } / 3
            if recentAvg > olderAvg + 200 {
                return .improvingTrend
            }
        }

        // Check consistency (low variance)
        let amounts = summaries.map { $0.amountMl }
        let nonZeroAmounts = amounts.filter { $0 > 0 }
        if nonZeroAmounts.count >= 4 {
            let avg = nonZeroAmounts.reduce(0, +) / nonZeroAmounts.count
            let variance = nonZeroAmounts.map { abs($0 - avg) }.reduce(0, +) / nonZeroAmounts.count
            if variance < 300 && avg > dailyGoalMl / 2 {
                return .consistentHydration
            }
        }

        // Check if needs more water (average below 50% of goal)
        if weeklyAverageMl < dailyGoalMl / 2 && weeklyAverageMl > 0 {
            return .needsMoreWater
        }

        // Analyze time patterns from entries
        var morningTotal = 0
        var afternoonTotal = 0
        var eveningTotal = 0

        for summary in summaries {
            for entry in summary.entries {
                let hour = calendar.component(.hour, from: entry.date)
                switch hour {
                case 5..<12:
                    morningTotal += entry.amountMl
                case 12..<18:
                    afternoonTotal += entry.amountMl
                default:
                    eveningTotal += entry.amountMl
                }
            }
        }

        let total = morningTotal + afternoonTotal + eveningTotal
        guard total > 0 else { return .none }

        let morningRatio = Double(morningTotal) / Double(total)
        let afternoonRatio = Double(afternoonTotal) / Double(total)
        let eveningRatio = Double(eveningTotal) / Double(total)

        if morningRatio > 0.45 {
            return .morningPerson
        } else if afternoonRatio > 0.45 {
            return .afternoonPerson
        } else if eveningRatio > 0.45 {
            return .eveningPerson
        }

        return .none
    }

    private func calculateStreak() {
        currentStreak = 0

        // Start from today and go backwards
        let today = calendar.startOfDay(for: .now)

        for summary in dailySummaries {
            // Skip future dates
            if summary.date > today { continue }

            // Skip today if it hasn't met goal yet (don't break streak)
            if calendar.isDateInToday(summary.date) && !summary.isGoalMet {
                continue
            }

            // If this day met goal, increment streak
            if summary.isGoalMet {
                currentStreak += 1
            } else {
                // Streak broken
                break
            }
        }
    }

    private func broadcastSnapshot(source: HydrationSnapshotSource) async {
        do {
            let snapshot = try services.hydrationSnapshotProvider.snapshot(for: .now, source: source)
            await services.hydrationBroadcaster.broadcast(snapshot: snapshot)
        } catch {
            services.crashReporter.record(error: error)
        }
    }

    private func syncHealthEntries(from startDate: Date, to endDate: Date) async -> Bool {
        let status = await services.healthService.authorizationStatus()
        guard status == .authorized else { return false }
        do {
            let samples = try await services.healthService.fetchWaterSamples(from: startDate, to: endDate)
            let localEntries = try services.waterStore.entries(from: startDate, to: endDate)
            let localHealthEntries = localEntries.filter { $0.isFromHealth && $0.healthSampleId != nil }
            let localIds = Set(localHealthEntries.compactMap(\.healthSampleId))
            let sampleIds = Set(samples.map(\.id))
            var didChange = false

            for sample in samples where !localIds.contains(sample.id) {
                // Skip if a non-health entry with matching amount+time exists nearby.
                // This happens when the phone saves to HK on behalf of the watch — the entry
                // exists (isFromHealth=false) but hasn't been updated with the real HK sampleId yet.
                let hasMatchingPendingEntry = localEntries.contains { entry in
                    !entry.isFromHealth &&
                    entry.healthSampleId == nil &&
                    entry.amountMl == sample.amountMl &&
                    abs(entry.date.timeIntervalSince(sample.date)) < 5
                }
                if hasMatchingPendingEntry {
                    continue
                }
                _ = try services.waterStore.addEntry(
                    amountMl: sample.amountMl,
                    date: sample.date,
                    isFromHealth: true,
                    healthSampleId: sample.id
                )
                didChange = true
            }

            // Only remove entries whose healthSampleId is missing from HealthKit
            // AND that are older than 60s. Entries from the watch arrive via
            // transferUserInfo before HealthKit cross-device sync completes (~5-30s).
            let removalCutoff = Date.now.addingTimeInterval(-60)
            for entry in localHealthEntries {
                guard let id = entry.healthSampleId else { continue }
                if !sampleIds.contains(id) {
                    if entry.date > removalCutoff {
                        continue
                    }
                    try services.waterStore.deleteEntry(entry)
                    didChange = true
                }
            }
            return didChange
        } catch {
            services.crashReporter.record(error: error)
            return false
        }
    }
}
