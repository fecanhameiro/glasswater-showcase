//
//  DomainModelTests.swift
//  GlassWaterTests
//
//  Tests for pure domain models: DailyIntakeSummary, DayPeriod,
//  WeeklyInsight, NotificationContentFactory.
//

import XCTest

@testable import GlassWater

final class DomainModelTests: XCTestCase {

    // MARK: - DailyIntakeSummary

    func testProgressCalculation() {
        let summary = DailyIntakeSummary(
            date: .now, amountMl: 1250, goalMl: 2500, entryCount: 3, entries: []
        )
        XCTAssertEqual(summary.progress, 0.5, accuracy: 0.001)
    }

    func testProgressWithZeroGoal() {
        let summary = DailyIntakeSummary(
            date: .now, amountMl: 500, goalMl: 0, entryCount: 1, entries: []
        )
        XCTAssertEqual(summary.progress, 0, "Should be 0 when goal is 0")
    }

    func testProgressCanExceedOne() {
        let summary = DailyIntakeSummary(
            date: .now, amountMl: 3000, goalMl: 2500, entryCount: 5, entries: []
        )
        XCTAssertGreaterThan(summary.progress, 1.0, "DailyIntakeSummary progress is unclamped")
    }

    func testIsGoalMetExactly() {
        let summary = DailyIntakeSummary(
            date: .now, amountMl: 2500, goalMl: 2500, entryCount: 5, entries: []
        )
        XCTAssertTrue(summary.isGoalMet)
    }

    func testIsGoalMetBelow() {
        let summary = DailyIntakeSummary(
            date: .now, amountMl: 2499, goalMl: 2500, entryCount: 5, entries: []
        )
        XCTAssertFalse(summary.isGoalMet)
    }

    func testIsGoalMetAbove() {
        let summary = DailyIntakeSummary(
            date: .now, amountMl: 3000, goalMl: 2500, entryCount: 5, entries: []
        )
        XCTAssertTrue(summary.isGoalMet)
    }

    func testIsGoalMetWithZeroGoal() {
        let summary = DailyIntakeSummary(
            date: .now, amountMl: 0, goalMl: 0, entryCount: 0, entries: []
        )
        XCTAssertTrue(summary.isGoalMet, "0 >= 0 is true")
    }

    // MARK: - DayPeriod

    func testDayPeriodMorning() {
        for hour in 5..<12 {
            XCTAssertEqual(DayPeriod.from(hour: hour), .morning, "Hour \(hour) should be morning")
        }
    }

    func testDayPeriodAfternoon() {
        for hour in 12..<18 {
            XCTAssertEqual(DayPeriod.from(hour: hour), .afternoon, "Hour \(hour) should be afternoon")
        }
    }

    func testDayPeriodNight() {
        let nightHours = [0, 1, 2, 3, 4, 18, 19, 20, 21, 22, 23]
        for hour in nightHours {
            XCTAssertEqual(DayPeriod.from(hour: hour), .night, "Hour \(hour) should be night")
        }
    }

    func testDayPeriodBoundaries() {
        XCTAssertEqual(DayPeriod.from(hour: 4), .night, "4am is night")
        XCTAssertEqual(DayPeriod.from(hour: 5), .morning, "5am is morning")
        XCTAssertEqual(DayPeriod.from(hour: 11), .morning, "11am is morning")
        XCTAssertEqual(DayPeriod.from(hour: 12), .afternoon, "12pm is afternoon")
        XCTAssertEqual(DayPeriod.from(hour: 17), .afternoon, "5pm is afternoon")
        XCTAssertEqual(DayPeriod.from(hour: 18), .night, "6pm is night")
    }

    func testDayPeriodAllCases() {
        XCTAssertEqual(DayPeriod.allCases.count, 3)
    }

    func testDayPeriodRawValues() {
        XCTAssertEqual(DayPeriod.morning.rawValue, "morning")
        XCTAssertEqual(DayPeriod.afternoon.rawValue, "afternoon")
        XCTAssertEqual(DayPeriod.night.rawValue, "night")
    }

    // MARK: - WeeklyInsight

    func testWeeklyInsightNoneHasNilText() {
        XCTAssertNil(WeeklyInsight.none.text)
    }

