//
//  HydrationSnapshotProviderTests.swift
//  GlassWaterTests
//
//  Tests for HydrationSnapshotProvider — the "brain" that computes
//  progress, remaining, goal-reached for ALL surfaces (app, widget, LA, watch).
//

import XCTest

@testable import GlassWater

@MainActor
final class HydrationSnapshotProviderTests: XCTestCase {
    private var waterStore: MockWaterStore!
    private var settingsStore: MockSettingsStore!
    private var calendar: Calendar!
    private var provider: HydrationSnapshotProvider!

    override func setUp() async throws {
        waterStore = MockWaterStore()
        settingsStore = MockSettingsStore()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        provider = HydrationSnapshotProvider(
            waterStore: waterStore,
            settingsStore: settingsStore,
            calendar: calendar
        )
    }

    // MARK: - Basic Snapshot

    func testSnapshotWithNoEntries() throws {
        settingsStore.settings.dailyGoalMl = 2500

        let snapshot = try provider.snapshot(for: Date.now, source: .app)

        XCTAssertEqual(snapshot.totalMl, 0)
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertEqual(snapshot.remainingMl, 2500)
        XCTAssertFalse(snapshot.goalReached)
        XCTAssertNil(snapshot.lastIntakeMl)
        XCTAssertNil(snapshot.lastIntakeDate)
    }

    func testSnapshotWithEntries() throws {
        settingsStore.settings.dailyGoalMl = 2000
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        waterStore.entries = [
            WaterEntry(date: dayStart.addingTimeInterval(3600), amountMl: 300),
            WaterEntry(date: dayStart.addingTimeInterval(7200), amountMl: 500),
        ]

        let snapshot = try provider.snapshot(for: now, source: .app)

        XCTAssertEqual(snapshot.totalMl, 800)
        XCTAssertEqual(snapshot.progress, 0.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.remainingMl, 1200)
        XCTAssertFalse(snapshot.goalReached)
    }

    func testSnapshotGoalReached() throws {
        settingsStore.settings.dailyGoalMl = 500
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        waterStore.entries = [
            WaterEntry(date: dayStart.addingTimeInterval(3600), amountMl: 600),
        ]

        let snapshot = try provider.snapshot(for: now, source: .app)

        XCTAssertTrue(snapshot.goalReached)
        XCTAssertEqual(snapshot.remainingMl, 0)
    }

    func testSnapshotGoalReachedExactly() throws {
        settingsStore.settings.dailyGoalMl = 500
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        waterStore.entries = [
            WaterEntry(date: dayStart.addingTimeInterval(3600), amountMl: 500),
        ]

        let snapshot = try provider.snapshot(for: now, source: .app)

        XCTAssertTrue(snapshot.goalReached)
        XCTAssertEqual(snapshot.progress, 1.0)
        XCTAssertEqual(snapshot.remainingMl, 0)
    }

    // MARK: - Clamping & Edge Cases

    func testProgressCapsAtOne() throws {
        settingsStore.settings.dailyGoalMl = 1000
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        waterStore.entries = [
            WaterEntry(date: dayStart.addingTimeInterval(3600), amountMl: 3000),
        ]

        let snapshot = try provider.snapshot(for: now, source: .app)

        XCTAssertEqual(snapshot.progress, 1.0, "Progress must never exceed 1.0")
        XCTAssertEqual(snapshot.totalMl, 3000, "totalMl should reflect actual intake")
    }

    func testRemainingNeverNegative() throws {
        settingsStore.settings.dailyGoalMl = 1000
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        waterStore.entries = [
            WaterEntry(date: dayStart.addingTimeInterval(3600), amountMl: 2000),
        ]

        let snapshot = try provider.snapshot(for: now, source: .app)

        XCTAssertEqual(snapshot.remainingMl, 0, "remainingMl must never be negative")
    }

    func testZeroGoal() throws {
        settingsStore.settings.dailyGoalMl = 0
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        waterStore.entries = [
            WaterEntry(date: dayStart.addingTimeInterval(3600), amountMl: 500),
        ]

        let snapshot = try provider.snapshot(for: now, source: .app)

        XCTAssertEqual(snapshot.progress, 0, "progress should be 0 when goal is 0 (no divide by zero)")
        XCTAssertFalse(snapshot.goalReached, "goalReached should be false when goal is 0")
    }

