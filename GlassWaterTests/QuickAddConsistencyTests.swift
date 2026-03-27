//
//  QuickAddConsistencyTests.swift
//  GlassWaterTests
//
//  Tests for cross-surface consistency of quick-add buttons.
//  All surfaces must compute the same amounts for the same inputs.
//

import XCTest

@testable import GlassWater

@MainActor
final class QuickAddConsistencyTests: XCTestCase {

    // MARK: - Clamp Idempotency

    func testClampRoundTrip() {
        // clamp(clamp(x)) must equal clamp(x) for all valid inputs
        for amount in stride(from: 0, through: 2000, by: 10) {
            let once = QuickAddOptions.clampCustomAmount(amount)
            let twice = QuickAddOptions.clampCustomAmount(once)
            XCTAssertEqual(once, twice, "Clamping must be idempotent for amount=\(amount)")
        }
    }

    // MARK: - Resolved Custom Amount Consistency

    func testResolvedCustomAmountConsistencyAcrossGoals() {
        let customAmounts: [Int?] = [nil, 50, 250, 500, 1000, 1500]
        let goals = [1000, 1500, 2000, 2500, 3000, 5000]

        for goal in goals {
            for custom in customAmounts {
                let resolved = QuickAddOptions.resolvedCustomAmount(forGoalMl: goal, customAmountMl: custom)

                XCTAssertGreaterThanOrEqual(resolved, AppConstants.customAmountMinMl,
                    "Resolved custom amount must be >= min for goal=\(goal), custom=\(String(describing: custom))")
                XCTAssertLessThanOrEqual(resolved, AppConstants.customAmountMaxMl,
                    "Resolved custom amount must be <= max for goal=\(goal), custom=\(String(describing: custom))")
            }
        }
    }

    // MARK: - All Percent Amounts Above Minimum

    func testAllPercentAmountsAboveMinimum() {
        let goals = [1000, 1500, 2000, 2500, 3000, 5000]

        for goal in goals {
            let options = QuickAddOptions.options(forGoalMl: goal)
            for option in options {
                XCTAssertGreaterThanOrEqual(option.amountMl, AppConstants.quickAddMinMl,
                    "Percent \(option.percent)% of goal=\(goal) must be >= \(AppConstants.quickAddMinMl)ml, got \(option.amountMl)ml")
            }
        }
    }

    func testAllPercentAmountsBelowMaximum() {
        let goals = [1000, 1500, 2000, 2500, 3000, 5000]

        for goal in goals {
            let options = QuickAddOptions.options(forGoalMl: goal)
            for option in options {
                XCTAssertLessThanOrEqual(option.amountMl, AppConstants.quickAddMaxMl,
                    "Percent \(option.percent)% of goal=\(goal) must be <= \(AppConstants.quickAddMaxMl)ml")
            }
        }
    }

    // MARK: - Live Activity Options Consistency

    func testLiveActivityOptionsMatchExpected() {
        let goal = 2500
        let customAmount = 350

        let laOptions = QuickAddOptions.liveActivityOptions(forGoalMl: goal, customAmountMl: customAmount)
        let quickAmount = QuickAddOptions.amount(forPercent: 10, goalMl: goal)
        let resolvedCustom = QuickAddOptions.resolvedCustomAmount(forGoalMl: goal, customAmountMl: customAmount)

        XCTAssertEqual(laOptions.first?.amountMl, quickAmount)
        if quickAmount != resolvedCustom {
            XCTAssertEqual(laOptions.count, 2)
            XCTAssertEqual(laOptions.last?.amountMl, resolvedCustom)
        }
    }

    func testLiveActivityOptionsDedupWhenSameAmount() {
        // When custom amount equals quick-add amount, should only have 1 button
        let goal = 2500
        let quickAmount = QuickAddOptions.amount(forPercent: 10, goalMl: goal)

        let laOptions = QuickAddOptions.liveActivityOptions(forGoalMl: goal, customAmountMl: quickAmount)

        XCTAssertEqual(laOptions.count, 1, "Should deduplicate when custom == quick-add")
    }

    // MARK: - Snapshot ↔ Content State Factory Consistency

