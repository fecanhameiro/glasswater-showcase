//
//  DayRolloverTests.swift
//  GlassWaterTests
//
//  Tests for day boundary (midnight reset) logic across multiple components.
//  Day rollover is the #1 bug-prone area — these tests ensure entries from
//  the previous day are never included in today's totals.
//

import XCTest

@testable import GlassWater

@MainActor
final class DayRolloverTests: XCTestCase {
    private var waterStore: MockWaterStore!
    private var settingsStore: MockSettingsStore!
    private var calendar: Calendar!
    // Auxiliary properties to prevent @MainActor dealloc crash on local variables
    private var provider: HydrationSnapshotProvider?
    private var testVm: HomeViewModel?
    private var testBuilder: TestServicesBuilder?

    override func setUp() async throws {
        waterStore = MockWaterStore()
        settingsStore = MockSettingsStore()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        LiveActivityState.clear()
        provider = nil
        testVm = nil
        testBuilder = nil
        waterStore = nil
        settingsStore = nil
        calendar = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Returns a fixed date for "today at midnight" and "yesterday at midnight" in UTC.
    private func dayBoundaries() -> (yesterdayStart: Date, todayStart: Date) {
        let todayStart = calendar.startOfDay(for: Date.now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        return (yesterdayStart, todayStart)
    }

    // MARK: - Snapshot Provider Day Boundary

    func testSnapshotProviderExcludesYesterdayEntries() throws {
        let (yesterdayStart, todayStart) = dayBoundaries()
        settingsStore.settings.dailyGoalMl = 2500

        waterStore.entries = [
            WaterEntry(date: yesterdayStart.addingTimeInterval(12 * 3600), amountMl: 1000),
            WaterEntry(date: yesterdayStart.addingTimeInterval(23 * 3600 + 59 * 60 + 59), amountMl: 700),
            WaterEntry(date: todayStart.addingTimeInterval(1), amountMl: 300),
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 200),
        ]

        provider = HydrationSnapshotProvider(
            waterStore: waterStore, settingsStore: settingsStore, calendar: calendar
        )
        let now = todayStart.addingTimeInterval(10 * 3600)
        let snapshot = try provider!.snapshot(for: now, source: .app)

        // 300 + 200 = 500. Yesterday entries (1000, 700) must be excluded.
        // Using 700 (not 500) for yesterday to avoid coincidental match with today's total.
        XCTAssertEqual(snapshot.totalMl, 500, "Only today's entries (300 + 200) should be counted")
        XCTAssertEqual(snapshot.dayStart, todayStart)
    }

    func testSnapshotDayStartIsAlwaysStartOfDay() throws {
        settingsStore.settings.dailyGoalMl = 2500

        // Query at 15:30 should still use midnight as dayStart
        let todayStart = calendar.startOfDay(for: Date.now)
        let queryTime = todayStart.addingTimeInterval(15 * 3600 + 30 * 60)

        provider = HydrationSnapshotProvider(
            waterStore: waterStore, settingsStore: settingsStore, calendar: calendar
        )
        let snapshot = try provider!.snapshot(for: queryTime, source: .app)

        XCTAssertEqual(snapshot.dayStart, todayStart)
    }

    // MARK: - MockWaterStore Day-Scoped Queries

    func testLatestTodayEntryReturnsNilForYesterdayOnly() throws {
        let (yesterdayStart, _) = dayBoundaries()

        waterStore.entries = [
            WaterEntry(date: yesterdayStart.addingTimeInterval(3600), amountMl: 500),
        ]

        let result = try waterStore.latestTodayEntry(for: Date.now)
        XCTAssertNil(result, "latestTodayEntry should return nil when only yesterday's entries exist")
    }

    func testLatestEntryReturnsAcrossDays() throws {
        let (yesterdayStart, _) = dayBoundaries()

        waterStore.entries = [
            WaterEntry(date: yesterdayStart.addingTimeInterval(3600), amountMl: 500),
        ]

        let result = try waterStore.latestEntry()
        XCTAssertNotNil(result, "latestEntry (all-time) should return yesterday's entry")
        XCTAssertEqual(result?.amountMl, 500)
    }

    func testLatestTodayEntryReturnsTodaysMostRecent() throws {
        let (_, todayStart) = dayBoundaries()
        let early = todayStart.addingTimeInterval(3600)
        let late = todayStart.addingTimeInterval(7200)

        waterStore.entries = [
            WaterEntry(date: early, amountMl: 200),
            WaterEntry(date: late, amountMl: 400),
        ]

        let result = try waterStore.latestTodayEntry(for: Date.now)
        XCTAssertEqual(result?.amountMl, 400)
        XCTAssertEqual(result?.date, late)
    }

    func testTotalForDateOnlyCountsThatDay() throws {
        let (yesterdayStart, todayStart) = dayBoundaries()

        waterStore.entries = [
            WaterEntry(date: yesterdayStart.addingTimeInterval(3600), amountMl: 1000),
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300),
            WaterEntry(date: todayStart.addingTimeInterval(7200), amountMl: 200),
        ]

        let todayTotal = try waterStore.total(for: Date.now)
        XCTAssertEqual(todayTotal, 500)
    }

