//
//  TestMocks.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import Foundation
import StoreKit

@testable import GlassWater

// MARK: - Mock Water Store

final class MockWaterStore: WaterStore {
    var entries: [WaterEntry] = []
    var addEntryCallCount = 0
    var deleteEntryCallCount = 0
    var updateEntryCallCount = 0
    var saveCallCount = 0
    var shouldThrow = false

    func addEntry(amountMl: Int, date: Date, isFromHealth: Bool, healthSampleId: UUID?) throws -> WaterEntry {
        if shouldThrow { throw GlassWaterError.persistenceFailed(operation: "addEntry", underlying: NSError(domain: "test", code: 0)) }
        addEntryCallCount += 1
        let entry = WaterEntry(date: date, amountMl: amountMl, isFromHealth: isFromHealth, healthSampleId: healthSampleId)
        entries.append(entry)
        return entry
    }

    func entries(from startDate: Date, to endDate: Date) throws -> [WaterEntry] {
        if shouldThrow { throw GlassWaterError.persistenceFailed(operation: "entries", underlying: NSError(domain: "test", code: 0)) }
        return entries.filter { $0.date >= startDate && $0.date < endDate }
    }

    func entriesMissingHealthSample() throws -> [WaterEntry] {
        entries.filter { !$0.isFromHealth && $0.healthSampleId == nil }
    }

    func total(for date: Date) throws -> Int {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return try entries(from: start, to: end).reduce(0) { $0 + $1.amountMl }
    }

    func latestEntry() throws -> WaterEntry? {
        entries.max(by: { $0.date < $1.date })
    }

    func latestTodayEntry(for date: Date) throws -> WaterEntry? {
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        return entries
            .filter { $0.date >= dayStart && $0.date < dayEnd }
            .max(by: { $0.date < $1.date })
    }

    func latestEntryDate() throws -> Date? {
        try latestEntry()?.date
    }

    func updateEntry(_ entry: WaterEntry, amountMl: Int, date: Date, isFromHealth: Bool, healthSampleId: UUID?) throws {
        if shouldThrow { throw GlassWaterError.persistenceFailed(operation: "updateEntry", underlying: NSError(domain: "test", code: 0)) }
        updateEntryCallCount += 1
        entry.amountMl = amountMl
        entry.date = date
        entry.isFromHealth = isFromHealth
        entry.healthSampleId = healthSampleId
    }

    func entryWithHealthSampleId(_ sampleId: UUID) throws -> WaterEntry? {
        entries.first { $0.healthSampleId == sampleId }
    }

    func deleteEntry(_ entry: WaterEntry) throws {
        if shouldThrow { throw GlassWaterError.persistenceFailed(operation: "deleteEntry", underlying: NSError(domain: "test", code: 0)) }
        deleteEntryCallCount += 1
        entries.removeAll { $0.id == entry.id }
    }

    func save() throws {
        if shouldThrow { throw GlassWaterError.persistenceFailed(operation: "save", underlying: NSError(domain: "test", code: 0)) }
        saveCallCount += 1
    }
}

// MARK: - Mock Settings Store

final class MockSettingsStore: SettingsStore {
    var settings = UserSettings()
    var saveCallCount = 0
    var shouldThrow = false

    func loadOrCreate() throws -> UserSettings {
        if shouldThrow { throw GlassWaterError.persistenceFailed(operation: "loadOrCreate", underlying: NSError(domain: "test", code: 0)) }
        return settings
    }

    func save() throws {
        if shouldThrow { throw GlassWaterError.persistenceFailed(operation: "save", underlying: NSError(domain: "test", code: 0)) }
        saveCallCount += 1
    }

    func invalidateCache() {
    }
}

// MARK: - Mock Health Service

final class MockHealthService: HealthKitServicing {
    var status: HealthAccessStatus = .notDetermined
    var savedAmounts: [(Int, Date)] = []
    var deletedSampleIds: [UUID] = []
    var samplesToReturn: [HealthWaterSample] = []
    var dailyIntakeToReturn: [Date: Int] = [:]
    var shouldThrow = false

    func isHealthDataAvailable() -> Bool { true }

    func authorizationStatus() async -> HealthAccessStatus { status }

    var shouldThrowOnAuth = false