    #if os(iOS)
    @MainActor
    func testSnapshotAndContentStateProgressMatch() throws {
        let waterStore = MockWaterStore()
        let settingsStore = MockSettingsStore()
        settingsStore.settings.dailyGoalMl = 2500
        settingsStore.settings.lastCustomAmountMl = 350

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = calendar.startOfDay(for: Date.now)

        waterStore.entries = [
            WaterEntry(date: dayStart.addingTimeInterval(3600), amountMl: 1250),
        ]

        // Build snapshot directly to avoid HydrationSnapshotProvider @MainActor dealloc crash in test teardown
        let entries = try waterStore.entries(from: dayStart, to: calendar.date(byAdding: .day, value: 1, to: dayStart)!)
        let totalMl = entries.reduce(0) { $0 + $1.amountMl }
        let goalMl = settingsStore.settings.dailyGoalMl
        let snapshot = HydrationSnapshot(
            updatedAt: dayStart.addingTimeInterval(10 * 3600),
            dayStart: dayStart,
            totalMl: totalMl,
            goalMl: goalMl,
            progress: goalMl > 0 ? min(Double(totalMl) / Double(goalMl), 1) : 0,
            remainingMl: max(goalMl - totalMl, 0),
            goalReached: totalMl >= goalMl,
            lastIntakeMl: entries.last?.amountMl,
            lastIntakeDate: entries.last?.date,
            customAmountMl: settingsStore.settings.lastCustomAmountMl ?? QuickAddOptions.resolvedCustomAmount(forGoalMl: goalMl, customAmountMl: nil),
            source: .app
        )

        let contentState = LiveActivityContentStateFactory.make(
            currentMl: snapshot.totalMl,
            dailyGoalMl: snapshot.goalMl,
            lastIntakeMl: snapshot.lastIntakeMl,
            lastIntakeDate: snapshot.lastIntakeDate,
            isSensitive: false,
            customAmountMl: snapshot.customAmountMl
        )

        XCTAssertEqual(snapshot.progress, contentState.progress, accuracy: 0.001,
            "Snapshot and ContentState must compute the same progress")
        XCTAssertEqual(snapshot.remainingMl, contentState.remainingMl)
        XCTAssertEqual(snapshot.goalReached, contentState.goalReached)
        XCTAssertEqual(snapshot.customAmountMl, contentState.customAmountMl)
    }
    #endif

    // MARK: - Cross-Surface Custom Amount Consistency

    @MainActor
    func testAllSurfacesAgreeOnNilCustomAmount() throws {
        let goal = 2500

        // HomeViewModel path (via resolvedCustomAmount)
        let homeAmount = QuickAddOptions.resolvedCustomAmount(forGoalMl: goal, customAmountMl: nil)

        // HydrationSnapshotProvider path (same call after fix)
        let waterStore = MockWaterStore()
        let settingsStore = MockSettingsStore()
        settingsStore.settings.dailyGoalMl = goal
        settingsStore.settings.lastCustomAmountMl = nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let provider = HydrationSnapshotProvider(
            waterStore: waterStore, settingsStore: settingsStore, calendar: calendar
        )
        let snapshot = try provider.snapshot(for: Date.now, source: .app)

        // WatchState path (via buildWatchState → resolvedCustomAmount)
        let builder = TestServicesBuilder()
        builder.settingsStore.settings.dailyGoalMl = goal
        builder.settingsStore.settings.lastCustomAmountMl = nil
        let watchState = try builder.services.buildWatchState()

        #if os(iOS)
        // LiveActivityContentStateFactory path
        let contentState = LiveActivityContentStateFactory.make(
            currentMl: 0, dailyGoalMl: goal,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertEqual(contentState.customAmountMl, homeAmount,
            "LA ContentState must match HomeViewModel custom amount when nil")
        #endif

        XCTAssertEqual(snapshot.customAmountMl, homeAmount,
            "Snapshot must match HomeViewModel custom amount when nil")
        XCTAssertEqual(watchState.customAmountMl, homeAmount,
            "WatchState must match HomeViewModel custom amount when nil")
    }

    @MainActor
    func testAllSurfacesAgreeOnSetCustomAmount() throws {
        let goal = 2500
        let customAmount = 350

        let waterStore = MockWaterStore()
        let settingsStore = MockSettingsStore()
        settingsStore.settings.dailyGoalMl = goal
        settingsStore.settings.lastCustomAmountMl = customAmount
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let provider = HydrationSnapshotProvider(
            waterStore: waterStore, settingsStore: settingsStore, calendar: calendar
        )
        let snapshot = try provider.snapshot(for: Date.now, source: .app)

        let builder = TestServicesBuilder()
        builder.settingsStore.settings.dailyGoalMl = goal
        builder.settingsStore.settings.lastCustomAmountMl = customAmount
        let watchState = try builder.services.buildWatchState()

        #if os(iOS)
        let contentState = LiveActivityContentStateFactory.make(
            currentMl: 0, dailyGoalMl: goal,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: customAmount
        )
        XCTAssertEqual(contentState.customAmountMl, 350)
        #endif

        XCTAssertEqual(snapshot.customAmountMl, 350)
        XCTAssertEqual(watchState.customAmountMl, 350)
    }
}