    func testWeeklyInsightNonNoneHasText() {
        let nonNone: [WeeklyInsight] = [
            .morningPerson, .afternoonPerson, .eveningPerson,
            .consistentHydration, .improvingTrend, .needsMoreWater, .greatWeek
        ]
        for insight in nonNone {
            XCTAssertNotNil(insight.text, "\(insight) should have text")
        }
    }

    func testWeeklyInsightNoneHasEmptyEmoji() {
        XCTAssertEqual(WeeklyInsight.none.emoji, "")
    }

    func testWeeklyInsightNonNoneHasEmoji() {
        let nonNone: [WeeklyInsight] = [
            .morningPerson, .afternoonPerson, .eveningPerson,
            .consistentHydration, .improvingTrend, .needsMoreWater, .greatWeek
        ]
        for insight in nonNone {
            XCTAssertFalse(insight.emoji.isEmpty, "\(insight) should have emoji")
        }
    }

    // MARK: - NotificationContentFactory

    func testNotificationContentReturnsNonEmpty() {
        let context = NotificationContentFactory.Context(
            currentTotalMl: 500, dailyGoalMl: 2500, date: .now, streakCount: 0
        )
        let content = NotificationContentFactory.makeContent(context: context)

        XCTAssertFalse(content.title.isEmpty)
        XCTAssertFalse(content.body.isEmpty)
    }

    func testNotificationContentDeterministic() {
        // Same date+hour should produce same content
        let fixedDate = Date(timeIntervalSince1970: 1711000000) // fixed point in time
        let context = NotificationContentFactory.Context(
            currentTotalMl: 500, dailyGoalMl: 2500, date: fixedDate, streakCount: 0
        )

        let content1 = NotificationContentFactory.makeContent(context: context)
        let content2 = NotificationContentFactory.makeContent(context: context)

        XCTAssertEqual(content1.title, content2.title, "Same input should give same title")
        XCTAssertEqual(content1.body, content2.body, "Same input should give same body")
    }

    func testNotificationContentStreakBodyWhenEligible() {
        // Streak >= 3 and seed % 3 == 0 triggers streak body
        // seed = dayOrdinal + hour, we need to find a date where this holds
        // Use brute force with a fixed date
        let calendar = Calendar(identifier: .gregorian)
        var foundStreakContent = false

        // Try 24 hours of a single day to find one where seed % 3 == 0
        for hour in 0..<24 {
            var components = DateComponents()
            components.year = 2026
            components.month = 3
            components.day = 15
            components.hour = hour
            guard let date = calendar.date(from: components) else { continue }

            let dayOrdinal = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
            let seed = dayOrdinal &+ hour
            if seed % 3 == 0 {
                let context = NotificationContentFactory.Context(
                    currentTotalMl: 500, dailyGoalMl: 2500, date: date, streakCount: 5
                )
                let content = NotificationContentFactory.makeContent(context: context)
                // Streak body should be from streak keys
                XCTAssertFalse(content.body.isEmpty)
                foundStreakContent = true
                break
            }
        }
        XCTAssertTrue(foundStreakContent, "Should find at least one hour where streak body triggers")
    }

    func testNotificationContentProgressBands() {
        let fixedDate = Date(timeIntervalSince1970: 1711000000)

        // Low progress (< 25%)
        let lowContext = NotificationContentFactory.Context(
            currentTotalMl: 100, dailyGoalMl: 2500, date: fixedDate, streakCount: 0
        )
        let lowContent = NotificationContentFactory.makeContent(context: lowContext)
        XCTAssertFalse(lowContent.body.isEmpty)

        // High progress (>= 75%)
        let highContext = NotificationContentFactory.Context(
            currentTotalMl: 2000, dailyGoalMl: 2500, date: fixedDate, streakCount: 0
        )
        let highContent = NotificationContentFactory.makeContent(context: highContext)
        XCTAssertFalse(highContent.body.isEmpty)
    }

    func testNotificationContentZeroGoal() {
        let context = NotificationContentFactory.Context(
            currentTotalMl: 500, dailyGoalMl: 0, date: .now, streakCount: 0
        )
        let content = NotificationContentFactory.makeContent(context: context)

        // progress = 0, should use low progress keys
        XCTAssertFalse(content.body.isEmpty)
    }
}
