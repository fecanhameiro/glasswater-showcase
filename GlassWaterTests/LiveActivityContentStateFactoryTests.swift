//
//  LiveActivityContentStateFactoryTests.swift
//  GlassWaterTests
//
//  Tests for LiveActivityContentStateFactory — pure function that builds
//  ContentState for Dynamic Island and Lock Screen Live Activity.
//

#if os(iOS)
import XCTest

@testable import GlassWater

final class LiveActivityContentStateFactoryTests: XCTestCase {

    // MARK: - Progress Calculation

    func testBasicProgress() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 1250, dailyGoalMl: 2500,
            lastIntakeMl: 250, lastIntakeDate: .now,
            isSensitive: false, customAmountMl: 300
        )
        XCTAssertEqual(state.progress, 0.5, accuracy: 0.001)
    }

    func testProgressCapsAtOne() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 3000, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: 300
        )
        XCTAssertEqual(state.progress, 1.0, "Progress must cap at 1.0")
    }

    func testZeroGoalProgress() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 500, dailyGoalMl: 0,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertEqual(state.progress, 0, "Progress should be 0 when goal is 0")
    }

    // MARK: - Goal Reached

    func testGoalReachedWhenExceeded() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 2600, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertTrue(state.goalReached)
    }

    func testGoalReachedExactly() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 2500, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertTrue(state.goalReached)
    }

    func testGoalNotReached() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 1000, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertFalse(state.goalReached)
    }

    func testGoalNotReachedWhenGoalIsZero() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 500, dailyGoalMl: 0,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertFalse(state.goalReached)
    }

    // MARK: - Remaining

    func testRemainingMl() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 1000, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertEqual(state.remainingMl, 1500)
    }

    func testRemainingNeverNegative() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 3000, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertEqual(state.remainingMl, 0)
    }

    // MARK: - Custom Amount

    func testCustomAmountResolved() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 0, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: 350
        )
        XCTAssertEqual(state.customAmountMl, 350)
    }

    func testCustomAmountNilFallsBackToPercentOfGoal() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 0, dailyGoalMl: 2000,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        // Fallback: 25% of 2000 = 500, clamped
        let expected = QuickAddOptions.resolvedCustomAmount(forGoalMl: 2000, customAmountMl: nil)
        XCTAssertEqual(state.customAmountMl, expected)
    }

    // MARK: - Passthrough Fields

    func testSensitiveModePassthrough() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 0, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: true, customAmountMl: nil
        )
        XCTAssertTrue(state.isSensitive)
    }

    func testLastIntakeFieldsPassthrough() {
        let date = Date.now
        let state = LiveActivityContentStateFactory.make(
            currentMl: 500, dailyGoalMl: 2500,
            lastIntakeMl: 250, lastIntakeDate: date,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertEqual(state.lastIntakeMl, 250)
        XCTAssertEqual(state.lastIntakeDate, date)
    }

    func testLastIntakeFieldsNil() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 0, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertNil(state.lastIntakeMl)
        XCTAssertNil(state.lastIntakeDate)
    }

    func testCurrentMlPassthrough() {
        let state = LiveActivityContentStateFactory.make(
            currentMl: 1234, dailyGoalMl: 2500,
            lastIntakeMl: nil, lastIntakeDate: nil,
            isSensitive: false, customAmountMl: nil
        )
        XCTAssertEqual(state.currentMl, 1234)
    }
}
#endif
