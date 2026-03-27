//
//  BroadcastDebounceTests.swift
//  GlassWaterTests
//
//  Tests for the broadcastCurrentSnapshot debounce mechanism in AppServices.
//  Verifies that rapid broadcast calls are coalesced to prevent redundant work.
//

import XCTest

@testable import GlassWater

@MainActor
final class BroadcastDebounceTests: XCTestCase {
    private var builder: TestServicesBuilder!

    override func setUp() async throws {
        builder = TestServicesBuilder()
        AppServices.lastBroadcastRequestDate = nil
    }

    override func tearDown() {
        AppServices.lastBroadcastRequestDate = nil
        builder = nil
        super.tearDown()
    }

    func testFirstBroadcastGoesThrough() async {
        let services = builder.services

        await services.broadcastCurrentSnapshot()

        XCTAssertEqual(builder.broadcaster.broadcastCallCount, 1,
                       "First broadcast should go through without debounce")
    }

    func testRapidBroadcastsAreDebounced() async {
        let services = builder.services

        await services.broadcastCurrentSnapshot()
        await services.broadcastCurrentSnapshot()
        await services.broadcastCurrentSnapshot()

        XCTAssertEqual(builder.broadcaster.broadcastCallCount, 1,
                       "Rapid successive broadcasts should be debounced to 1")
    }

    func testBroadcastAfterDebounceWindowGoesThrough() async {
        let services = builder.services

        await services.broadcastCurrentSnapshot()
        XCTAssertEqual(builder.broadcaster.broadcastCallCount, 1)

        // Wait for debounce window (0.3s) to expire — use 2x margin for CI reliability
        try? await Task.sleep(for: .milliseconds(600))

        await services.broadcastCurrentSnapshot()
        XCTAssertEqual(builder.broadcaster.broadcastCallCount, 2,
                       "Broadcast after debounce window should go through")
    }
}