    func requestAuthorization() async throws -> HealthAccessStatus {
        if shouldThrowOnAuth { throw GlassWaterError.healthKitSyncFailed(underlying: NSError(domain: "test", code: 0)) }
        return status
    }

    func fetchWaterSamples(from startDate: Date, to endDate: Date) async throws -> [HealthWaterSample] {
        if shouldThrow { throw GlassWaterError.healthKitSyncFailed(underlying: NSError(domain: "test", code: 0)) }
        return samplesToReturn
    }

    func fetchWaterIntake(from startDate: Date, to endDate: Date) async throws -> Int {
        if shouldThrow { throw GlassWaterError.healthKitSyncFailed(underlying: NSError(domain: "test", code: 0)) }
        return samplesToReturn.reduce(0) { $0 + $1.amountMl }
    }

    func fetchDailyIntake(from startDate: Date, to endDate: Date, calendar: Calendar) async throws -> [Date: Int] {
        dailyIntakeToReturn
    }

    func saveWaterIntake(amountMl: Int, date: Date) async throws -> UUID {
        if shouldThrow { throw GlassWaterError.healthKitSyncFailed(underlying: NSError(domain: "test", code: 0)) }
        savedAmounts.append((amountMl, date))
        return UUID()
    }

    func deleteWaterSample(id: UUID) async throws {
        if shouldThrow { throw GlassWaterError.healthKitSyncFailed(underlying: NSError(domain: "test", code: 0)) }
        deletedSampleIds.append(id)
    }

    func startObservingWaterChanges(onUpdate: @escaping () -> Void) async {}
    func stopObservingWaterChanges() async {}
}

// MARK: - Mock Notification Service

final class MockNotificationService: NotificationServicing {
    var updateRemindersCallCount = 0
    var applyIntelligentRulesCallCount = 0

    func requestAuthorization() async -> Bool { true }
    func requestProvisionalAuthorization() async -> Bool { true }
    func authorizationStatus() async -> NotificationAccessStatus { .authorized }

    func updateReminders(
        isEnabled: Bool, currentTotalMl: Int, dailyGoalMl: Int, customAmountMl: Int?,
        reminderStartMinutes: Int, reminderEndMinutes: Int, reminderIntervalMinutes: Int,
        lastEntryDate: Date?, streakCount: Int, date: Date
    ) async {
        updateRemindersCallCount += 1
    }

    func applyIntelligentRules(
        isEnabled: Bool, currentTotalMl: Int, dailyGoalMl: Int,
        reminderStartMinutes: Int, reminderEndMinutes: Int,
        lastEntryDate: Date?, date: Date
    ) async {
        applyIntelligentRulesCallCount += 1
    }

    func clearDeliveredReminders() async {
    }
}

// MARK: - Mock Haptics Service

final class MockHapticsService: HapticsServicing {
    var lightImpactCount = 0
    var mediumImpactCount = 0
    var successCount = 0

    func lightImpact() { lightImpactCount += 1 }
    func mediumImpact() { mediumImpactCount += 1 }
    func success() { successCount += 1 }
}

// MARK: - Mock Live Activity Service

final class MockLiveActivityService: LiveActivityServicing {
    var updateCallCount = 0
    var endCallCount = 0

    func update(
        currentMl: Int, dailyGoalMl: Int, lastIntakeMl: Int?, lastIntakeDate: Date?,
        customAmountMl: Int?, isSensitive: Bool, date: Date
    ) async {
        updateCallCount += 1
    }

    func end() async { endCallCount += 1 }
}

// MARK: - Mock Snapshot Provider

final class MockSnapshotProvider: HydrationSnapshotProviding {
    nonisolated(unsafe) var snapshotCallCount = 0

    nonisolated func snapshot(for date: Date, source: HydrationSnapshotSource) throws -> HydrationSnapshot {
        snapshotCallCount += 1
        return HydrationSnapshot(
            updatedAt: date,
            dayStart: Calendar.autoupdatingCurrent.startOfDay(for: date),
            totalMl: 0, goalMl: 2500, progress: 0, remainingMl: 2500,
            goalReached: false, lastIntakeMl: nil, lastIntakeDate: nil,
            customAmountMl: 250, source: source
        )
    }
}

// MARK: - Mock Broadcaster

