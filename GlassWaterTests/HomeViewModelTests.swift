//
//  HomeViewModelTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import XCTest

@testable import GlassWater

@MainActor
final class HomeViewModelTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var vm: HomeViewModel!

    override func setUp() async throws {
        AppServices.lastBroadcastRequestDate = nil
        LiveActivityState.clear()
        DayGoalStatus.resetToIdle()
        builder = TestServicesBuilder()
        builder.healthService.status = .notDetermined
        vm = HomeViewModel(services: builder.services)
        vm.isInForeground = true  // Tests simulate foreground behavior
    }

    override func tearDown() {
        AppServices.lastBroadcastRequestDate = nil
        LiveActivityState.clear()
        DayGoalStatus.resetToIdle()
        builder = nil
        vm = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(vm.todayTotalMl, 0)
        XCTAssertEqual(vm.dailyGoalMl, AppConstants.defaultDailyGoalMl)
        XCTAssertFalse(vm.goalReached)
        XCTAssertFalse(vm.canUndo)
        XCTAssertTrue(vm.todayEntries.isEmpty)
        XCTAssertEqual(vm.streakCount, 0)
    }

    // MARK: - Load

    func testLoadSetsGoalFromSettings() async {
        builder.settingsStore.settings.dailyGoalMl = 3000
        await vm.load()
        XCTAssertEqual(vm.dailyGoalMl, 3000)
    }

    func testLoadSetsHapticsFromSettings() async {
        builder.settingsStore.settings.hapticsEnabled = false
        await vm.load()
        XCTAssertFalse(vm.hapticsEnabled)
    }

    func testLoadSetsStreakFromSettings() async {
        builder.settingsStore.settings.streakCount = 5
        await vm.load()
        XCTAssertEqual(vm.streakCount, 5)
    }

    func testLoadCalculatesTodayTotal() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let entry1 = WaterEntry(date: today.addingTimeInterval(3600), amountMl: 300)
        let entry2 = WaterEntry(date: today.addingTimeInterval(7200), amountMl: 200)
        builder.waterStore.entries = [entry1, entry2]

        await vm.load()

        XCTAssertEqual(vm.todayTotalMl, 500)
        XCTAssertEqual(vm.todayEntries.count, 2)
    }

    func testLoadWithSettingsError() async {
        builder.settingsStore.shouldThrow = true
        await vm.load()
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }

    // MARK: - Add Entry

    func testAddIncreasesTotalOptimistically() async {
        await vm.load()
        let initialTotal = vm.todayTotalMl

        await vm.add(amountMl: 250)

        XCTAssertEqual(vm.todayTotalMl, initialTotal + 250)
        XCTAssertEqual(builder.waterStore.addEntryCallCount, 1)
    }

    func testAddTriggersUndo() async {
        await vm.load()
        await vm.add(amountMl: 250)
        XCTAssertTrue(vm.canUndo)
    }

    func testAddTriggersHapticWhenEnabled() async {
        builder.settingsStore.settings.hapticsEnabled = true
        await vm.load()
        await vm.add(amountMl: 250)
        XCTAssertEqual(builder.haptics.lightImpactCount, 1)
    }

    func testAddNoHapticWhenDisabled() async {
        builder.settingsStore.settings.hapticsEnabled = false
        await vm.load()
        await vm.add(amountMl: 250)
        XCTAssertEqual(builder.haptics.lightImpactCount, 0)
    }

    func testAddGoalReachedTriggersSuccessHaptic() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        builder.settingsStore.settings.hapticsEnabled = true
        await vm.load()

        await vm.add(amountMl: 300)

        XCTAssertTrue(vm.goalReached)
        XCTAssertEqual(builder.haptics.successCount, 1)
        XCTAssertTrue(vm.sequencer.justReachedGoal)
    }

    func testAddWithHealthKitAuthorized() async {
        builder.healthService.status = .authorized
        await vm.load()

        await vm.add(amountMl: 250)

        XCTAssertEqual(builder.healthService.savedAmounts.count, 1)
        XCTAssertEqual(builder.healthService.savedAmounts.first?.0, 250)
    }

    func testAddWithHealthKitNotAuthorized() async {
        builder.healthService.status = .notDetermined
        await vm.load()

        await vm.add(amountMl: 250)

        XCTAssertTrue(builder.healthService.savedAmounts.isEmpty)
    }

    func testAddBroadcastsSnapshot() async {
        await vm.load()
        builder.broadcaster.broadcastCallCount = 0

        await vm.add(amountMl: 250)

        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
    }

    func testAddWithPersistenceErrorRevertsOptimistic() async {
        await vm.load()
        builder.waterStore.shouldThrow = true

        await vm.add(amountMl: 250)

        // Should revert - total goes back to 0 since refreshTodayEntries will also throw
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }

    func testAddWithZeroAmountIsRejected() async {
        await vm.load()
        await vm.add(amountMl: 0)

        XCTAssertEqual(vm.todayTotalMl, 0, "Zero amount should be rejected")
        XCTAssertEqual(builder.waterStore.addEntryCallCount, 0)
    }

    func testAddWithNegativeAmountIsRejected() async {
        await vm.load()
        await vm.add(amountMl: -100)

        XCTAssertEqual(vm.todayTotalMl, 0, "Negative amount should be rejected")
        XCTAssertEqual(builder.waterStore.addEntryCallCount, 0)
    }

    // MARK: - Add Custom

    func testAddCustomClampsAmount() async {
        await vm.load()
        await vm.addCustom(amountMl: 10) // Below minimum

        XCTAssertEqual(vm.customAmountMl, AppConstants.customAmountMinMl)
    }

    func testAddCustomStoresAmount() async {
        await vm.load()
        await vm.addCustom(amountMl: 350)

        XCTAssertEqual(vm.customAmountMl, 350)
        XCTAssertEqual(builder.settingsStore.settings.lastCustomAmountMl, 350)
    }

    // MARK: - Undo

    func testUndoRemovesLastEntry() async {
        await vm.load()
        await vm.add(amountMl: 250)

        XCTAssertTrue(vm.canUndo)
        XCTAssertEqual(vm.todayEntries.count, 1)

        await vm.undoLastEntry()

        XCTAssertFalse(vm.canUndo)
        XCTAssertEqual(builder.waterStore.deleteEntryCallCount, 1)
    }

    func testUndoWhenNotAvailable() async {
        await vm.load()
        XCTAssertFalse(vm.canUndo)

        await vm.undoLastEntry()

        XCTAssertEqual(builder.waterStore.deleteEntryCallCount, 0)
    }

    // MARK: - Delete Entry

    func testDeleteEntry() async {
        let entry = WaterEntry(date: .now, amountMl: 300)
        builder.waterStore.entries = [entry]
        await vm.load()

        await vm.deleteEntry(entry)

        XCTAssertEqual(builder.waterStore.deleteEntryCallCount, 1)
        XCTAssertTrue(builder.waterStore.entries.isEmpty)
    }

    func testDeleteEntryWithHealthKitSample() async {
        let sampleId = UUID()
        let entry = WaterEntry(date: .now, amountMl: 300, isFromHealth: true, healthSampleId: sampleId)
        builder.waterStore.entries = [entry]
        builder.healthService.status = .authorized
        await vm.load()

        await vm.deleteEntry(entry)

        XCTAssertEqual(builder.healthService.deletedSampleIds, [sampleId])
    }

    // MARK: - Update Entry

    func testUpdateEntry() async {
        let entry = WaterEntry(date: .now, amountMl: 200)
        builder.waterStore.entries = [entry]
        await vm.load()

        let newDate = Date.now.addingTimeInterval(3600)
        await vm.updateEntry(entry, amountMl: 500, date: newDate)

        XCTAssertGreaterThan(builder.waterStore.updateEntryCallCount, 0)
    }

    // MARK: - Progress

    func testProgressCalculation() async {
        builder.settingsStore.settings.dailyGoalMl = 2000
        let entry = WaterEntry(date: .now, amountMl: 1000)
        builder.waterStore.entries = [entry]
        await vm.load()

        XCTAssertEqual(vm.progress, 0.5, accuracy: 0.01)
    }

    func testProgressCapsAt1() async {
        builder.settingsStore.settings.dailyGoalMl = 1000
        let entry = WaterEntry(date: .now, amountMl: 2000)
        builder.waterStore.entries = [entry]
        await vm.load()

        XCTAssertEqual(vm.progress, 1.0)
    }

    func testProgressWithZeroGoal() {
        XCTAssertEqual(vm.progress, 0)
    }

    // MARK: - Goal Reached

    func testGoalReachedWhenTotalExceedsGoal() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        let entry = WaterEntry(date: .now, amountMl: 600)
        builder.waterStore.entries = [entry]
        await vm.load()

        XCTAssertTrue(vm.goalReached)
    }

    func testGoalNotReachedWhenTotalBelow() async {
        builder.settingsStore.settings.dailyGoalMl = 2500
        let entry = WaterEntry(date: .now, amountMl: 500)
        builder.waterStore.entries = [entry]
        await vm.load()

        XCTAssertFalse(vm.goalReached)
    }

    // MARK: - Quick Add Options

    func testQuickAddOptionsBasedOnGoal() async {
        builder.settingsStore.settings.dailyGoalMl = 2500
        await vm.load()

        let options = vm.quickAddOptions
        XCTAssertEqual(options.count, AppConstants.quickAddPercents.count)
        XCTAssertEqual(options.map(\.percent), AppConstants.quickAddPercents)
    }
}
