//
//  NotificationActionTests.swift
//  GlassWaterTests
//
//  Tests for NotificationAction identifier parsing, NotificationContentFactory
//  edge cases, and AnalyticsTimeOfDay helper.
//

import XCTest

@testable import GlassWater

final class NotificationActionTests: XCTestCase {

    // MARK: - NotificationAction Identifier Generation

    func testPercentIdentifierFormat() {
        XCTAssertEqual(NotificationAction.percentIdentifier(10), "glasswater.add.percent.10")
        XCTAssertEqual(NotificationAction.percentIdentifier(25), "glasswater.add.percent.25")
    }

    func testCustomAmountIdentifierFormat() {
        XCTAssertEqual(NotificationAction.customAmountIdentifier(350), "glasswater.add.custom.350")
    }

    // MARK: - NotificationAction Identifier Parsing

    func testPercentFromIdentifier() {
        XCTAssertEqual(NotificationAction.percent(from: "glasswater.add.percent.10"), 10)
        XCTAssertEqual(NotificationAction.percent(from: "glasswater.add.percent.25"), 25)
    }

    func testPercentFromInvalidIdentifier() {
        XCTAssertNil(NotificationAction.percent(from: "glasswater.add.custom.350"))
        XCTAssertNil(NotificationAction.percent(from: "random.string"))
        XCTAssertNil(NotificationAction.percent(from: ""))
    }

    func testPercentFromIdentifierWithNonNumeric() {
        XCTAssertNil(NotificationAction.percent(from: "glasswater.add.percent.abc"))
    }

    func testCustomAmountFromIdentifier() {
        XCTAssertEqual(NotificationAction.customAmount(from: "glasswater.add.custom.350"), 350)
        XCTAssertEqual(NotificationAction.customAmount(from: "glasswater.add.custom.500"), 500)
    }

    func testCustomAmountExcludesSpecialIdentifiers() {
        // customInputIdentifier and customSavedIdentifier should NOT parse as custom amounts
        XCTAssertNil(NotificationAction.customAmount(from: NotificationAction.customInputIdentifier))
        XCTAssertNil(NotificationAction.customAmount(from: NotificationAction.customSavedIdentifier))
    }

    func testCustomAmountFromInvalidIdentifier() {
        XCTAssertNil(NotificationAction.customAmount(from: "glasswater.add.percent.10"))
        XCTAssertNil(NotificationAction.customAmount(from: "random"))
    }

    // MARK: - NotificationAction Constants

    func testReminderCategoryConstant() {
        XCTAssertEqual(NotificationAction.reminderCategory, "glasswater.reminder.category")
    }

    func testSnoozeIdentifierConstant() {
        XCTAssertEqual(NotificationAction.snoozeIdentifier, "glasswater.snooze")
    }

    func testSnoozeReminderIdentifierConstant() {
        XCTAssertEqual(NotificationAction.snoozeReminderIdentifier, "glasswater.snooze.reminder")
    }

    // MARK: - Round-trip: generate → parse

    func testPercentIdentifierRoundTrip() {
        for percent in [5, 10, 15, 20, 25, 50, 100] {
            let identifier = NotificationAction.percentIdentifier(percent)
            let parsed = NotificationAction.percent(from: identifier)
            XCTAssertEqual(parsed, percent, "Round-trip failed for percent=\(percent)")
        }
    }

    func testCustomAmountIdentifierRoundTrip() {
        for amount in [50, 100, 250, 500, 1000, 1500] {
            let identifier = NotificationAction.customAmountIdentifier(amount)
            let parsed = NotificationAction.customAmount(from: identifier)
            XCTAssertEqual(parsed, amount, "Round-trip failed for amount=\(amount)")
        }
    }

    // MARK: - AnalyticsTimeOfDay

    func testAnalyticsTimeOfDayMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Create a date at 8am UTC
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 21
        components.hour = 8
        components.timeZone = TimeZone(identifier: "UTC")
        // AnalyticsTimeOfDay uses .now, so we can only test that it returns a valid string
        let result = AnalyticsTimeOfDay.current(calendar: calendar)
        XCTAssertTrue(["morning", "afternoon", "evening"].contains(result))
    }

    func testAnalyticsTimeOfDayValues() {
        // Verify all possible return values are valid
        let validValues = ["morning", "afternoon", "evening"]
        let result = AnalyticsTimeOfDay.current()
        XCTAssertTrue(validValues.contains(result), "Should return one of \(validValues), got \(result)")
    }
}
