//
//  QuickAddOptionsTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import XCTest

@testable import GlassWater

final class QuickAddOptionsTests: XCTestCase {

    // MARK: - Options Generation

    func testOptionsReturnsCorrectCount() {
        let options = QuickAddOptions.options(forGoalMl: 2500)
        XCTAssertEqual(options.count, AppConstants.quickAddPercents.count)
    }

    func testOptionsHaveCorrectPercents() {
        let options = QuickAddOptions.options(forGoalMl: 2500)
        let percents = options.map(\.percent)
        XCTAssertEqual(percents, AppConstants.quickAddPercents)
    }

    // MARK: - Amount Calculation

    func testAmountFor10PercentOf2500() {
        let amount = QuickAddOptions.amount(forPercent: 10, goalMl: 2500)
        XCTAssertEqual(amount, 250) // 2500 * 0.10 = 250
    }

    func testAmountFor15PercentOf2500() {
        let amount = QuickAddOptions.amount(forPercent: 15, goalMl: 2500)
        XCTAssertEqual(amount, 400) // 2500 * 0.15 = 375, rounded to step 50 = 400
    }

    func testAmountFor25PercentOf2500() {
        let amount = QuickAddOptions.amount(forPercent: 25, goalMl: 2500)
        XCTAssertEqual(amount, 650) // 2500 * 0.25 = 625, rounded to step 50 = 650
    }

    func testAmountClampsToMinimum() {
        let amount = QuickAddOptions.amount(forPercent: 1, goalMl: 1000)
        // 1000 * 0.01 = 10, rounded = 0, clamped to minimum 100
        XCTAssertEqual(amount, AppConstants.quickAddMinMl)
    }

    func testAmountClampsToMaximum() {
        let amount = QuickAddOptions.amount(forPercent: 100, goalMl: 5000)
        // 5000 * 1.0 = 5000, clamped to maximum 1000
        XCTAssertEqual(amount, AppConstants.quickAddMaxMl)
    }

    func testAmountRoundsToStep() {
        // Goal 2000, 10% = 200, already on step 50 boundary
        let amount = QuickAddOptions.amount(forPercent: 10, goalMl: 2000)
        XCTAssertEqual(amount % AppConstants.quickAddStepMl, 0)
    }

    // MARK: - Custom Amount Clamping

    func testClampCustomAmountWithinRange() {
        let clamped = QuickAddOptions.clampCustomAmount(300)
        XCTAssertEqual(clamped, 300)
    }

    func testClampCustomAmountBelowMinimum() {
        let clamped = QuickAddOptions.clampCustomAmount(10)
        XCTAssertEqual(clamped, AppConstants.customAmountMinMl)
    }

    func testClampCustomAmountAboveMaximum() {
        let clamped = QuickAddOptions.clampCustomAmount(5000)
        XCTAssertEqual(clamped, AppConstants.customAmountMaxMl)
    }

    func testClampCustomAmountRoundsToStep() {
        let clamped = QuickAddOptions.clampCustomAmount(273)
        XCTAssertEqual(clamped % AppConstants.customAmountStepMl, 0)
    }

    // MARK: - Custom Amounts List

    func testCustomAmountsStartsAtMinimum() {
        let amounts = QuickAddOptions.customAmounts()
        XCTAssertEqual(amounts.first, AppConstants.customAmountMinMl)
    }

    func testCustomAmountsEndsAtMaximum() {
        let amounts = QuickAddOptions.customAmounts()
        XCTAssertEqual(amounts.last, AppConstants.customAmountMaxMl)
    }

    func testCustomAmountsAreInSteps() {
        let amounts = QuickAddOptions.customAmounts()
        for i in 1..<amounts.count {
            XCTAssertEqual(
                amounts[i] - amounts[i - 1],
                AppConstants.customAmountStepMl,
                "Step between \(amounts[i - 1]) and \(amounts[i]) is not \(AppConstants.customAmountStepMl)"
            )
        }
    }

    // MARK: - Resolved Custom Amount

    func testResolvedCustomAmountWithExistingValue() {
        let resolved = QuickAddOptions.resolvedCustomAmount(forGoalMl: 2500, customAmountMl: 350)
        XCTAssertEqual(resolved, 350)
    }

    func testResolvedCustomAmountWithNilFallsBackToPercent() {
        let resolved = QuickAddOptions.resolvedCustomAmount(forGoalMl: 2500, customAmountMl: nil)
        XCTAssertGreaterThanOrEqual(resolved, AppConstants.customAmountMinMl)
        XCTAssertLessThanOrEqual(resolved, AppConstants.customAmountMaxMl)
    }

    // MARK: - Live Activity Options

    func testLiveActivityOptionsHasTwoItems() {
        let options = QuickAddOptions.liveActivityOptions(forGoalMl: 2500, customAmountMl: 300)
        // 2 items: quick (10% of goal) + custom (300ml) — custom != quick so both appear
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options.first?.id, "quick")
        XCTAssertEqual(options.last?.id, "custom")
    }

    func testLiveActivityOptionsLastItemIsCustom() {
        let options = QuickAddOptions.liveActivityOptions(forGoalMl: 2500, customAmountMl: 300)
        XCTAssertEqual(options.last?.id, "custom")
        XCTAssertEqual(options.last?.amountMl, 300)
    }

    // MARK: - Custom Percents

    func testOptionsWithCustomPercents() {
        let options = QuickAddOptions.options(forGoalMl: 2500, percents: [5, 20, 50])
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options.map(\.percent), [5, 20, 50])
    }

    func testOptionsWithEmptyPercentsUsesDefaults() {
        let options = QuickAddOptions.options(forGoalMl: 2500, percents: [])
        XCTAssertEqual(options.count, AppConstants.quickAddPercents.count)
    }

    func testOptionsWithDuplicatePercentsDeduplicates() {
        let options = QuickAddOptions.options(forGoalMl: 2500, percents: [10, 10, 25])
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options.map(\.percent), [10, 25])
    }
}
