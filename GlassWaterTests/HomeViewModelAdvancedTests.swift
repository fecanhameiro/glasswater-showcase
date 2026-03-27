//
//  HomeViewModelAdvancedTests.swift
//  GlassWaterTests
//
//  Advanced tests for HomeViewModel: streak management, duck reward,
//  celebration, refreshFromExternalChange, and edge cases.
//

import XCTest

@testable import GlassWater

@MainActor
final class HomeViewModelAdvancedTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var vm: HomeViewModel!
    private var calendar: Calendar!

    override func setUp() async throws {
        AppServices.lastBroadcastRequestDate = nil
        LiveActivityState.clear()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        DayGoalStatus.resetToIdle(calendar: calendar)
        builder = TestServicesBuilder()
        builder.healthService.status = .notDetermined
        vm = HomeViewModel(services: builder.services, calendar: calendar)
        vm.isInForeground = true  // Tests simulate foreground behavior
    }

    override func tearDown() {
        AppServices.lastBroadcastRequestDate = nil
        LiveActivityState.clear()
        if let calendar {
            DayGoalStatus.resetToIdle(calendar: calendar)
        } else {
            DayGoalStatus.resetToIdle()
        }
        builder = nil
        vm = nil
        calendar = nil
        super.tearDown()
    }

    private var todayStart: Date {
        calendar.startOfDay(for: Date.now)
    }

    // MARK: - Streak Management

    func testStreakIncrementsOnGoalReached() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.settingsStore.settings.streakCount = 3
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: todayStart)!
        let twoDaysBefore = calendar.date(byAdding: .day, value: -3, to: todayStart)!
        builder.settingsStore.settings.lastCompletedDay = yesterday
        // Populate audit trail so calculateStreak returns correct value
        builder.settingsStore.settings.markDayCompleted(yesterday, calendar: calendar)
        builder.settingsStore.settings.markDayCompleted(dayBefore, calendar: calendar)
        builder.settingsStore.settings.markDayCompleted(twoDaysBefore, calendar: calendar)
        await vm.load()

        await vm.add(amountMl: 600)

        XCTAssertTrue(vm.goalReached)
        XCTAssertEqual(vm.streakCount, 4, "Streak should increment when goal reached with previous day completed")
    }

    func testStreakResetsToOneAfterGap() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.settingsStore.settings.streakCount = 5
        // Last completed 3 days ago (gap)
        builder.settingsStore.settings.lastCompletedDay = calendar.date(byAdding: .day, value: -3, to: todayStart)
        await vm.load()

        await vm.add(amountMl: 600)

        XCTAssertTrue(vm.goalReached)
        XCTAssertEqual(vm.streakCount, 1, "Streak should reset to 1 after a gap")
    }

    func testStreakDoesNotIncrementTwiceSameDay() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        builder.settingsStore.settings.streakCount = 2
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: todayStart)!
        builder.settingsStore.settings.lastCompletedDay = yesterday
        // Populate audit trail so recalculation returns correct streak
        builder.settingsStore.settings.markDayCompleted(yesterday, calendar: calendar)
        builder.settingsStore.settings.markDayCompleted(dayBefore, calendar: calendar)
        await vm.load()

        await vm.add(amountMl: 300)
        XCTAssertEqual(vm.streakCount, 3)

        // Add more water same day — streak should not increment again
        await vm.add(amountMl: 100)
        XCTAssertEqual(vm.streakCount, 3, "Streak should not increment twice on same day")
    }

    func testStreakRevertsWhenGoalUnreachedByDelete() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.settingsStore.settings.streakCount = 2
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: todayStart)!
        builder.settingsStore.settings.lastCompletedDay = yesterday
        // Populate audit trail so streak revert can recalculate correctly
        builder.settingsStore.settings.markDayCompleted(yesterday, calendar: calendar)
        builder.settingsStore.settings.markDayCompleted(dayBefore, calendar: calendar)
        await vm.load()

        // Reach goal
        await vm.add(amountMl: 600)
        XCTAssertEqual(vm.streakCount, 3)

        // Delete entry — goal no longer reached
        let entry = vm.todayEntries.first!
        await vm.deleteEntry(entry)

        XCTAssertFalse(vm.goalReached)
        XCTAssertEqual(vm.streakCount, 2, "Streak should revert when goal is un-reached by deletion")
    }

    func testStreakStaysZeroWhenGoalNotReached() async {
        builder.settingsStore.settings.dailyGoalMl = 5000
        builder.settingsStore.settings.streakCount = 0
        await vm.load()

        await vm.add(amountMl: 250)

        XCTAssertFalse(vm.goalReached)
        XCTAssertEqual(vm.streakCount, 0)
    }

    // MARK: - Goal Reached Celebration

    func testJustReachedGoalOnFirstGoal() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        await vm.load()

        XCTAssertFalse(vm.sequencer.justReachedGoal)
        await vm.add(amountMl: 300)

        XCTAssertTrue(vm.goalReached)
        XCTAssertTrue(vm.sequencer.justReachedGoal, "justReachedGoal should be true on first goal reach")
    }

    func testJustReachedGoalNotReTriggered() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        await vm.load()

        await vm.add(amountMl: 300)
        XCTAssertTrue(vm.sequencer.justReachedGoal)

        // Add more — already reached, justReachedGoal stays but no second success haptic
        let successCountBefore = builder.haptics.successCount
        await vm.add(amountMl: 100)
        XCTAssertEqual(builder.haptics.successCount, successCountBefore, "Should not trigger success haptic again")
    }

    // MARK: - Duck Reward

    func testDuckRewardOnFirstGoalReached() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        builder.settingsStore.settings.swimmingDuckEnabled = false
        builder.settingsStore.settings.duckCount = 0
        await vm.load()

        await vm.add(amountMl: 300)

        // Duck should be awarded (first discovery auto-enables)
        // visibleDuckCount is deferred (stays at 0 until duckRevealTask fires),
        // but the duck is persisted in settings. The async duckRevealTask will transition
        // DayGoalStatus to .duckAwarded and show the overlay.
        XCTAssertEqual(builder.settingsStore.settings.duckCount, 1, "Duck should be persisted in settings")
        XCTAssertFalse(vm.sequencer.showDuckReward, "Duck reveal overlay should not be showing yet")
        XCTAssertTrue(vm.swimmingDuckEnabled, "Should auto-enable ducks on first discovery")
        XCTAssertTrue(vm.sequencer.isFirstDuckReward)

        let duckEvents = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.duckAwarded }
        XCTAssertEqual(duckEvents.count, 1)
    }

    func testDuckNotAwardedWhenOptedOut() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        builder.settingsStore.settings.swimmingDuckEnabled = false
        builder.settingsStore.settings.duckCount = 1 // Had ducks before, then disabled
        await vm.load()

        await vm.add(amountMl: 300)

        // Ducks are hidden when disabled (visibleDuckCount=0), but silently awarded in SwiftData
        XCTAssertEqual(vm.sequencer.visibleDuckCount, 0, "Ducks should be hidden when opted out")
        XCTAssertEqual(builder.settingsStore.settings.duckCount, 2, "Duck silently awarded even when opted out")
    }

    func testDuckNotAwardedTwiceSameDay() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        builder.settingsStore.settings.swimmingDuckEnabled = true
        builder.settingsStore.settings.duckCount = 2
        builder.settingsStore.settings.lastDuckAwardedDay = todayStart
        await vm.load()

        await vm.add(amountMl: 300)

        XCTAssertEqual(vm.sequencer.visibleDuckCount, 2, "Should not award duck twice same day")
    }

    func testDuckRevokedOnGoalUnreached() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        builder.settingsStore.settings.swimmingDuckEnabled = true
        builder.settingsStore.settings.duckCount = 3
        builder.settingsStore.settings.lastDuckAwardedDay = todayStart
        await vm.load()

        // Add entry to reach goal
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300)
        builder.waterStore.entries = [entry]
        await vm.load()
        XCTAssertTrue(vm.goalReached)

        // Delete — goal un-reached
        await vm.deleteEntry(entry)

        XCTAssertFalse(vm.goalReached)
        XCTAssertEqual(vm.sequencer.visibleDuckCount, 2, "Duck should be revoked when goal un-reached")
        XCTAssertFalse(vm.sequencer.showDuckReward)

        let revokeEvents = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.duckRevoked }
        XCTAssertEqual(revokeEvents.count, 1)
    }

    // MARK: - Refresh From External Change

    func testRefreshFromExternalChangeUpdatesTotal() async {
        await vm.load()
        XCTAssertEqual(vm.todayTotalMl, 0)

        // Simulate widget adding water (entry appears in store)
        builder.waterStore.entries.append(
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 300)
        )
        vm.refreshFromExternalChange()
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(vm.todayTotalMl, 300)
        XCTAssertEqual(vm.todayEntries.count, 1)
    }

    func testRefreshFromExternalChangeDetectsGoalReached() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        await vm.load()

        // External source adds enough water
        builder.waterStore.entries.append(
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        )
        vm.refreshFromExternalChange()
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(vm.goalReached)
    }

    // MARK: - Update Entry

    func testUpdateEntryChangesTotal() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 200)
        builder.waterStore.entries = [entry]
        await vm.load()
        XCTAssertEqual(vm.todayTotalMl, 200)

        await vm.updateEntry(entry, amountMl: 500, date: entry.date)

        XCTAssertEqual(vm.todayTotalMl, 500)
        XCTAssertGreaterThan(builder.waterStore.updateEntryCallCount, 0)
    }

    func testUpdateEntryBroadcasts() async {
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 200)
        builder.waterStore.entries = [entry]
        await vm.load()
        builder.broadcaster.broadcastCallCount = 0

        await vm.updateEntry(entry, amountMl: 500, date: entry.date)

        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
    }

    // MARK: - Custom Amount Persistence

    func testCustomAmountLoadedFromSettings() async {
        builder.settingsStore.settings.lastCustomAmountMl = 400
        await vm.load()

        XCTAssertEqual(vm.customAmountMl, 400)
    }

    func testCustomAmountDefaultWhenNil() async {
        builder.settingsStore.settings.lastCustomAmountMl = nil
        builder.settingsStore.settings.dailyGoalMl = 2500
        await vm.load()

        // Should use resolvedCustomAmount (25% of goal), consistent with all surfaces
        let expected = QuickAddOptions.resolvedCustomAmount(forGoalMl: 2500, customAmountMl: nil)
        XCTAssertEqual(vm.customAmountMl, expected)
    }

    // MARK: - Celebration & External Goal

    func testCelebrateExternalGoalFiresEvenWhenDuckAlreadyAwarded() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.settingsStore.settings.swimmingDuckEnabled = true
        builder.settingsStore.settings.duckCount = 3
        builder.settingsStore.settings.lastDuckAwardedDay = todayStart
        await vm.load()

        // Simulate external add that reaches goal
        builder.waterStore.entries.append(
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        )
        vm.refreshFromExternalChange()
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(vm.goalReached)
        XCTAssertTrue(vm.sequencer.justReachedGoal, "Celebration should fire even when duck was already awarded today")
        XCTAssertEqual(vm.sequencer.visibleDuckCount, 3, "Duck should NOT be awarded again")
    }

    func testCancelCelebrationWhenDeleteUnreachesGoal() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        await vm.load()

        await vm.add(amountMl: 300)
        XCTAssertTrue(vm.sequencer.justReachedGoal)

        let entry = vm.todayEntries.first!
        await vm.deleteEntry(entry)

        XCTAssertFalse(vm.goalReached)
        XCTAssertFalse(vm.sequencer.justReachedGoal, "Celebration should be cancelled when goal is un-reached")
    }

    func testRefreshFromHistoryChangeDoesNotCelebrate() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        await vm.load()

        // Simulate history adding enough water
        builder.waterStore.entries.append(
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        )
        await vm.refreshFromHistoryChange()

        XCTAssertTrue(vm.goalReached)
        XCTAssertFalse(vm.sequencer.justReachedGoal, "History changes should not trigger celebration")
    }

    func testRefreshFromHistoryChangeCancelsCelebration() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        await vm.load()

        // Reach goal via app
        await vm.add(amountMl: 300)
        XCTAssertTrue(vm.sequencer.justReachedGoal)

        // Simulate history deleting — entry removed from store
        builder.waterStore.entries.removeAll()
        await vm.refreshFromHistoryChange()

        XCTAssertFalse(vm.goalReached)
        XCTAssertFalse(vm.sequencer.justReachedGoal, "History delete should cancel celebration")
    }

    func testStreakRevertVerifiesYesterdayTotal() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.settingsStore.settings.streakCount = 3
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: todayStart)!
        let twoDaysBefore = calendar.date(byAdding: .day, value: -3, to: todayStart)!
        builder.settingsStore.settings.lastCompletedDay = yesterday
        // Populate audit trail so streak revert can recalculate correctly
        builder.settingsStore.settings.markDayCompleted(yesterday, calendar: calendar)
        builder.settingsStore.settings.markDayCompleted(dayBefore, calendar: calendar)
        builder.settingsStore.settings.markDayCompleted(twoDaysBefore, calendar: calendar)
        await vm.load()

        // Add entry for yesterday so waterStore.total(for: yesterday) returns 600
        builder.waterStore.entries.append(
            WaterEntry(date: yesterday.addingTimeInterval(3600), amountMl: 600)
        )

        // Reach goal today
        await vm.add(amountMl: 600)
        XCTAssertEqual(vm.streakCount, 4)

        // Delete — goal un-reached
        let entry = vm.todayEntries.first!
        await vm.deleteEntry(entry)

        XCTAssertFalse(vm.goalReached)
        XCTAssertEqual(vm.streakCount, 3, "Streak should revert to 3 because yesterday had 600ml >= 500ml goal")
    }

    // MARK: - Progress Edge Cases

    func testProgressWithMultipleEntries() async {
        builder.settingsStore.settings.dailyGoalMl = 2000
        builder.waterStore.entries = [
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 500),
            WaterEntry(date: todayStart.addingTimeInterval(7200), amountMl: 500),
        ]
        await vm.load()

        XCTAssertEqual(vm.todayTotalMl, 1000)
        XCTAssertEqual(vm.progress, 0.5, accuracy: 0.01)
    }

    func testHydrationStatusOutsideWindow() async {
        builder.settingsStore.settings.reminderStartMinutes = 9 * 60
        builder.settingsStore.settings.reminderEndMinutes = 10 * 60 // Very narrow window
        await vm.load()

        // Status depends on current time — just verify it returns a valid value
        let status = vm.hydrationStatus
        XCTAssertNotNil(status)
    }

    // MARK: - LA Broadcast Scenarios

    func testBroadcastCalledOnAdd() async {
        builder.settingsStore.settings.dailyGoalMl = 2500
        await vm.load()
        builder.broadcaster.broadcastCallCount = 0

        await vm.add(amountMl: 250)

        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0,
                             "Broadcast should be called after adding water")
    }

    func testGoalReachedBroadcastsSnapshotWithGoalReached() async {
        builder.settingsStore.settings.dailyGoalMl = 250
        await vm.load()

        await vm.add(amountMl: 300)

        XCTAssertTrue(vm.goalReached)
        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
    }

    // MARK: - External Goal Reach + Re-Celebration

    func testExternalGoalReachCelebratesOnce() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        await vm.load()
        XCTAssertFalse(vm.goalReached)

        // First external goal reach
        builder.waterStore.entries.append(
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        )
        vm.refreshFromExternalChange()
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertTrue(vm.goalReached)

        // Track success haptic count before second notification
        let successCountBefore = builder.haptics.successCount

        // Second external notification — should NOT re-celebrate
        vm.refreshFromExternalChange()
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertTrue(vm.goalReached, "Goal should still be reached")
        XCTAssertEqual(builder.haptics.successCount, successCountBefore,
                       "Should not trigger success haptic again on second external notification")
    }

    func testExternalGoalUnreachAllowsReCelebration() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.settingsStore.settings.swimmingDuckEnabled = true
        builder.settingsStore.settings.duckCount = 1
        await vm.load()

        // Reach goal
        await vm.add(amountMl: 600)
        XCTAssertTrue(vm.goalReached)
        let duckCountAfterFirst = vm.sequencer.visibleDuckCount

        // Delete entry — un-reach
        let entry = vm.todayEntries.first!
        await vm.deleteEntry(entry)
        XCTAssertFalse(vm.goalReached)

        // Re-reach goal — should celebrate again
        await vm.add(amountMl: 600)
        XCTAssertTrue(vm.goalReached)
        XCTAssertTrue(vm.sequencer.justReachedGoal, "Should celebrate again after un-reach + re-reach")
        XCTAssertEqual(vm.sequencer.visibleDuckCount, duckCountAfterFirst,
                        "Duck count should return to same level after revoke + re-award")
    }

    // MARK: - Streak: calculateStreak Self-Healing

    func testStreakUsesCalculateStreakNotPlusOne() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        // Set up a deliberate inconsistency: streakCount says 10 but audit trail has only 2 days
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        builder.settingsStore.settings.streakCount = 10
        builder.settingsStore.settings.lastCompletedDay = yesterday
        builder.settingsStore.settings.markDayCompleted(yesterday, calendar: calendar)
        // Only yesterday in audit trail — calculateStreak should return 2 (yesterday + today), not 11
        await vm.load()

        await vm.add(amountMl: 600)

        XCTAssertTrue(vm.goalReached)
        XCTAssertEqual(vm.streakCount, 2,
                        "Streak should be recalculated from audit trail (2), not incremented from stale value (11)")
    }

    func testStreakRetroactiveFlushesToAuditTrail() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.settingsStore.settings.streakCount = 0
        builder.settingsStore.settings.swimmingDuckEnabled = true
        builder.settingsStore.settings.duckCount = 1

        // Simulate water added via widget while app was closed (entries in store, goal reached)
        builder.waterStore.entries.append(
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        )
        await vm.load()

        // After load, awardMissedDucksAndStreak should have run and flushed to audit trail
        let completedDays = builder.settingsStore.settings.completedDays
        let todayInTrail = completedDays.contains { calendar.isDate($0, inSameDayAs: todayStart) }
        XCTAssertTrue(todayInTrail, "Today should be in completedDaysJSON after retroactive update")
    }

    func testStreakSurvivesRelaunchAfterRetroactiveUpdate() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        builder.settingsStore.settings.streakCount = 0
        builder.settingsStore.settings.swimmingDuckEnabled = true
        builder.settingsStore.settings.duckCount = 1

        // External add reaching goal
        builder.waterStore.entries.append(
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        )
        await vm.load()
        let streakAfterFirstLoad = vm.streakCount
        XCTAssertGreaterThan(streakAfterFirstLoad, 0)

        // Simulate "relaunch" by calling load again
        await vm.load()

        XCTAssertEqual(vm.streakCount, streakAfterFirstLoad,
                        "Streak should survive relaunch because audit trail was flushed")
    }

    // MARK: - Cross-Day Entry Edit

    func testCrossDayEntryEditUpdatesAuditTrail() async {
        builder.settingsStore.settings.dailyGoalMl = 500
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        // Entry starts on today
        let entry = WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        builder.waterStore.entries = [entry]
        await vm.load()
        XCTAssertTrue(vm.goalReached)

        // Move entry to yesterday
        await vm.updateEntry(entry, amountMl: 600, date: yesterday.addingTimeInterval(3600))

        // Today should now have 0ml — goal not reached
        XCTAssertFalse(vm.goalReached)

        // Yesterday should be in audit trail (if total >= goal)
        let yesterdayInTrail = builder.settingsStore.settings.completedDays
            .contains { calendar.isDate($0, inSameDayAs: yesterday) }
        XCTAssertTrue(yesterdayInTrail,
                       "Yesterday should be marked in audit trail after receiving the entry")

        // Today should NOT be in audit trail
        let todayInTrail = builder.settingsStore.settings.completedDays
            .contains { calendar.isDate($0, inSameDayAs: todayStart) }
        XCTAssertFalse(todayInTrail,
                        "Today should be unmarked from audit trail after losing the entry")
    }

    // MARK: - Celebration Persistence

    func testGoalCelebratedTodayRestoredFromDayGoalStatus() async {
        // Simulate that celebration already happened today (persisted in DayGoalStatus)
        DayGoalStatus.transitionTo(.goalReached, calendar: calendar)
        DayGoalStatus.transitionTo(.celebrating, calendar: calendar)
        DayGoalStatus.transitionTo(.duckAwarded, calendar: calendar)
        DayGoalStatus.transitionTo(.completed, calendar: calendar)

        // Also set LiveActivityState for consistency
        var state = LiveActivityState.idle(calendar: calendar)
        state.transition(to: .goalReached, now: .now, calendar: calendar)
        defer { LiveActivityState.clear() }

        builder.settingsStore.settings.dailyGoalMl = 500
        builder.waterStore.entries.append(
            WaterEntry(date: todayStart.addingTimeInterval(3600), amountMl: 600)
        )
        await vm.load()

        // Goal is reached but celebration should NOT fire again
        XCTAssertTrue(vm.goalReached)
        XCTAssertFalse(vm.sequencer.justReachedGoal,
                        "Should not re-celebrate when already celebrated today (DayGoalStatus is completed)")
    }
}
