//
//  HistoryViewModelTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import XCTest

@testable import GlassWater

@MainActor
final class HistoryViewModelTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var calendar: Calendar!
    private var vm: HistoryViewModel!

    override func setUp() async throws {
        builder = TestServicesBuilder()
        builder.healthService.status = .notDetermined
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        vm = HistoryViewModel(services: builder.services, calendar: calendar)
    }

    override func tearDown() {
        builder = nil
        calendar = nil
        vm = nil
        super.tearDown()
    }

    private func daysAgo(_ n: Int) -> Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -n, to: today)!.addingTimeInterval(12 * 3600) // noon
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(vm.weeklyPoints.isEmpty)
        XCTAssertTrue(vm.dailySummaries.isEmpty)
        XCTAssertEqual(vm.dailyGoalMl, AppConstants.defaultDailyGoalMl)
        XCTAssertEqual(vm.weeklyTotalMl, 0)
        XCTAssertEqual(vm.currentStreak, 0)
    }

    // MARK: - Load

    func testLoadSetsGoalFromSettings() async {
        builder.settingsStore.settings.dailyGoalMl = 3000
        await vm.load()
        XCTAssertEqual(vm.dailyGoalMl, 3000)
    }

    func testLoadBuildsWeeklyPoints() async {
        // Add entries for the last 3 days
        for i in 0...2 {
            builder.waterStore.entries.append(WaterEntry(date: daysAgo(i), amountMl: 500 + i * 100))
        }
        await vm.load()

        XCTAssertEqual(vm.weeklyPoints.count, 7) // Always 7 days
    }

    func testLoadBuildsDailySummaries() async {
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(0), amountMl: 1000))
        await vm.load()

        XCTAssertEqual(vm.dailySummaries.count, 14) // 14 days of history
    }

    // MARK: - Weekly Insights

    func testWeeklyTotalCalculation() async {
        for i in 0...6 {
            builder.waterStore.entries.append(WaterEntry(date: daysAgo(i), amountMl: 1000))
        }
        await vm.load()

        XCTAssertEqual(vm.weeklyTotalMl, 7000)
    }

    func testWeeklyAverageCalculation() async {
        for i in 0...6 {
            builder.waterStore.entries.append(WaterEntry(date: daysAgo(i), amountMl: 1400))
        }
        await vm.load()

        XCTAssertEqual(vm.weeklyAverageMl, 1400)
    }

    func testGreatWeekInsight() async {
        builder.settingsStore.settings.dailyGoalMl = 1000
        // 5 days meeting goal
        for i in 0...4 {
            builder.waterStore.entries.append(WaterEntry(date: daysAgo(i), amountMl: 1200))
        }
        // 2 days below
        for i in 5...6 {
            builder.waterStore.entries.append(WaterEntry(date: daysAgo(i), amountMl: 500))
        }
        await vm.load()

        XCTAssertEqual(vm.daysMetGoal, 5)
        XCTAssertEqual(vm.weeklyInsight, .greatWeek)
    }

    func testNeedsMoreWaterInsight() async {
        builder.settingsStore.settings.dailyGoalMl = 2500
        // Very low amounts each day
        for i in 0...6 {
            builder.waterStore.entries.append(WaterEntry(date: daysAgo(i), amountMl: 300))
        }
        await vm.load()

        XCTAssertEqual(vm.weeklyInsight, .needsMoreWater)
    }

    func testBestDayCalculation() async {
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(0), amountMl: 500))
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(1), amountMl: 2000))
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(2), amountMl: 800))
        await vm.load()

        XCTAssertNotNil(vm.bestDay)
        XCTAssertEqual(vm.bestDay?.amountMl, 2000)
    }

    // MARK: - Streak

    func testStreakCountsConsecutiveGoalDays() async {
        builder.settingsStore.settings.dailyGoalMl = 1000
        // Yesterday and day before: met goal
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(1), amountMl: 1500))
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(2), amountMl: 1200))
        // 3 days ago: didn't meet
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(3), amountMl: 300))
        await vm.load()

        XCTAssertEqual(vm.currentStreak, 2)
    }

    func testStreakBreaksOnMissedDay() async {
        builder.settingsStore.settings.dailyGoalMl = 1000
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(1), amountMl: 1500))
        // Day 2 missed (no entry)
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(3), amountMl: 1500))
        await vm.load()

        XCTAssertEqual(vm.currentStreak, 1)
    }

    func testStreakIsZeroWithNoGoalMet() async {
        builder.settingsStore.settings.dailyGoalMl = 5000
        builder.waterStore.entries.append(WaterEntry(date: daysAgo(1), amountMl: 100))
        await vm.load()

        XCTAssertEqual(vm.currentStreak, 0)
    }

    // MARK: - Weekly Progress

    func testWeeklyProgress() async {
        builder.settingsStore.settings.dailyGoalMl = 1000
        for i in 0...6 {
            builder.waterStore.entries.append(WaterEntry(date: daysAgo(i), amountMl: 500))
        }
        await vm.load()

        // weeklyGoalMl = 7000, weeklyTotalMl = 3500
        XCTAssertEqual(vm.weeklyProgress, 0.5, accuracy: 0.01)
    }

    // MARK: - Error Handling

    func testLoadWithSettingsErrorRecordsCrash() async {
        builder.settingsStore.shouldThrow = true
        await vm.load()
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }

    // MARK: - Time Patterns

    func testMorningPersonInsight() async {
        // Need: avg >= goal/2 to skip needsMoreWater, variance > 300 to skip consistentHydration,
        // < 5 days met goal to skip greatWeek, no improving trend, morning ratio > 45%
        builder.settingsStore.settings.dailyGoalMl = 1500
        let amounts = [600, 1400, 600, 1400, 600, 1400, 600]
        for i in 0...6 {
            let day = calendar.startOfDay(for: daysAgo(i))
            let morningDate = day.addingTimeInterval(8 * 3600) // 8am
            builder.waterStore.entries.append(WaterEntry(date: morningDate, amountMl: amounts[i]))
        }
        await vm.load()

        // Total=6600, avg=943, goal/2=750 → avg >= 750 ✓ → skips needsMoreWater
        // Variance of [600,1400,...] = 400 > 300 → skips consistentHydration
        // 0 days met goal (max 1400 < 1500) → skips greatWeek
        // All entries at 8am → morningRatio = 100% > 45% → morningPerson
        XCTAssertGreaterThanOrEqual(vm.weeklyAverageMl, builder.settingsStore.settings.dailyGoalMl / 2,
            "Average must be >= goal/2 to avoid needsMoreWater")
        XCTAssertEqual(vm.weeklyInsight, .morningPerson)
    }

    func testEveningPersonInsight() async {
        builder.settingsStore.settings.dailyGoalMl = 1500
        let amounts = [600, 1400, 600, 1400, 600, 1400, 600]
        for i in 0...6 {
            let day = calendar.startOfDay(for: daysAgo(i))
            let eveningDate = day.addingTimeInterval(20 * 3600) // 8pm
            builder.waterStore.entries.append(WaterEntry(date: eveningDate, amountMl: amounts[i]))
        }
        await vm.load()

        XCTAssertGreaterThanOrEqual(vm.weeklyAverageMl, builder.settingsStore.settings.dailyGoalMl / 2,
            "Average must be >= goal/2 to avoid needsMoreWater")
        XCTAssertEqual(vm.weeklyInsight, .eveningPerson)
    }
}
