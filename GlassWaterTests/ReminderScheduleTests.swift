//
//  ReminderScheduleTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import XCTest

@testable import GlassWater

final class ReminderScheduleTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    private func date(year: Int = 2026, month: Int = 2, day: Int = 6, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: components)!
    }

    // MARK: - Schedule Dates

    func testScheduleDatesGeneratesCorrectIntervals() {
        let reference = date(hour: 9, minute: 0)
        let dates = ReminderSchedule.scheduleDates(
            referenceDate: reference,
            startMinutes: 9 * 60,
            endMinutes: 21 * 60,
            intervalMinutes: 120,
            calendar: calendar
        )
        // 9:00, 11:00, 13:00, 15:00, 17:00, 19:00, 21:00
        XCTAssertEqual(dates.count, 7)
    }

    func testScheduleDatesSkipsPastTimes() {
        let reference = date(hour: 14, minute: 0)
        let dates = ReminderSchedule.scheduleDates(
            referenceDate: reference,
            startMinutes: 9 * 60,
            endMinutes: 21 * 60,
            intervalMinutes: 120,
            calendar: calendar
        )
        // Past times (9, 11, 13) wrap to next day, future times (15, 17, 19, 21) stay today
        for d in dates {
            XCTAssertGreaterThanOrEqual(d, reference)
        }
    }

    func testScheduleDatesAreSorted() {
        let reference = date(hour: 12, minute: 0)
        let dates = ReminderSchedule.scheduleDates(
            referenceDate: reference,
            startMinutes: 9 * 60,
            endMinutes: 21 * 60,
            intervalMinutes: 120,
            calendar: calendar
        )
        XCTAssertEqual(dates, dates.sorted())
    }

    func testScheduleDatesWithMinimumInterval() {
        let reference = date(hour: 9, minute: 0)
        let dates = ReminderSchedule.scheduleDates(
            referenceDate: reference,
            startMinutes: 9 * 60,
            endMinutes: 10 * 60,
            intervalMinutes: 30,
            calendar: calendar
        )
        // 9:00, 9:30, 10:00
        XCTAssertEqual(dates.count, 3)
    }

    // MARK: - Next Refresh Date

    func testNextRefreshDateReturnsFirstFutureDate() {
        let reference = date(hour: 14, minute: 0)
        let next = ReminderSchedule.nextRefreshDate(
            referenceDate: reference,
            startMinutes: 9 * 60,
            endMinutes: 21 * 60,
            intervalMinutes: 120,
            calendar: calendar
        )
        XCTAssertNotNil(next)
        XCTAssertGreaterThanOrEqual(next!, reference)
    }

    func testNextRefreshDateReturnsNilForEmptySchedule() {
        // This shouldn't actually return nil because there's a fallback,
        // but test with extreme clamped values
        let reference = date(hour: 10, minute: 30)
        let next = ReminderSchedule.nextRefreshDate(
            referenceDate: reference,
            startMinutes: 10 * 60 + 30,
            endMinutes: 10 * 60 + 30,
            intervalMinutes: 60,
            calendar: calendar
        )
        XCTAssertNotNil(next)
    }

    // MARK: - Window End Date

    func testReminderWindowEndDateNormalWindow() {
        let reference = date(hour: 12, minute: 0)
        let endDate = ReminderSchedule.reminderWindowEndDate(
            referenceDate: reference,
            startMinutes: 9 * 60,
            endMinutes: 21 * 60,
            calendar: calendar
        )
        XCTAssertNotNil(endDate)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endDate!)
        XCTAssertEqual(endComponents.hour, 21)
        XCTAssertEqual(endComponents.minute, 0)
    }

    // MARK: - Edge Cases

    func testScheduleWithIntervalBelowMinimumClampsTo30() {
        let reference = date(hour: 9, minute: 0)
        let dates = ReminderSchedule.scheduleDates(
            referenceDate: reference,
            startMinutes: 9 * 60,
            endMinutes: 10 * 60,
            intervalMinutes: 5, // Below minimum
            calendar: calendar
        )
        // Should clamp to 30 min: 9:00, 9:30, 10:00
        XCTAssertEqual(dates.count, 3)
    }

    func testScheduleWithNegativeStartClamps() {
        let reference = date(hour: 0, minute: 0)
        let dates = ReminderSchedule.scheduleDates(
            referenceDate: reference,
            startMinutes: -100,
            endMinutes: 2 * 60,
            intervalMinutes: 60,
            calendar: calendar
        )
        XCTAssertFalse(dates.isEmpty)
    }
}
