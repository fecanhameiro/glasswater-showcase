//
//  StreakAuditTrailTests.swift
//  GlassWaterTests
//
//  Pure unit tests for UserSettings streak audit trail:
//  calculateStreak(), markDayCompleted(), unmarkDayCompleted().
//  These are pure function tests with no ViewModel or service dependencies.
//

import XCTest

@testable import GlassWater

final class StreakAuditTrailTests: XCTestCase {
    private var settings: UserSettings!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        settings = UserSettings()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        settings = nil
        calendar = nil
        super.tearDown()
    }

    private var todayStart: Date {
        calendar.startOfDay(for: .now)
    }

    private func dayOffset(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: todayStart)!
    }

    // MARK: - calculateStreak

    func testCalculateStreakConsecutiveDays() {
        // Mark 5 consecutive days ending today
        for i in -4...0 {
            settings.markDayCompleted(dayOffset(i), calendar: calendar)
        }

        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 5, "5 consecutive days ending today should give streak of 5")
    }

    func testCalculateStreakWithGap() {
        // [D-4, D-3, D-1, D] — gap at D-2
        settings.markDayCompleted(dayOffset(-4), calendar: calendar)
        settings.markDayCompleted(dayOffset(-3), calendar: calendar)
        settings.markDayCompleted(dayOffset(-1), calendar: calendar)
        settings.markDayCompleted(dayOffset(0), calendar: calendar)

        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 2, "Gap at D-2 should break streak — only D-1 + D count")
    }

    func testCalculateStreakEmptyReturnsZero() {
        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 0)
    }

    func testCalculateStreakStartsFromTodayOrYesterday() {
        // Only days 5+ ago, no today or yesterday
        settings.markDayCompleted(dayOffset(-5), calendar: calendar)
        settings.markDayCompleted(dayOffset(-6), calendar: calendar)

        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 0, "Streak must start from today or yesterday")
    }

    func testCalculateStreakStartsFromYesterday() {
        // Yesterday + day before — no today
        settings.markDayCompleted(dayOffset(-1), calendar: calendar)
        settings.markDayCompleted(dayOffset(-2), calendar: calendar)

        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 2, "Streak starting from yesterday should still count")
    }

    func testCalculateStreakDeduplicatesDays() {
        // Mark same day twice
        settings.markDayCompleted(dayOffset(0), calendar: calendar)
        settings.markDayCompleted(dayOffset(0), calendar: calendar)
        settings.markDayCompleted(dayOffset(-1), calendar: calendar)

        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 2, "Duplicate days should count as 1")
    }

    // MARK: - markDayCompleted

    func testMarkDayCompletedIdempotent() {
        settings.markDayCompleted(dayOffset(0), calendar: calendar)
        let countAfterFirst = settings.completedDays.count

        settings.markDayCompleted(dayOffset(0), calendar: calendar)
        let countAfterSecond = settings.completedDays.count

        XCTAssertEqual(countAfterFirst, countAfterSecond,
                       "Marking same day twice should not add duplicate")
    }

    func testMarkDayCompletedSortedDescending() {
        settings.markDayCompleted(dayOffset(-3), calendar: calendar)
        settings.markDayCompleted(dayOffset(0), calendar: calendar)
        settings.markDayCompleted(dayOffset(-1), calendar: calendar)

        let days = settings.completedDays
        XCTAssertEqual(days.count, 3)
        // Verify descending order
        for i in 0..<(days.count - 1) {
            XCTAssertGreaterThanOrEqual(days[i], days[i + 1],
                                        "completedDays should be sorted descending")
        }
    }

    // MARK: - unmarkDayCompleted

    func testUnmarkDayCompleted() {
        settings.markDayCompleted(dayOffset(0), calendar: calendar)
        settings.markDayCompleted(dayOffset(-1), calendar: calendar)
        XCTAssertEqual(settings.completedDays.count, 2)

        settings.unmarkDayCompleted(dayOffset(0), calendar: calendar)
        XCTAssertEqual(settings.completedDays.count, 1)

        // Streak should now be 1 (only yesterday)
        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 1)
    }

    // MARK: - 30-day trim

    func testCompletedDaysTrimsOlderThan30Days() {
        // Mark a day 31 days ago
        let oldDay = dayOffset(-31)
        settings.markDayCompleted(oldDay, calendar: calendar)
        settings.markDayCompleted(dayOffset(0), calendar: calendar)

        let days = settings.completedDays
        let hasOldDay = days.contains { calendar.isDate($0, inSameDayAs: oldDay) }
        XCTAssertFalse(hasOldDay, "Days older than 30 days should be trimmed")
        XCTAssertEqual(days.count, 1, "Only today should remain")
    }

    // MARK: - Stale streakCount vs empty audit trail

    func testCalculateStreakReturnsZeroWhenAuditTrailEmptyDespiteStaleStreakCount() {
        // Simulate the exact bug scenario: streakCount says 10 but completedDaysJSON is empty
        settings.streakCount = 10
        settings.lastCompletedDay = dayOffset(-1)

        // calculateStreak should return 0 because the audit trail is the source of truth
        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 0,
                       "calculateStreak must return 0 when audit trail is empty, regardless of stale streakCount")
    }

    func testCalculateStreakIgnoresStaleStreakCountWithPartialAuditTrail() {
        // streakCount says 10 but audit trail only has today
        settings.streakCount = 10
        settings.lastCompletedDay = dayOffset(0)
        settings.markDayCompleted(dayOffset(0), calendar: calendar)

        let streak = settings.calculateStreak(calendar: calendar)
        XCTAssertEqual(streak, 1,
                       "calculateStreak should return 1 (only today in trail), not the stale streakCount of 10")
    }
}
