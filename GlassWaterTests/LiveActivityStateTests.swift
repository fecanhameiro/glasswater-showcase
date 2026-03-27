//
//  LiveActivityStateTests.swift
//  GlassWaterTests
//
//  Tests for the LiveActivityState state machine — single source of truth
//  for Live Activity goal/celebration lifecycle.
//

import XCTest
@testable import GlassWater

final class LiveActivityStateTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        LiveActivityState.clear()
    }

    override func tearDown() {
        LiveActivityState.clear()
        calendar = nil
        super.tearDown()
    }

    // MARK: - Phase Transitions

    func testIdleTransitionToInProgress() {
        var state = LiveActivityState.idle(calendar: calendar)
        XCTAssertEqual(state.phase, .idle)

        let success = state.transition(to: .inProgress, now: .now, calendar: calendar)
        XCTAssertTrue(success)
        XCTAssertEqual(state.phase, .inProgress)
        XCTAssertNil(state.celebrationDismissAt)
    }

    func testInProgressTransitionToGoalReached() {
        var state = LiveActivityState.idle(calendar: calendar)
        state.transition(to: .inProgress, now: .now, calendar: calendar)

        let dismissAt = Date.now.addingTimeInterval(30 * 60)
        let success = state.transition(to: .goalReached, now: .now, calendar: calendar, celebrationDismissAt: dismissAt)
        XCTAssertTrue(success)
        XCTAssertEqual(state.phase, .goalReached)
        XCTAssertNotNil(state.celebrationDismissAt)
        XCTAssertEqual(state.celebrationDismissAt!.timeIntervalSince1970, dismissAt.timeIntervalSince1970, accuracy: 1.0)
    }

    func testGoalReachedTransitionToDismissed() {
        var state = LiveActivityState.idle(calendar: calendar)
        let dismissAt = Date.now.addingTimeInterval(30 * 60)
        state.transition(to: .goalReached, now: .now, calendar: calendar, celebrationDismissAt: dismissAt)

        let success = state.transition(to: .dismissed, now: .now, calendar: calendar)
        XCTAssertTrue(success)
        XCTAssertEqual(state.phase, .dismissed)
        XCTAssertNil(state.celebrationDismissAt, "celebrationDismissAt should be cleared on dismiss")
    }

    func testDayChangeOverridesRequestedPhase() {
        var state = LiveActivityState.idle(calendar: calendar)
        state.transition(to: .inProgress, now: .now, calendar: calendar)

        // Simulate "tomorrow"
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let success = state.transition(to: .goalReached, now: tomorrow, calendar: calendar)
        XCTAssertFalse(success, "Day change should override requested phase and return false")
        XCTAssertEqual(state.phase, .newDay, "Phase should be .newDay after day change")
        XCTAssertNil(state.celebrationDismissAt)
    }

    func testNewDayTransitionToInProgress() {
        var state = LiveActivityState.idle(calendar: calendar)
        // Force newDay
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        state.transition(to: .inProgress, now: tomorrow, calendar: calendar) // overridden to .newDay
        XCTAssertEqual(state.phase, .newDay)

        // Now transition to inProgress on the new day
        let success = state.transition(to: .inProgress, now: tomorrow, calendar: calendar)
        XCTAssertTrue(success)
        XCTAssertEqual(state.phase, .inProgress)
    }

    // MARK: - Derived Properties

    func testGoalCelebratedTodayDerivedCorrectly() {
        var state = LiveActivityState.idle(calendar: calendar)
        XCTAssertFalse(state.goalCelebratedToday)

        state.transition(to: .inProgress, now: .now, calendar: calendar)
        XCTAssertFalse(state.goalCelebratedToday)

        state.transition(to: .goalReached, now: .now, calendar: calendar)
        XCTAssertTrue(state.goalCelebratedToday, "goalReached should count as celebrated")

        state.transition(to: .dismissed, now: .now, calendar: calendar)
        XCTAssertTrue(state.goalCelebratedToday, "dismissed should count as celebrated")

        // newDay should NOT count as celebrated
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        state.transition(to: .inProgress, now: tomorrow, calendar: calendar) // → .newDay
        XCTAssertFalse(state.goalCelebratedToday, "newDay should not count as celebrated")
    }

    func testIsCelebrationExpired() {
        var state = LiveActivityState.idle(calendar: calendar)
        let dismissAt = Date.now.addingTimeInterval(30 * 60)
        state.transition(to: .goalReached, now: .now, calendar: calendar, celebrationDismissAt: dismissAt)

        XCTAssertFalse(state.isCelebrationExpired(now: .now), "Should not be expired right after goal reached")
        XCTAssertFalse(state.isCelebrationExpired(now: dismissAt.addingTimeInterval(-1)), "Should not be expired 1s before dismiss")
        XCTAssertTrue(state.isCelebrationExpired(now: dismissAt), "Should be expired at exactly dismiss time")
        XCTAssertTrue(state.isCelebrationExpired(now: dismissAt.addingTimeInterval(60)), "Should be expired after dismiss time")
    }

    func testIsCelebrationExpiredOnlyForGoalReached() {
        var state = LiveActivityState.idle(calendar: calendar)
        state.transition(to: .inProgress, now: .now, calendar: calendar)
        XCTAssertFalse(state.isCelebrationExpired(now: .distantFuture), "inProgress should never be 'celebration expired'")

        state.transition(to: .dismissed, now: .now, calendar: calendar)
        XCTAssertFalse(state.isCelebrationExpired(now: .distantFuture), "dismissed should never be 'celebration expired'")
    }

    // MARK: - IsToday

    func testIsTodayReturnsTrueForToday() {
        let state = LiveActivityState.idle(calendar: calendar)
        XCTAssertTrue(state.isToday(calendar: calendar))
    }

    func testIsTodayReturnsFalseForYesterday() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))!
        let state = LiveActivityState(phase: .dismissed, date: yesterday, dayStart: yesterday)
        XCTAssertFalse(state.isToday(calendar: calendar))
    }

    // MARK: - Persistence

    func testSaveAndLoadRoundTrip() {
        var state = LiveActivityState.idle(calendar: calendar)
        let dismissAt = Date.now.addingTimeInterval(1800)
        state.transition(to: .goalReached, now: .now, calendar: calendar, celebrationDismissAt: dismissAt)
        // state.save() is called by transition()

        let loaded = LiveActivityState.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.phase, .goalReached)
        XCTAssertNotNil(loaded?.celebrationDismissAt)
        XCTAssertEqual(loaded?.celebrationDismissAt?.timeIntervalSince1970 ?? 0, dismissAt.timeIntervalSince1970, accuracy: 1.0)
    }

    func testClearRemovesState() {
        var state = LiveActivityState.idle(calendar: calendar)
        state.transition(to: .inProgress, now: .now, calendar: calendar)

        LiveActivityState.clear()
        XCTAssertNil(LiveActivityState.load())
    }

    func testLoadReturnsNilWhenNoState() {
        LiveActivityState.clear()
        XCTAssertNil(LiveActivityState.load())
    }

    // MARK: - Edge Cases

    func testMultipleTransitionsInSameDay() {
        var state = LiveActivityState.idle(calendar: calendar)
        state.transition(to: .inProgress, now: .now, calendar: calendar)
        state.transition(to: .goalReached, now: .now, calendar: calendar)
        state.transition(to: .dismissed, now: .now, calendar: calendar)

        XCTAssertEqual(state.phase, .dismissed)
        XCTAssertTrue(state.goalCelebratedToday)

        // Un-reach goal
        state.transition(to: .inProgress, now: .now, calendar: calendar)
        XCTAssertEqual(state.phase, .inProgress)
        XCTAssertFalse(state.goalCelebratedToday)

        // Re-reach goal
        let newDismissAt = Date.now.addingTimeInterval(1800)
        state.transition(to: .goalReached, now: .now, calendar: calendar, celebrationDismissAt: newDismissAt)
        XCTAssertEqual(state.phase, .goalReached)
        XCTAssertTrue(state.goalCelebratedToday)
    }

    func testDayChangeClearsCelebrationDismissAt() {
        var state = LiveActivityState.idle(calendar: calendar)
        let dismissAt = Date.now.addingTimeInterval(1800)
        state.transition(to: .goalReached, now: .now, calendar: calendar, celebrationDismissAt: dismissAt)
        XCTAssertNotNil(state.celebrationDismissAt)

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        state.transition(to: .inProgress, now: tomorrow, calendar: calendar) // → .newDay
        XCTAssertNil(state.celebrationDismissAt, "Day change should clear celebrationDismissAt")
    }
}
