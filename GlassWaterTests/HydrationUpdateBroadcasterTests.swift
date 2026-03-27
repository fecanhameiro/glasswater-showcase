//
//  HydrationUpdateBroadcasterTests.swift
//  GlassWaterTests
//
//  Tests for HydrationUpdateBroadcaster — throttling, LA updates,
//  and watch state skipping for echo prevention.
//

import XCTest

@testable import GlassWater

@MainActor
final class HydrationUpdateBroadcasterTests: XCTestCase {
    private var snapshotStore: InMemoryHydrationSnapshotStore!
    private var settingsStore: MockSettingsStore!
    private var liveActivity: MockLiveActivityService!
    private var phoneConnectivity: MockPhoneConnectivityService!
    private var broadcaster: HydrationUpdateBroadcaster!

    override func setUp() async throws {
        snapshotStore = InMemoryHydrationSnapshotStore()
        settingsStore = MockSettingsStore()
        settingsStore.settings.hasCompletedOnboarding = true
        settingsStore.settings.liveActivitiesEnabled = true
        liveActivity = MockLiveActivityService()
        phoneConnectivity = MockPhoneConnectivityService()
        broadcaster = HydrationUpdateBroadcaster(
            snapshotStore: snapshotStore,
            settingsStore: settingsStore,
            liveActivity: liveActivity,
            phoneConnectivity: phoneConnectivity,
            minimumInterval: 0.1 // Short interval for tests
        )
    }

    private func makeSnapshot(totalMl: Int = 500, source: HydrationSnapshotSource = .app) -> HydrationSnapshot {
        HydrationSnapshot(
            updatedAt: .now,
            dayStart: Calendar.autoupdatingCurrent.startOfDay(for: .now),
            totalMl: totalMl,
            goalMl: 2500,
            progress: Double(totalMl) / 2500.0,
            remainingMl: max(2500 - totalMl, 0),
            goalReached: totalMl >= 2500,
            lastIntakeMl: 250,
            lastIntakeDate: .now,
            customAmountMl: 250,
            source: source
        )
    }

    // MARK: - First Broadcast

    func testFirstBroadcastGoesThrough() async {
        let snapshot = makeSnapshot()
        await broadcaster.broadcast(snapshot: snapshot)

        XCTAssertEqual(liveActivity.updateCallCount, 1)
        XCTAssertNotNil(snapshotStore.load())
        XCTAssertEqual(snapshotStore.load()?.totalMl, 500)
    }

    // MARK: - Throttling

    func testSecondBroadcastWithinIntervalIsThrottled() async {
        let snapshot1 = makeSnapshot(totalMl: 500)
        let snapshot2 = makeSnapshot(totalMl: 750)

        await broadcaster.broadcast(snapshot: snapshot1)
        XCTAssertEqual(liveActivity.updateCallCount, 1)

        // Immediately send second — should be throttled
        await broadcaster.broadcast(snapshot: snapshot2)
        XCTAssertEqual(liveActivity.updateCallCount, 1, "Second broadcast within interval should be throttled")
    }

    func testThrottledBroadcastEventuallyFlushes() async {
        let snapshot1 = makeSnapshot(totalMl: 500)
        let snapshot2 = makeSnapshot(totalMl: 750)

        await broadcaster.broadcast(snapshot: snapshot1)
        await broadcaster.broadcast(snapshot: snapshot2)

        // Wait for throttle to flush (interval is 0.1s, use 5x margin for CI stability)
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(liveActivity.updateCallCount, 2, "Throttled broadcast should eventually flush")
        XCTAssertEqual(snapshotStore.load()?.totalMl, 750, "Should have the latest snapshot")
    }

    // MARK: - LA Disabled Path

    func testLiveActivityDisabledCallsEnd() async {
        settingsStore.settings.liveActivitiesEnabled = false

        let snapshot = makeSnapshot()
        await broadcaster.broadcast(snapshot: snapshot)

        XCTAssertEqual(liveActivity.endCallCount, 1)
        XCTAssertEqual(liveActivity.updateCallCount, 0)
    }

    func testOnboardingNotCompletedCallsEnd() async {
        settingsStore.settings.hasCompletedOnboarding = false

        let snapshot = makeSnapshot()
        await broadcaster.broadcast(snapshot: snapshot)

        XCTAssertEqual(liveActivity.endCallCount, 1)
        XCTAssertEqual(liveActivity.updateCallCount, 0)
    }

    // MARK: - Watch Echo Prevention

    func testWatchSourceSkipsWatchSend() async {
        broadcaster.watchStateBuilder = {
            WatchState(
                updatedAt: .now,
                dayStart: Calendar.autoupdatingCurrent.startOfDay(for: .now),
                totalMl: 500, goalMl: 2500, progress: 0.2, remainingMl: 2000,
                goalReached: false, customAmountMl: 250, volumeUnit: "ml",
                entries: [], processedCommandIds: []
            )
        }

        let snapshot = makeSnapshot(source: .watch)
        await broadcaster.broadcast(snapshot: snapshot)

        XCTAssertEqual(phoneConnectivity.sendStateCallCount, 0, "Should NOT send to watch when source is .watch")
    }

    func testNonWatchSourceSendsWatchState() async {
        broadcaster.watchStateBuilder = {
            WatchState(
                updatedAt: .now,
                dayStart: Calendar.autoupdatingCurrent.startOfDay(for: .now),
                totalMl: 500, goalMl: 2500, progress: 0.2, remainingMl: 2000,
                goalReached: false, customAmountMl: 250, volumeUnit: "ml",
                entries: [], processedCommandIds: []
            )
        }

        let snapshot = makeSnapshot(source: .app)
        await broadcaster.broadcast(snapshot: snapshot)

        XCTAssertEqual(phoneConnectivity.sendStateCallCount, 1, "Should send to watch when source is not .watch")
    }

    // MARK: - Snapshot Persistence

    func testBroadcastSavesSnapshot() async {
        XCTAssertNil(snapshotStore.load())

        let snapshot = makeSnapshot(totalMl: 1234)
        await broadcaster.broadcast(snapshot: snapshot)

        let saved = snapshotStore.load()
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.totalMl, 1234)
    }
}
