//
//  HydrationSnapshotStoreTests.swift
//  GlassWaterTests
//
//  Tests for HydrationSnapshotStore implementations:
//  InMemoryHydrationSnapshotStore and AppGroupHydrationSnapshotStore.
//

import XCTest

@testable import GlassWater

final class HydrationSnapshotStoreTests: XCTestCase {

    private func makeSnapshot(
        totalMl: Int = 500,
        goalMl: Int = 2500,
        source: HydrationSnapshotSource = .app
    ) -> HydrationSnapshot {
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: .now)
        return HydrationSnapshot(
            updatedAt: .now,
            dayStart: dayStart,
            totalMl: totalMl,
            goalMl: goalMl,
            progress: goalMl > 0 ? min(Double(totalMl) / Double(goalMl), 1) : 0,
            remainingMl: max(goalMl - totalMl, 0),
            goalReached: goalMl > 0 && totalMl >= goalMl,
            lastIntakeMl: 250,
            lastIntakeDate: .now,
            customAmountMl: 250,
            source: source
        )
    }

    // MARK: - InMemoryHydrationSnapshotStore

    func testInMemoryStoreInitiallyNil() {
        let store = InMemoryHydrationSnapshotStore()
        XCTAssertNil(store.load())
    }

    func testInMemoryStoreSaveAndLoad() {
        let store = InMemoryHydrationSnapshotStore()
        let snapshot = makeSnapshot(totalMl: 1234)

        store.save(snapshot)

        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.totalMl, 1234)
    }

    func testInMemoryStoreOverwritesPrevious() {
        let store = InMemoryHydrationSnapshotStore()

        store.save(makeSnapshot(totalMl: 100))
        store.save(makeSnapshot(totalMl: 999))

        XCTAssertEqual(store.load()?.totalMl, 999)
    }

    func testInMemoryStorePreservesAllFields() {
        let store = InMemoryHydrationSnapshotStore()
        let snapshot = makeSnapshot(totalMl: 500, goalMl: 2500, source: .widget)

        store.save(snapshot)
        let loaded = store.load()!

        XCTAssertEqual(loaded.totalMl, snapshot.totalMl)
        XCTAssertEqual(loaded.goalMl, snapshot.goalMl)
        XCTAssertEqual(loaded.progress, snapshot.progress)
        XCTAssertEqual(loaded.remainingMl, snapshot.remainingMl)
        XCTAssertEqual(loaded.goalReached, snapshot.goalReached)
        XCTAssertEqual(loaded.lastIntakeMl, snapshot.lastIntakeMl)
        XCTAssertEqual(loaded.customAmountMl, snapshot.customAmountMl)
        XCTAssertEqual(loaded.source, .widget)
    }

    // MARK: - AppGroupHydrationSnapshotStore

    func testAppGroupStoreRoundTrip() {
        // Use a test-specific suite to avoid polluting real app group
        let testSuiteId = "com.glasswater.test.\(UUID().uuidString)"
        let store = AppGroupHydrationSnapshotStore(appGroupIdentifier: testSuiteId)

        let snapshot = makeSnapshot(totalMl: 750, source: .liveActivity)
        store.save(snapshot)

        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.totalMl, 750)
        XCTAssertEqual(loaded?.source, .liveActivity)

        // Cleanup
        UserDefaults(suiteName: testSuiteId)?.removePersistentDomain(forName: testSuiteId)
    }

    func testAppGroupStoreOverwrites() {
        let testSuiteId = "com.glasswater.test.\(UUID().uuidString)"
        let store = AppGroupHydrationSnapshotStore(appGroupIdentifier: testSuiteId)

        store.save(makeSnapshot(totalMl: 100))
        store.save(makeSnapshot(totalMl: 800))

        XCTAssertEqual(store.load()?.totalMl, 800)

        UserDefaults(suiteName: testSuiteId)?.removePersistentDomain(forName: testSuiteId)
    }

    func testAppGroupStoreEmptyReturnsNil() {
        let testSuiteId = "com.glasswater.test.\(UUID().uuidString)"
        let store = AppGroupHydrationSnapshotStore(appGroupIdentifier: testSuiteId)

        XCTAssertNil(store.load())

        UserDefaults(suiteName: testSuiteId)?.removePersistentDomain(forName: testSuiteId)
    }

    func testAppGroupStorePreservesGoalReached() {
        let testSuiteId = "com.glasswater.test.\(UUID().uuidString)"
        let store = AppGroupHydrationSnapshotStore(appGroupIdentifier: testSuiteId)

        let snapshot = makeSnapshot(totalMl: 3000, goalMl: 2500)
        store.save(snapshot)

        let loaded = store.load()
        XCTAssertTrue(loaded?.goalReached ?? false)
        XCTAssertEqual(loaded?.progress, 1.0)

        UserDefaults(suiteName: testSuiteId)?.removePersistentDomain(forName: testSuiteId)
    }

    // MARK: - Snapshot Encoding Stability

    func testSnapshotEncodeDecode() throws {
        let snapshot = makeSnapshot(totalMl: 1500, goalMl: 2500, source: .watch)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(HydrationSnapshot.self, from: data)

        XCTAssertEqual(decoded.totalMl, 1500)
        XCTAssertEqual(decoded.goalMl, 2500)
        XCTAssertEqual(decoded.source, .watch)
        XCTAssertEqual(decoded.customAmountMl, 250)
    }

    func testSnapshotAllSourcesEncodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for source in HydrationSnapshotSource.allCases {
            let snapshot = makeSnapshot(source: source)
            let data = try encoder.encode(snapshot)
            let decoded = try decoder.decode(HydrationSnapshot.self, from: data)
            XCTAssertEqual(decoded.source, source, "Round-trip failed for source=\(source)")
        }
    }
}
