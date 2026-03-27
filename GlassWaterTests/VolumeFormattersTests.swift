//
//  VolumeFormattersTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import XCTest

@testable import GlassWater

final class VolumeFormattersTests: XCTestCase {

    // MARK: - Milliliters

    func testFormatMillilitersBelow1000() {
        let result = VolumeFormatters.string(fromMl: 500, unitStyle: .short)
        XCTAssertFalse(result.isEmpty)
        // Should contain "500" and some unit indicator
        XCTAssertTrue(result.contains("500"))
    }

    func testFormatZeroMl() {
        let result = VolumeFormatters.string(fromMl: 0, unitStyle: .short)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("0"))
    }

    // MARK: - Liters

    func testFormatLitersAt1000() {
        let result = VolumeFormatters.string(fromMl: 1000, unitStyle: .short)
        XCTAssertFalse(result.isEmpty)
        // Should format as 1 L or similar
        XCTAssertTrue(result.contains("1"))
    }

    func testFormatLitersAt2500() {
        let result = VolumeFormatters.string(fromMl: 2500, unitStyle: .short)
        XCTAssertFalse(result.isEmpty)
        // Should format as 2.5 L or similar
        XCTAssertTrue(result.contains("2.5") || result.contains("2,5"))
    }

    // MARK: - Unit Styles

    func testShortStyleProducesOutput() {
        let result = VolumeFormatters.string(fromMl: 250, unitStyle: .short)
        XCTAssertFalse(result.isEmpty)
    }

    func testMediumStyleProducesOutput() {
        let result = VolumeFormatters.string(fromMl: 250, unitStyle: .medium)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Consistency

    func testSameInputProducesSameOutput() {
        let a = VolumeFormatters.string(fromMl: 750, unitStyle: .short)
        let b = VolumeFormatters.string(fromMl: 750, unitStyle: .short)
        XCTAssertEqual(a, b)
    }

    func testLargerAmountProducesLargerUnit() {
        let small = VolumeFormatters.string(fromMl: 500, unitStyle: .short)
        let large = VolumeFormatters.string(fromMl: 2000, unitStyle: .short)
        // Both should be non-empty and different
        XCTAssertNotEqual(small, large)
    }

    // MARK: - Unit Conversion

    func testMlFromFluidOunces() {
        let ml = VolumeFormatters.ml(fromFluidOunces: 1.0)
        // 1 fl oz ≈ 29.5735 ml
        XCTAssertEqual(ml, 30, accuracy: 1) // rounded
    }

    func testMlFromFluidOuncesZero() {
        let ml = VolumeFormatters.ml(fromFluidOunces: 0)
        XCTAssertEqual(ml, 0)
    }

    func testMlFromFluidOuncesLarge() {
        let ml = VolumeFormatters.ml(fromFluidOunces: 8.0) // 1 cup
        // 8 fl oz ≈ 236.588 ml
        XCTAssertEqual(ml, 237, accuracy: 1)
    }

    func testMlFromFluidOuncesHalf() {
        let ml = VolumeFormatters.ml(fromFluidOunces: 0.5)
        // 0.5 fl oz ≈ 14.79 ml
        XCTAssertEqual(ml, 15, accuracy: 1)
    }

    // MARK: - VolumeUnit

    func testVolumeUnitMlResolvesToMl() {
        XCTAssertEqual(VolumeUnit.ml.resolved, .ml)
    }

    func testVolumeUnitOzResolvesToOz() {
        XCTAssertEqual(VolumeUnit.oz.resolved, .oz)
    }

    func testVolumeUnitAutoResolves() {
        // auto resolves based on locale — just verify it doesn't crash
        let resolved = VolumeUnit.auto.resolved
        XCTAssertTrue(resolved == .ml || resolved == .oz)
    }

    func testVolumeUnitRawValues() {
        XCTAssertEqual(VolumeUnit.auto.rawValue, "auto")
        XCTAssertEqual(VolumeUnit.ml.rawValue, "ml")
        XCTAssertEqual(VolumeUnit.oz.rawValue, "oz")
    }

    func testVolumeUnitAllCases() {
        XCTAssertEqual(VolumeUnit.allCases.count, 3)
    }

    // MARK: - Edge Cases

    func testFormatNegativeMl() {
        let result = VolumeFormatters.string(fromMl: -100, unitStyle: .short)
        XCTAssertFalse(result.isEmpty, "Should handle negative values without crashing")
    }

    func testFormatVeryLargeMl() {
        let result = VolumeFormatters.string(fromMl: 99999, unitStyle: .short)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Conversion Round Trip

    func testFluidOunceRoundTrip() {
        // Convert ml → oz → ml should be close to original
        let originalMl = 500
        let oz = Double(originalMl) / 29.5735
        let backToMl = VolumeFormatters.ml(fromFluidOunces: oz)
        XCTAssertEqual(backToMl, originalMl, accuracy: 1, "Round trip should preserve value within 1ml")
    }
}