final class MockBroadcaster: HydrationUpdateBroadcasting {
    var broadcastCallCount = 0
    var lastSnapshot: HydrationSnapshot?

    func broadcast(snapshot: HydrationSnapshot) async {
        broadcastCallCount += 1
        lastSnapshot = snapshot
    }
}

// MARK: - Mock Crash Reporter

final class MockCrashReporter: CrashReporting {
    var recordedErrors: [Error] = []
    var loggedMessages: [String] = []
    var customValues: [String: Any] = [:]

    func record(error: Error) { recordedErrors.append(error) }
    func log(_ message: String) { loggedMessages.append(message) }
    func setCustomValue(_ value: Any, forKey key: String) { customValues[key] = value }
}

// MARK: - Mock Analytics Service

final class MockAnalyticsService: AnalyticsTracking {
    var loggedEvents: [(name: String, parameters: [String: Any]?)] = []
    var userProperties: [String: String?] = [:]
    var screenViews: [String] = []

    func logEvent(_ name: String, parameters: [String: Any]?) {
        loggedEvents.append((name: name, parameters: parameters))
    }

    func setUserProperty(_ value: String?, forName name: String) {
        userProperties[name] = value
    }

    func logScreenView(screenName: String) {
        screenViews.append(screenName)
    }
}

// MARK: - Mock Phone Connectivity Service

final class MockPhoneConnectivityService: PhoneConnectivityServicing {
    var sendStateCallCount = 0
    var lastSentState: WatchState?
    var sendSettingsCallCount = 0
    var lastSentGoalMl: Int?
    var lastSentCustomAmountMl: Int?
    var onCommandReceived: (@MainActor (WatchCommand, @escaping (WatchState?) -> Void) -> Void)?

    func sendState(_ state: WatchState) {
        sendStateCallCount += 1
        lastSentState = state
    }

    func sendSettings(goalMl: Int, customAmountMl: Int) {
        sendSettingsCallCount += 1
        lastSentGoalMl = goalMl
        lastSentCustomAmountMl = customAmountMl
    }
}

// MARK: - Mock Tip Jar Service

final class MockTipJarService: TipJarServicing {
    var productsToReturn: [Product] = []
    var purchaseResult: TipJarPurchaseResult = .success
    var shouldThrow = false
    var fetchCallCount = 0
    var purchaseCallCount = 0

    func fetchProducts() async throws -> [Product] {
        fetchCallCount += 1
        if shouldThrow { throw NSError(domain: "TipJarTest", code: 0, userInfo: [NSLocalizedDescriptionKey: "Test error"]) }
        return productsToReturn
    }

    func purchase(_ product: Product) async throws -> TipJarPurchaseResult {
        purchaseCallCount += 1
        if shouldThrow { throw NSError(domain: "TipJarTest", code: 0, userInfo: [NSLocalizedDescriptionKey: "Test error"]) }
        return purchaseResult
    }

    func listenForTransactions(onVerified: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task {}
    }
}

// MARK: - Test AppServices Factory

@MainActor
struct TestServicesBuilder {
    let waterStore = MockWaterStore()
    let settingsStore = MockSettingsStore()
    let healthService = MockHealthService()
    let notificationService = MockNotificationService()
    let haptics = MockHapticsService()
    let liveActivity = MockLiveActivityService()
    let snapshotStore = InMemoryHydrationSnapshotStore()
    let snapshotProvider = MockSnapshotProvider()
    let broadcaster = MockBroadcaster()
    let crashReporter = MockCrashReporter()
    let analytics = MockAnalyticsService()
    let phoneConnectivity = MockPhoneConnectivityService()
    let tipJar = MockTipJarService()

    var services: AppServices {
        AppServices(
            waterStore: waterStore,
            settingsStore: settingsStore,
            healthService: healthService,
            notificationService: notificationService,
            haptics: haptics,
            liveActivity: liveActivity,
            hydrationSnapshotStore: snapshotStore,
            hydrationSnapshotProvider: snapshotProvider,
            hydrationBroadcaster: broadcaster,
            phoneConnectivity: phoneConnectivity,
            sounds: PreviewSoundService(),
            crashReporter: crashReporter,
            analytics: analytics,
            tipJar: tipJar
        )
    }
}