    // MARK: - ContentState Factory After Rollover

    #if os(iOS)
    func testContentStateFactoryZeroAfterRollover() {
        // Simulate new day: 0ml consumed
        let state = LiveActivityContentStateFactory.make(
            currentMl: 0, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: 300
        )

        XCTAssertEqual(state.progress, 0)
        XCTAssertEqual(state.currentMl, 0)
        XCTAssertEqual(state.remainingMl, 2500)
        XCTAssertFalse(state.goalReached)
    }
    #endif

    // MARK: - HomeViewModel Day Isolation

    func testHomeViewModelLoadExcludesYesterdayEntries() async {
        let (yesterdayStart, todayStart) = dayBoundaries()
        testBuilder = TestServicesBuilder()
        testBuilder!.healthService.status = .notDetermined

        testBuilder!.waterStore.entries = [
            WaterEntry(date: yesterdayStart.addingTimeInterval(3600), amountMl: 1000),
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300),
        ]

        testVm = HomeViewModel(services: testBuilder!.services, calendar: calendar)
        testVm!.isInForeground = true
        await testVm!.load()

        XCTAssertEqual(testVm!.todayTotalMl, 300, "HomeViewModel should only include today's entries")
        XCTAssertEqual(testVm!.todayEntries.count, 1)
    }

    // MARK: - Timezone Edge Case

    func testDayBoundaryRespectTimezone() throws {
        settingsStore.settings.dailyGoalMl = 2500

        // Use a different timezone (UTC+5)
        var tzCalendar = Calendar(identifier: .gregorian)
        tzCalendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!

        provider = HydrationSnapshotProvider(
            waterStore: waterStore, settingsStore: settingsStore, calendar: tzCalendar
        )

        let now = Date.now
        let dayStart = tzCalendar.startOfDay(for: now)

        // Entry at dayStart + 1s (today in UTC+5)
        waterStore.entries = [
            WaterEntry(date: dayStart.addingTimeInterval(1), amountMl: 400),
        ]

        let snapshot = try provider!.snapshot(for: now, source: .app)
        XCTAssertEqual(snapshot.totalMl, 400)
        XCTAssertEqual(snapshot.dayStart, dayStart)
    }

    // MARK: - LiveActivityState Day Boundary

    func testLiveActivityStateDismissedClearedOnDayChange() {
        let cal = Calendar.autoupdatingCurrent
        var state = LiveActivityState.idle(calendar: cal)
        state.transition(to: .dismissed, now: .now, calendar: cal)
        XCTAssertTrue(state.goalCelebratedToday)

        // Simulate "yesterday" by creating state with yesterday's dayStart
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))!
        let oldState = LiveActivityState(phase: .dismissed, date: yesterday, dayStart: yesterday)
        XCTAssertFalse(oldState.isToday(calendar: cal),
                       "Dismissal from yesterday should not carry over to today")
    }

    func testMidnightDoesNotCarryOverDismissalFromYesterday() {
        let cal = Calendar.autoupdatingCurrent
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))!
        let oldState = LiveActivityState(phase: .dismissed, date: yesterday, dayStart: yesterday)
        oldState.save()

        let loaded = LiveActivityState.load()
        XCTAssertFalse(loaded?.isToday(calendar: cal) ?? true)
        XCTAssertFalse((loaded?.goalCelebratedToday ?? false) && (loaded?.isToday(calendar: cal) ?? false))
        LiveActivityState.clear()
    }
}
