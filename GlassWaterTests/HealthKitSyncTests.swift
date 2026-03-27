//
//  HealthKitSyncTests.swift
//  GlassWaterTests
//
//  Tests for HealthKit sync deduplication logic in HomeViewModel.
//  The syncHealthEntries method must:
//  - Add new HK samples not in local store
//  - Skip duplicates (by sampleId)
//  - Skip pending entries (matching amount + 5s window)
//  - Remove local entries whose HK sample was deleted
//  - Grace period for recent entries (60s)
//

import XCTest

@testable import GlassWater

@MainActor
final class HealthKitSyncTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var vm: HomeViewModel!
    private var calendar: Calendar!

    override func setUp() async throws {
        builder = TestServicesBuilder()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // HealthKit must be authorized for sync to run
        builder.healthService.status = .authorized
        vm = HomeViewModel(services: builder.services, calendar: calendar)
        vm.isInForeground = true  // Tests simulate foreground behavior
    }

    override func tearDown() {
        builder = nil
        vm = nil
        calendar = nil
        super.tearDown()
    }

    private var todayStart: Date {
        calendar.startOfDay(for: Date.now)
    }

    // MARK: - Add New Samples

    func testSyncAddsNewHealthSamples() async {
        let sampleId = UUID()
        let sampleDate = todayStart.addingTimeInterval(3600)

        builder.healthService.samplesToReturn = [
            HealthWaterSample(id: sampleId, date: sampleDate, amountMl: 300),
        ]

        await vm.load()

        // The sync should have added this as a local entry
        XCTAssertEqual(vm.todayTotalMl, 300)
        let matchingEntry = builder.waterStore.entries.first { $0.healthSampleId == sampleId }
        XCTAssertNotNil(matchingEntry, "HK sample should be added to local store")
        XCTAssertEqual(matchingEntry?.amountMl, 300)
        XCTAssertTrue(matchingEntry?.isFromHealth ?? false)
    }

    // MARK: - Skip Duplicates

    func testSyncSkipsDuplicatesBySampleId() async {
        let sampleId = UUID()
        let sampleDate = todayStart.addingTimeInterval(3600)

        // Already have this sample locally
        builder.waterStore.entries = [
            WaterEntry(date: sampleDate, amountMl: 300, isFromHealth: true, healthSampleId: sampleId),
        ]
        builder.healthService.samplesToReturn = [
            HealthWaterSample(id: sampleId, date: sampleDate, amountMl: 300),
        ]

        await vm.load()

        // Should NOT add a duplicate
        let matchingEntries = builder.waterStore.entries.filter { $0.healthSampleId == sampleId }
        XCTAssertEqual(matchingEntries.count, 1, "Should not duplicate existing HK entry")
        XCTAssertEqual(vm.todayTotalMl, 300)
    }

    // MARK: - Skip Pending Match

    func testSyncSkipsPendingNonHealthMatch() async {
        let sampleId = UUID()
        let sampleDate = todayStart.addingTimeInterval(3600)

        // A non-health entry with matching amount and very close time
        // This simulates: phone saved to HK on behalf of watch, entry exists but isn't marked as HK yet
        builder.waterStore.entries = [
            WaterEntry(date: sampleDate.addingTimeInterval(2), amountMl: 300, isFromHealth: false, healthSampleId: nil),
        ]
        builder.healthService.samplesToReturn = [
            HealthWaterSample(id: sampleId, date: sampleDate, amountMl: 300),
        ]

        await vm.load()

        // The key invariant: total should be 300, not 600 (no duplication)
        XCTAssertEqual(vm.todayTotalMl, 300, "Total should only count 300ml — sync must not duplicate the pending entry")
        // Verify addEntry was NOT called (the sample was skipped due to pending match)
        XCTAssertEqual(builder.waterStore.addEntryCallCount, 0, "Should not call addEntry when matching pending entry exists")
    }

    // MARK: - Remove Deleted Samples

    func testSyncRemovesDeletedHealthSamples() async throws {
        let sampleId = UUID()
        // Entry from well past the 60s grace period (2 hours ago)
        let entryDate = Date.now.addingTimeInterval(-7200)

        // Skip if entryDate falls before today (e.g. test runs near midnight)
        let dayStart = calendar.startOfDay(for: Date.now)
        try XCTSkipIf(entryDate < dayStart, "Entry would fall in yesterday — skipping to avoid flakiness near midnight")

        builder.waterStore.entries = [
            WaterEntry(date: entryDate, amountMl: 300, isFromHealth: true, healthSampleId: sampleId),
        ]
        // HK no longer has this sample
        builder.healthService.samplesToReturn = []

        await vm.load()

        XCTAssertEqual(builder.waterStore.deleteEntryCallCount, 1, "Should remove entry whose HK sample was deleted")
        XCTAssertEqual(vm.todayTotalMl, 0)
    }

    // MARK: - Grace Period

    func testSyncSkipsRecentDeletions() async {
        let sampleId = UUID()
        // Entry from just now (within 60s grace period)
        let entryDate = Date.now.addingTimeInterval(-5)

        builder.waterStore.entries = [
            WaterEntry(date: entryDate, amountMl: 300, isFromHealth: true, healthSampleId: sampleId),
        ]
        // HK doesn't have this sample yet (cross-device sync delay)
        builder.healthService.samplesToReturn = []

        await vm.load()

        // Should NOT remove because entry is within 60s grace period
        XCTAssertEqual(builder.waterStore.deleteEntryCallCount, 0, "Should not remove entry within grace period")
        XCTAssertEqual(vm.todayTotalMl, 300)
    }

    // MARK: - Updates Total

    func testSyncUpdatesTotal() async {
        let sample1 = UUID()
        let sample2 = UUID()

        builder.healthService.samplesToReturn = [
            HealthWaterSample(id: sample1, date: todayStart.addingTimeInterval(3600), amountMl: 200),
            HealthWaterSample(id: sample2, date: todayStart.addingTimeInterval(7200), amountMl: 300),
        ]

        await vm.load()

        XCTAssertEqual(vm.todayTotalMl, 500)
        XCTAssertEqual(vm.todayEntries.count, 2)
    }

    // MARK: - Error Handling

    func testSyncWithHealthKitErrorReportsButDoesNotCrash() async {
        builder.healthService.shouldThrow = true

        await vm.load()

        // Should report error but not crash
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
        XCTAssertEqual(vm.todayTotalMl, 0, "Total should be 0 since sync failed")
    }

    // MARK: - Multiple Syncs Don't Duplicate

    func testMultipleSyncsDoNotDuplicate() async {
        let sampleId = UUID()
        builder.healthService.samplesToReturn = [
            HealthWaterSample(id: sampleId, date: todayStart.addingTimeInterval(3600), amountMl: 300),
        ]

        // First load triggers sync
        await vm.load()
        XCTAssertEqual(vm.todayTotalMl, 300)

        // Simulate refresh (second sync) — the entry is now in local store with sampleId
        vm.refreshFromExternalChange()
        // Wait for debounce (200ms) + processing
        try? await Task.sleep(for: .milliseconds(400))

        // Should still be 300, not 600
        XCTAssertEqual(vm.todayTotalMl, 300, "Second sync should not duplicate the entry")
    }
}