    // MARK: - Custom Amount

    func testCustomAmountFromSettings() throws {
        settingsStore.settings.dailyGoalMl = 2500
        settingsStore.settings.lastCustomAmountMl = 350

        let snapshot = try provider.snapshot(for: Date.now, source: .app)

        XCTAssertEqual(snapshot.customAmountMl, 350)
    }

    func testCustomAmountFallbackWhenNil() throws {
        settingsStore.settings.dailyGoalMl = 2500
        settingsStore.settings.lastCustomAmountMl = nil

        let snapshot = try provider.snapshot(for: Date.now, source: .app)

        // Should use QuickAddOptions.resolvedCustomAmount fallback (25% of goal)
        let expected = QuickAddOptions.resolvedCustomAmount(forGoalMl: 2500, customAmountMl: nil)
        XCTAssertEqual(snapshot.customAmountMl, expected)
    }

    func testCustomAmountClampedTooLow() throws {
        settingsStore.settings.dailyGoalMl = 2500
        settingsStore.settings.lastCustomAmountMl = 10

        let snapshot = try provider.snapshot(for: Date.now, source: .app)

        XCTAssertGreaterThanOrEqual(snapshot.customAmountMl, AppConstants.customAmountMinMl)
    }

    func testCustomAmountClampedTooHigh() throws {
        settingsStore.settings.dailyGoalMl = 2500
        settingsStore.settings.lastCustomAmountMl = 9999

        let snapshot = try provider.snapshot(for: Date.now, source: .app)

        XCTAssertLessThanOrEqual(snapshot.customAmountMl, AppConstants.customAmountMaxMl)
    }

    // MARK: - Last Entry Fields

    func testLastEntryFields() throws {
        settingsStore.settings.dailyGoalMl = 2500
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        let earlierDate = dayStart.addingTimeInterval(3600)
        let laterDate = dayStart.addingTimeInterval(7200)
        waterStore.entries = [
            WaterEntry(date: earlierDate, amountMl: 200),
            WaterEntry(date: laterDate, amountMl: 400),
        ]

        let snapshot = try provider.snapshot(for: now, source: .app)

        XCTAssertEqual(snapshot.lastIntakeMl, 400, "Should return the most recent entry's amount")
        XCTAssertEqual(snapshot.lastIntakeDate, laterDate, "Should return the most recent entry's date")
    }

    // MARK: - Source Passthrough

    func testSourcePassthrough() throws {
        for source in HydrationSnapshotSource.allCases {
            let snapshot = try provider.snapshot(for: Date.now, source: source)
            XCTAssertEqual(snapshot.source, source)
        }
    }

    // MARK: - Day Boundary

    func testDayBoundaryExcludesYesterdayEntries() throws {
        settingsStore.settings.dailyGoalMl = 2500

        // Create a fixed "now" at 10:00 UTC today
        let todayStart = calendar.startOfDay(for: Date.now)
        let now = todayStart.addingTimeInterval(10 * 3600)

        // Yesterday entry at 23:59:59
        let yesterdayEnd = todayStart.addingTimeInterval(-1)
        // Today entry at 00:00:01
        let todayEarly = todayStart.addingTimeInterval(1)

        waterStore.entries = [
            WaterEntry(date: yesterdayEnd, amountMl: 500),
            WaterEntry(date: todayEarly, amountMl: 300),
        ]

        let snapshot = try provider.snapshot(for: now, source: .app)

        XCTAssertEqual(snapshot.totalMl, 300, "Yesterday's entries must be excluded")
        XCTAssertEqual(snapshot.dayStart, todayStart)
    }

    // MARK: - Error Handling

    func testSnapshotThrowsWhenSettingsStoreThrows() {
        settingsStore.shouldThrow = true
        XCTAssertThrowsError(try provider.snapshot(for: Date.now, source: .app))
    }

    func testSnapshotThrowsWhenWaterStoreThrows() {
        waterStore.shouldThrow = true
        XCTAssertThrowsError(try provider.snapshot(for: Date.now, source: .app))
    }
}
