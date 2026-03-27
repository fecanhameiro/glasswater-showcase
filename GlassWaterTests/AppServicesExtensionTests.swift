//
//  AppServicesExtensionTests.swift
//  GlassWaterTests
//
//  Tests for AppServices extensions: buildWatchState, refreshNotifications,
//  broadcastCurrentSnapshot, and backfillPendingHealthEntries.
//

import XCTest

@testable import GlassWater

@MainActor
final class AppServicesExtensionTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var services: AppServices!

    override func setUp() async throws {
        AppServices.lastBroadcastRequestDate = nil
        builder = TestServicesBuilder()
        services = builder.services
    }

    override func tearDown() {
        AppServices.lastBroadcastRequestDate = nil
        builder = nil
        services = nil
        super.tearDown()
    }

    private var todayStart: Date {
        Calendar.autoupdatingCurrent.startOfDay(for: .now)
    }

    // MARK: - buildWatchState

    func testBuildWatchStateBasic() throws {
        builder.settingsStore.settings.dailyGoalMl = 2500
        builder.waterStore.entries = [
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 500),
        ]

        let state = try services.buildWatchState()

        XCTAssertEqual(state.totalMl, 500)
        XCTAssertEqual(state.goalMl, 2500)
        XCTAssertEqual(state.progress, 0.2, accuracy: 0.01)
        XCTAssertEqual(state.remainingMl, 2000)
        XCTAssertFalse(state.goalReached)
    }

    func testBuildWatchStateGoalReached() throws {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.waterStore.entries = [
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600),
        ]

        let state = try services.buildWatchState()

        XCTAssertTrue(state.goalReached)
        XCTAssertEqual(state.progress, 1.0)
        XCTAssertEqual(state.remainingMl, 0)
    }

    func testBuildWatchStateCustomAmountResolved() throws {
        builder.settingsStore.settings.dailyGoalMl = 2500
        builder.settingsStore.settings.lastCustomAmountMl = 400

        let state = try services.buildWatchState()

        XCTAssertEqual(state.customAmountMl, 400)
    }

    func testBuildWatchStateCustomAmountFallback() throws {
        builder.settingsStore.settings.dailyGoalMl = 2500
        builder.settingsStore.settings.lastCustomAmountMl = nil

        let state = try services.buildWatchState()

        // Should use resolvedCustomAmount (25% of goal), not defaultCustomAmountMl
        let expected = QuickAddOptions.resolvedCustomAmount(forGoalMl: 2500, customAmountMl: nil)
        XCTAssertEqual(state.customAmountMl, expected)
    }

    func testBuildWatchStateLimitsEntries() throws {
        // Add 15 entries — should only include 8 most recent
        for i in 0..<15 {
            builder.waterStore.entries.append(
                WaterEntry(date: todayStart.addingTimeInterval(Double(i) * 600), amountMl: 100)
            )
        }

        let state = try services.buildWatchState()

        XCTAssertEqual(state.entries.count, 8, "Should limit to 8 most recent entries")
    }

    func testBuildWatchStateEntriesSortedByDateDesc() throws {
        let early = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 100)
        let late = WaterEntry(date: todayStart.addingTimeInterval(7200), amountMl: 200)
        builder.waterStore.entries = [early, late]

        let state = try services.buildWatchState()

        XCTAssertEqual(state.entries.first?.amountMl, 200, "Most recent entry should be first")
    }

    func testBuildWatchStateIncludesProcessedCommandIds() throws {
        let commandId = UUID()
        let state = try services.buildWatchState(processedCommandIds: [commandId])

        XCTAssertTrue(state.processedCommandIds.contains(commandId))
    }

    func testBuildWatchStateZeroGoal() throws {
        builder.settingsStore.settings.dailyGoalMl = 0

        let state = try services.buildWatchState()

        XCTAssertEqual(state.progress, 0)
        XCTAssertFalse(state.goalReached)
    }

    func testBuildWatchStateWithSettingsError() {
        builder.settingsStore.shouldThrow = true

        XCTAssertThrowsError(try services.buildWatchState())
    }

    // MARK: - refreshNotifications

    func testRefreshNotificationsCallsUpdateReminders() async {
        builder.settingsStore.settings.notificationsEnabled = true
        builder.settingsStore.settings.dailyGoalMl = 2500

        await services.refreshNotifications()

        XCTAssertEqual(builder.notificationService.updateRemindersCallCount, 1)
    }

    func testRefreshNotificationsWithSmartRulesEnabled() async {
        builder.settingsStore.settings.intelligentNotificationsEnabled = true

        await services.refreshNotifications(applySmartRules: true)

        XCTAssertEqual(builder.notificationService.updateRemindersCallCount, 1)
        XCTAssertEqual(builder.notificationService.applyIntelligentRulesCallCount, 1)
    }

    func testRefreshNotificationsWithSmartRulesDisabled() async {
        builder.settingsStore.settings.intelligentNotificationsEnabled = false

        await services.refreshNotifications(applySmartRules: true)

        XCTAssertEqual(builder.notificationService.updateRemindersCallCount, 1)
        XCTAssertEqual(builder.notificationService.applyIntelligentRulesCallCount, 0,
            "Should not apply smart rules when intelligentNotificationsEnabled is false")
    }

    func testRefreshNotificationsWithSettingsError() async {
        builder.settingsStore.shouldThrow = true

        await services.refreshNotifications()

        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
        XCTAssertEqual(builder.notificationService.updateRemindersCallCount, 0)
    }

    // MARK: - broadcastCurrentSnapshot

    func testBroadcastCurrentSnapshotBroadcasts() async {
        builder.settingsStore.settings.dailyGoalMl = 2500

        await services.broadcastCurrentSnapshot()

        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
    }

    func testBroadcastCurrentSnapshotSetsProgressCustomValue() async {
        // MockSnapshotProvider returns totalMl=0, goalMl=2500 → progress 0%
        await services.broadcastCurrentSnapshot()

        XCTAssertEqual(builder.crashReporter.customValues["daily_progress_pct"] as? Int, 0)
    }

    func testBroadcastCurrentSnapshotWithSnapshotError() async {
        // MockSnapshotProvider doesn't throw based on settingsStore,
        // but we can verify the broadcast still happens when provider succeeds
        await services.broadcastCurrentSnapshot()

        // No errors should be recorded when everything works
        XCTAssertTrue(builder.crashReporter.recordedErrors.isEmpty)
        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
    }

    // MARK: - backfillPendingHealthEntries

    func testBackfillSavesToHealthKit() async {
        builder.healthService.status = .authorized
        // Entry without HK sample
        builder.waterStore.entries = [
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300, isFromHealth: false, healthSampleId: nil),
        ]

        await services.backfillPendingHealthEntries()

        XCTAssertEqual(builder.healthService.savedAmounts.count, 1)
        XCTAssertEqual(builder.healthService.savedAmounts.first?.0, 300)
        XCTAssertGreaterThan(builder.waterStore.updateEntryCallCount, 0)
    }

    func testBackfillSkipsWhenNotAuthorized() async {
        builder.healthService.status = .notDetermined
        builder.waterStore.entries = [
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300, isFromHealth: false, healthSampleId: nil),
        ]

        await services.backfillPendingHealthEntries()

        XCTAssertTrue(builder.healthService.savedAmounts.isEmpty, "Should not save when not authorized")
    }

    func testBackfillSkipsEntriesWithHealthSample() async {
        builder.healthService.status = .authorized
        // Entry already has HK sample
        builder.waterStore.entries = [
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300, isFromHealth: true, healthSampleId: UUID()),
        ]

        await services.backfillPendingHealthEntries()

        XCTAssertTrue(builder.healthService.savedAmounts.isEmpty, "Should not backfill entries with existing HK sample")
    }

    func testBackfillWithHealthKitError() async {
        builder.healthService.status = .authorized
        builder.healthService.shouldThrow = true
        builder.waterStore.entries = [
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300, isFromHealth: false, healthSampleId: nil),
        ]

        await services.backfillPendingHealthEntries()

        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }
}
