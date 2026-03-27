//
//  GlassWaterErrorTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import XCTest

@testable import GlassWater

final class GlassWaterErrorTests: XCTestCase {

    // MARK: - Error Descriptions

    func testPersistenceFailedHasDescription() {
        let error = GlassWaterError.persistenceFailed(
            operation: "save",
            underlying: NSError(domain: "test", code: 1)
        )
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("save"))
    }

    func testHealthKitUnavailableHasDescription() {
        let error = GlassWaterError.healthKitUnavailable
        XCTAssertNotNil(error.errorDescription)
    }

    func testHealthKitAuthorizationDeniedHasDescription() {
        let error = GlassWaterError.healthKitAuthorizationDenied
        XCTAssertNotNil(error.errorDescription)
    }

    func testInvalidAmountIncludesValue() {
        let error = GlassWaterError.invalidAmount(-50)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("-50"))
    }

    func testInvalidGoalIncludesValue() {
        let error = GlassWaterError.invalidGoal(999999)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("999999"))
    }

    // MARK: - Underlying Error

    func testPersistenceFailedHasUnderlyingError() {
        let underlying = NSError(domain: "test", code: 42)
        let error = GlassWaterError.persistenceFailed(operation: "fetch", underlying: underlying)
        XCTAssertNotNil(error.underlyingError)
        XCTAssertEqual((error.underlyingError! as NSError).code, 42)
    }

    func testHealthKitSyncFailedHasUnderlyingError() {
        let underlying = NSError(domain: "HK", code: 5)
        let error = GlassWaterError.healthKitSyncFailed(underlying: underlying)
        XCTAssertNotNil(error.underlyingError)
    }

    func testNotificationSchedulingFailedHasUnderlyingError() {
        let underlying = NSError(domain: "UN", code: 3)
        let error = GlassWaterError.notificationSchedulingFailed(underlying: underlying)
        XCTAssertNotNil(error.underlyingError)
    }

    func testSimpleErrorsHaveNoUnderlyingError() {
        XCTAssertNil(GlassWaterError.healthKitUnavailable.underlyingError)
        XCTAssertNil(GlassWaterError.healthKitAuthorizationDenied.underlyingError)
        XCTAssertNil(GlassWaterError.snapshotEncodingFailed.underlyingError)
        XCTAssertNil(GlassWaterError.snapshotDecodingFailed.underlyingError)
        XCTAssertNil(GlassWaterError.invalidAmount(100).underlyingError)
        XCTAssertNil(GlassWaterError.invalidGoal(2000).underlyingError)
    }

    // MARK: - LocalizedError Conformance

    func testConformsToLocalizedError() {
        let error: LocalizedError = GlassWaterError.healthKitUnavailable
        XCTAssertNotNil(error.errorDescription)
    }

    func testAllCasesHaveNonEmptyDescription() {
        let cases: [GlassWaterError] = [
            .persistenceFailed(operation: "test", underlying: NSError(domain: "", code: 0)),
            .healthKitUnavailable,
            .healthKitAuthorizationDenied,
            .healthKitSyncFailed(underlying: NSError(domain: "", code: 0)),
            .notificationSchedulingFailed(underlying: NSError(domain: "", code: 0)),
            .snapshotEncodingFailed,
            .snapshotDecodingFailed,
            .invalidAmount(0),
            .invalidGoal(0),
        ]

        for error in cases {
            XCTAssertFalse(
                error.errorDescription?.isEmpty ?? true,
                "\(error) has empty description"
            )
        }
    }
}
