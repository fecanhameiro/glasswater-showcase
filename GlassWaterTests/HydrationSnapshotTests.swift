//
//  HydrationSnapshotTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import XCTest

@testable import GlassWater

final class HydrationSnapshotTests: XCTestCase {

    // MARK: - Codable Conformance

    func testSnapshotEncodesAndDecodes() throws {
        let snapshot = HydrationSnapshot(
            updatedAt: .now,
            dayStart: Calendar.current.startOfDay(for: .now),
            totalMl: 1500,
            goalMl: 2500,
            progress: 0.6,
            remainingMl: 1000,
            goalReached: false,
            lastIntakeMl: 250,
            lastIntakeDate: .now,
            customAmountMl: 300,
            source: .app
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(HydrationSnapshot.self, from: data)

        XCTAssertEqual(decoded.totalMl, 1500)
        XCTAssertEqual(decoded.goalMl, 2500)
        XCTAssertEqual(decoded.progress, 0.6)
        XCTAssertEqual(decoded.remainingMl, 1000)
        XCTAssertEqual(decoded.goalReached, false)
        XCTAssertEqual(decoded.lastIntakeMl, 250)
        XCTAssertEqual(decoded.customAmountMl, 300)
        XCTAssertEqual(decoded.source, .app)
    }

    func testSnapshotWithNilOptionals() throws {
        let snapshot = HydrationSnapshot(
            updatedAt: .now,
            dayStart: Calendar.current.startOfDay(for: .now),
            totalMl: 0,
            goalMl: 2500,
            progress: 0,
            remainingMl: 2500,
            goalReached: false,
            lastIntakeMl: nil,
            lastIntakeDate: nil,
            customAmountMl: 250,
            source: .widget
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(HydrationSnapshot.self, from: data)

        XCTAssertNil(decoded.lastIntakeMl)
        XCTAssertNil(decoded.lastIntakeDate)
        XCTAssertEqual(decoded.source, .widget)
    }

    // MARK: - Equatable

    func testSnapshotEquality() {
        let date = Date.now
        let dayStart = Calendar.current.startOfDay(for: date)

        let a = HydrationSnapshot(
            updatedAt: date, dayStart: dayStart, totalMl: 1000, goalMl: 2500,
            progress: 0.4, remainingMl: 1500, goalReached: false,
            lastIntakeMl: 200, lastIntakeDate: date, customAmountMl: 250, source: .app
        )
        let b = HydrationSnapshot(
            updatedAt: date, dayStart: dayStart, totalMl: 1000, goalMl: 2500,
            progress: 0.4, remainingMl: 1500, goalReached: false,
            lastIntakeMl: 200, lastIntakeDate: date, customAmountMl: 250, source: .app
        )

        XCTAssertEqual(a, b)
    }

    func testSnapshotInequalityOnDifferentTotal() {
        let date = Date.now
        let dayStart = Calendar.current.startOfDay(for: date)

        let a = HydrationSnapshot(
            updatedAt: date, dayStart: dayStart, totalMl: 1000, goalMl: 2500,
            progress: 0.4, remainingMl: 1500, goalReached: false,
            lastIntakeMl: nil, lastIntakeDate: nil, customAmountMl: 250, source: .app
        )
        let b = HydrationSnapshot(
            updatedAt: date, dayStart: dayStart, totalMl: 2000, goalMl: 2500,
            progress: 0.8, remainingMl: 500, goalReached: false,
            lastIntakeMl: nil, lastIntakeDate: nil, customAmountMl: 250, source: .app
        )

        XCTAssertNotEqual(a, b)
    }

    // MARK: - Source Enum

    func testAllSourceCasesExist() {
        let allCases = HydrationSnapshotSource.allCases
        XCTAssertTrue(allCases.contains(.app))
        XCTAssertTrue(allCases.contains(.widget))
        XCTAssertTrue(allCases.contains(.liveActivity))
        XCTAssertTrue(allCases.contains(.watch))
        XCTAssertTrue(allCases.contains(.notification))
        XCTAssertTrue(allCases.contains(.background))
        XCTAssertTrue(allCases.contains(.health))
        XCTAssertTrue(allCases.contains(.unknown))
    }

    func testSourceRawValueRoundTrips() throws {
        for source in HydrationSnapshotSource.allCases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(HydrationSnapshotSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }
}
