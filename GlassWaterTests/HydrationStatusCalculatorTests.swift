//
//  HydrationStatusCalculatorTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import XCTest

@testable import GlassWater

final class HydrationStatusCalculatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(hour: Int, minute: Int) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - Goal Reached

    func testGoalReachedReturnsGoalReachedRegardlessOfTime() {
        let status = HydrationStatusCalculator.status(
            progress: 1.0,
            goalReached: true,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 12, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .goalReached)
    }

    // MARK: - Outside Window

    func testBeforeWindowReturnsOutsideWindow() {
        let status = HydrationStatusCalculator.status(
            progress: 0.0,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 7, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .outsideWindow)
    }

    func testAfterWindowReturnsOutsideWindow() {
        let status = HydrationStatusCalculator.status(
            progress: 0.5,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 22, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .outsideWindow)
    }

    func testZeroWindowDurationReturnsOutsideWindow() {
        let status = HydrationStatusCalculator.status(
            progress: 0.5,
            goalReached: false,
            reminderStartMinutes: 12 * 60,
            reminderEndMinutes: 12 * 60,
            now: date(hour: 12, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .outsideWindow)
    }

    // MARK: - On Track

    func testOnTrackWhenProgressMatchesExpected() {
        // Window 9:00-21:00 (12h), time 15:00 = 50% through
        // Progress 0.50 = exactly on track
        let status = HydrationStatusCalculator.status(
            progress: 0.50,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 15, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .onTrack)
    }

    func testOnTrackWhenAheadOfSchedule() {
        // Window 9:00-21:00, time 12:00 = 25% through, progress 0.60
        let status = HydrationStatusCalculator.status(
            progress: 0.60,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 12, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .onTrack)
    }

    func testOnTrackWhenWithin5PercentBehind() {
        // Window 9:00-21:00, time 15:00 = 50% through
        // Progress 0.46 = 4% behind (within 5% tolerance)
        let status = HydrationStatusCalculator.status(
            progress: 0.46,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 15, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .onTrack)
    }

    // MARK: - Slightly Behind

    func testSlightlyBehindWhen5To20PercentBehind() {
        // Window 9:00-21:00, time 15:00 = 50% through
        // Progress 0.35 = 15% behind
        let status = HydrationStatusCalculator.status(
            progress: 0.35,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 15, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .slightlyBehind)
    }

    // MARK: - Behind

    func testBehindWhenMoreThan20PercentBehind() {
        // Window 9:00-21:00, time 15:00 = 50% through
        // Progress 0.10 = 40% behind
        let status = HydrationStatusCalculator.status(
            progress: 0.10,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 15, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .behind)
    }

    func testBehindWithZeroProgressMidDay() {
        // Window 9:00-21:00, time 18:00 = 75% through, progress 0
        let status = HydrationStatusCalculator.status(
            progress: 0.0,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 18, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .behind)
    }

    // MARK: - Edge Cases

    func testAtExactStartOfWindow() {
        let status = HydrationStatusCalculator.status(
            progress: 0.0,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 9, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .onTrack)
    }

    func testAtExactEndOfWindow() {
        // At 21:00, expected progress = 100%, progress 0.80 = 20% behind
        let status = HydrationStatusCalculator.status(
            progress: 0.80,
            goalReached: false,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 21, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .slightlyBehind)
    }

    func testGoalReachedTakesPrecedenceOverBehind() {
        let status = HydrationStatusCalculator.status(
            progress: 0.1,
            goalReached: true,
            reminderStartMinutes: 9 * 60,
            reminderEndMinutes: 21 * 60,
            now: date(hour: 20, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(status, .goalReached)
    }
}
