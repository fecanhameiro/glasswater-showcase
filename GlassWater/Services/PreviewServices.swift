//
//  PreviewServices.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import StoreKit

@MainActor
final class PreviewWaterStore: WaterStore {
    func addEntry(
        amountMl: Int,
        date: Date,
        isFromHealth: Bool,
        healthSampleId: UUID?
    ) throws -> WaterEntry {
        WaterEntry(date: date, amountMl: amountMl)
    }

    func entries(from startDate: Date, to endDate: Date) throws -> [WaterEntry] {
        let calendar = Calendar.autoupdatingCurrent
        return (0...6).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            return WaterEntry(date: date, amountMl: 1200 + (offset * 100))
        }
    }

    func entriesMissingHealthSample() throws -> [WaterEntry] {
        []
    }

    func total(for date: Date) throws -> Int {
        1200
    }

    func latestEntry() throws -> WaterEntry? {
        WaterEntry(date: Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -2, to: .now) ?? .now, amountMl: 250)
    }

    func latestTodayEntry(for date: Date) throws -> WaterEntry? {
        WaterEntry(date: Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -2, to: date) ?? date, amountMl: 250)
    }

    func latestEntryDate() throws -> Date? {
        Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -2, to: .now)
    }

    func updateEntry(
        _ entry: WaterEntry,
        amountMl: Int,
        date: Date,
        isFromHealth: Bool,
        healthSampleId: UUID?
    ) throws {
    }

    func entryWithHealthSampleId(_ sampleId: UUID) throws -> WaterEntry? {
        nil
    }

    func deleteEntry(_ entry: WaterEntry) throws {
    }

    func save() throws {
    }
}

@MainActor
final class PreviewSettingsStore: SettingsStore {
    private let settings = UserSettings()

    func loadOrCreate() throws -> UserSettings {
        settings
    }

    func save() throws {
    }

    func invalidateCache() {
    }
}

final class PreviewHealthService: HealthKitServicing {
    func isHealthDataAvailable() -> Bool {
        true
    }

    func authorizationStatus() async -> HealthAccessStatus {
        .authorized
    }

    func requestAuthorization() async throws -> HealthAccessStatus {
        .authorized
    }

    func fetchWaterSamples(from startDate: Date, to endDate: Date) async throws -> [HealthWaterSample] {
        let calendar = Calendar.autoupdatingCurrent
        return (0...3).map { offset in
            let date = calendar.date(byAdding: .hour, value: -offset, to: endDate) ?? endDate
            return HealthWaterSample(id: UUID(), date: date, amountMl: 250)
        }
    }

    func fetchWaterIntake(from startDate: Date, to endDate: Date) async throws -> Int {
        1200
    }

    func fetchDailyIntake(from startDate: Date, to endDate: Date, calendar: Calendar) async throws -> [Date: Int] {
        var totals: [Date: Int] = [:]
        var day = calendar.startOfDay(for: startDate)
        while day < endDate {
            totals[day] = 1200
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? endDate
        }
        return totals
    }

    func saveWaterIntake(amountMl: Int, date: Date) async throws -> UUID {
        UUID()
    }

    func deleteWaterSample(id: UUID) async throws {
    }

    func startObservingWaterChanges(onUpdate: @escaping () -> Void) async {
    }

    func stopObservingWaterChanges() async {
    }
}

final class PreviewNotificationService: NotificationServicing {
    func requestAuthorization() async -> Bool {
        true
    }

    func requestProvisionalAuthorization() async -> Bool {
        true
    }

    func authorizationStatus() async -> NotificationAccessStatus {
        .authorized
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
    }

    func clearDeliveredReminders() async {
    }
}

final class PreviewHapticsService: HapticsServicing {
    func lightImpact() {
    }

    func mediumImpact() {
    }

    func success() {
    }
}

final class PreviewLiveActivityService: LiveActivityServicing {
    func update(
        currentMl: Int,
        dailyGoalMl: Int,
        lastIntakeMl: Int?,
        lastIntakeDate: Date?,
        customAmountMl: Int?,
        isSensitive: Bool,
        date: Date
    ) async {
    }

    func end() async {
    }
}

@MainActor
final class PreviewHydrationSnapshotProvider: HydrationSnapshotProviding {
    func snapshot(for date: Date, source: HydrationSnapshotSource) throws -> HydrationSnapshot {
        HydrationSnapshot(
            updatedAt: date,
            dayStart: Calendar.autoupdatingCurrent.startOfDay(for: date),
            totalMl: 1200,
            goalMl: AppConstants.defaultDailyGoalMl,
            progress: 0.48,
            remainingMl: 1300,
            goalReached: false,
            lastIntakeMl: 250,
            lastIntakeDate: Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -1, to: date),
            customAmountMl: AppConstants.defaultCustomAmountMl,
            source: source
        )
    }
}

@MainActor
final class PreviewHydrationUpdateBroadcaster: HydrationUpdateBroadcasting {
    func broadcast(snapshot: HydrationSnapshot) async {
    }
}

final class PreviewTipJarService: TipJarServicing {
    func fetchProducts() async throws -> [Product] {
        []
    }

    func purchase(_ product: Product) async throws -> TipJarPurchaseResult {
        .success
    }

    func listenForTransactions(onVerified: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task {}
    }
}
