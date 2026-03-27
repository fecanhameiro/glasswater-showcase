//
//  HistoryViewModelCRUDTests.swift
//  GlassWaterTests
//
//  Tests for HistoryViewModel delete/update entry operations and
//  their side effects (HK sync, broadcast, recalculation).
//

import XCTest

@testable import GlassWater

@MainActor
final class HistoryViewModelCRUDTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var calendar: Calendar!
    private var vm: HistoryViewModel!

    override func setUp() async throws {
        AppServices.lastBroadcastRequestDate = nil
        builder = TestServicesBuilder()
        builder.healthService.status = .notDetermined
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        vm = HistoryViewModel(services: builder.services, calendar: calendar)
    }

    override func tearDown() {
        AppServices.lastBroadcastRequestDate = nil
        builder = nil
        calendar = nil
        vm = nil
        super.tearDown()
    }

    private var todayStart: Date {
        calendar.startOfDay(for: Date.now)
    }

    // MARK: - Delete Entry

    func testDeleteEntryRemovesFromStore() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300)
        builder.waterStore.entries = [entry]
        await vm.load()

        await vm.deleteEntry(entry)

        XCTAssertEqual(builder.waterStore.deleteEntryCallCount, 1)
        XCTAssertTrue(builder.waterStore.entries.isEmpty)
    }

    func testDeleteEntryDeletesHealthKitSample() async {
        let sampleId = UUID()
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300,
                               isFromHealth: true, healthSampleId: sampleId)
        builder.waterStore.entries = [entry]
        builder.healthService.status = .authorized
        await vm.load()

        await vm.deleteEntry(entry)

        XCTAssertEqual(builder.healthService.deletedSampleIds, [sampleId])
    }

    func testDeleteEntryBroadcastsSnapshot() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300)
        builder.waterStore.entries = [entry]
        await vm.load()
        builder.broadcaster.broadcastCallCount = 0

        await vm.deleteEntry(entry)

        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
    }

    func testDeleteEntryRecalculatesInsights() async {
        builder.settingsStore.settings.dailyGoalMl = 1000
        let entry1 = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        let entry2 = WaterEntry(date: todayStart.addingTimeInterval(7200), amountMl: 500)
        builder.waterStore.entries = [entry1, entry2]
        await vm.load()

        let totalBefore = vm.weeklyTotalMl
        await vm.deleteEntry(entry1)

        XCTAssertLessThan(vm.weeklyTotalMl, totalBefore, "Weekly total should decrease after deletion")
    }

    func testDeleteEntryWithPersistenceError() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300)
        builder.waterStore.entries = [entry]
        await vm.load()
        builder.waterStore.shouldThrow = true

        await vm.deleteEntry(entry)

        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }

    // MARK: - Update Entry

    func testUpdateEntryChangesAmount() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 200)
        builder.waterStore.entries = [entry]
        await vm.load()

        await vm.updateEntry(entry, amountMl: 500, date: entry.date)

        XCTAssertEqual(entry.amountMl, 500)
        XCTAssertGreaterThan(builder.waterStore.updateEntryCallCount, 0)
    }

    func testUpdateEntryCreatesNewHealthSample() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 200)
        builder.waterStore.entries = [entry]
        builder.healthService.status = .authorized
        await vm.load()

        await vm.updateEntry(entry, amountMl: 500, date: entry.date)

        XCTAssertEqual(builder.healthService.savedAmounts.count, 1)
        XCTAssertEqual(builder.healthService.savedAmounts.first?.0, 500)
    }

    func testUpdateEntryDeletesOldHealthSample() async {
        let oldSampleId = UUID()
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 200,
                               isFromHealth: true, healthSampleId: oldSampleId)
        builder.waterStore.entries = [entry]
        builder.healthService.status = .authorized
        await vm.load()

        await vm.updateEntry(entry, amountMl: 500, date: entry.date)

        XCTAssertTrue(builder.healthService.deletedSampleIds.contains(oldSampleId),
            "Should delete old HK sample when updating")
    }

    func testUpdateEntryBroadcasts() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 200)
        builder.waterStore.entries = [entry]
        await vm.load()
        builder.broadcaster.broadcastCallCount = 0

        await vm.updateEntry(entry, amountMl: 500, date: entry.date)

        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
    }

    // MARK: - Notification Type

    func testDeletePostsHistoryNotification() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300)
        builder.waterStore.entries = [entry]
        await vm.load()

        let expectation = XCTNSNotificationExpectation(
            name: .hydrationDidChangeFromHistory,
            object: nil
        )
        await vm.deleteEntry(entry)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testUpdatePostsHistoryNotification() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 200)
        builder.waterStore.entries = [entry]
        await vm.load()

        let expectation = XCTNSNotificationExpectation(
            name: .hydrationDidChangeFromHistory,
            object: nil
        )
        await vm.updateEntry(entry, amountMl: 500, date: entry.date)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testDeletePostsHistoryNotificationNotExternal() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300)
        builder.waterStore.entries = [entry]
        await vm.load()

        // History delete should post .hydrationDidChangeFromHistory
        let historyExpectation = XCTNSNotificationExpectation(
            name: .hydrationDidChangeFromHistory,
            object: nil
        )

        await vm.deleteEntry(entry)

        await fulfillment(of: [historyExpectation], timeout: 1.0)
    }

    // MARK: - Weekly Insights Recalculation

    func testWeeklyInsightsRecalculateAfterDelete() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        // 5 days meeting goal → greatWeek
        for i in 0...4 {
            let day = calendar.date(byAdding: .day, value: -i, to: todayStart)!
            builder.waterStore.entries.append(
                WaterEntry(date: day.addingTimeInterval(12 * 3600), amountMl: 600)
            )
        }
        await vm.load()
        XCTAssertEqual(vm.daysMetGoal, 5)
        XCTAssertEqual(vm.weeklyInsight, .greatWeek)

        // Delete one → 4 days meeting goal → no longer greatWeek
        let entryToDelete = builder.waterStore.entries.first!
        await vm.deleteEntry(entryToDelete)

        XCTAssertLessThan(vm.daysMetGoal, 5)
        XCTAssertNotEqual(vm.weeklyInsight, .greatWeek)
    }
}
