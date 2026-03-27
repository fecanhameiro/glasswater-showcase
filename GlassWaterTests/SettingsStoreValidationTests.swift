//
//  SwiftDataSettingsStoreTests.swift
//  GlassWaterTests
//
//  Tests for SwiftDataSettingsStore: validation, clamping, caching,
//  and AppGroup sync.
//

import SwiftData
import XCTest

@testable import GlassWater

@MainActor
final class SettingsStoreValidationTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SwiftDataSettingsStore!

    override func setUp() async throws {
        let schema = Schema([WaterEntry.self, UserSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        store = SwiftDataSettingsStore(modelContext: container.mainContext)
    }

    // MARK: - Load or Create

    func testLoadOrCreateReturnsDefaultSettings() throws {
        let settings = try store.loadOrCreate()

        XCTAssertEqual(settings.dailyGoalMl, AppConstants.defaultDailyGoalMl)
        XCTAssertFalse(settings.notificationsEnabled)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertEqual(settings.reminderStartMinutes, AppConstants.defaultReminderStartMinutes)
        XCTAssertEqual(settings.reminderEndMinutes, AppConstants.defaultReminderEndMinutes)
        XCTAssertEqual(settings.reminderIntervalMinutes, AppConstants.defaultReminderIntervalMinutes)
    }

    func testLoadOrCreateReturnsCachedInstance() throws {
        let first = try store.loadOrCreate()
        let second = try store.loadOrCreate()

        XCTAssertTrue(first === second, "Should return the same cached instance")
    }

    func testLoadOrCreateReturnsExistingAfterSave() throws {
        let settings = try store.loadOrCreate()
        settings.dailyGoalMl = 3000
        try store.save()

        // Invalidate cache and reload
        store.invalidateCache()
        let reloaded = try store.loadOrCreate()

        XCTAssertEqual(reloaded.dailyGoalMl, 3000)
    }

    // MARK: - Validation & Clamping

    func testClampsDailyGoalBelowMinimum() throws {
        let settings = try store.loadOrCreate()
        settings.dailyGoalMl = 100 // Below minimum of 1000
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.dailyGoalMl, AppConstants.minDailyGoalMl)
    }

    func testClampsDailyGoalAboveMaximum() throws {
        let settings = try store.loadOrCreate()
        settings.dailyGoalMl = 99999 // Above maximum of 5000
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.dailyGoalMl, AppConstants.maxDailyGoalMl)
    }

    func testClampsReminderStartMinutesNegative() throws {
        let settings = try store.loadOrCreate()
        settings.reminderStartMinutes = -100
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.reminderStartMinutes, 0)
    }

    func testClampsReminderEndMinutesAboveMax() throws {
        let settings = try store.loadOrCreate()
        settings.reminderEndMinutes = 2000 // > 1439
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.reminderEndMinutes, 24 * 60 - 1)
    }

    func testClampsReminderIntervalBelowMinimum() throws {
        let settings = try store.loadOrCreate()
        settings.reminderIntervalMinutes = 10 // Below 60
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.reminderIntervalMinutes, 60)
    }

    func testClampsReminderIntervalAboveMaximum() throws {
        let settings = try store.loadOrCreate()
        settings.reminderIntervalMinutes = 500 // Above 240
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.reminderIntervalMinutes, 240)
    }

    func testClampsCustomAmountBelowMinimum() throws {
        let settings = try store.loadOrCreate()
        settings.lastCustomAmountMl = 10 // Below 50
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.lastCustomAmountMl, AppConstants.customAmountMinMl)
    }

    func testClampsCustomAmountAboveMaximum() throws {
        let settings = try store.loadOrCreate()
        settings.lastCustomAmountMl = 9999 // Above 1500
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.lastCustomAmountMl, AppConstants.customAmountMaxMl)
    }

    func testNilCustomAmountStaysNil() throws {
        let settings = try store.loadOrCreate()
        settings.lastCustomAmountMl = nil
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertNil(reloaded.lastCustomAmountMl)
    }

    func testClampsNegativeStreakToZero() throws {
        let settings = try store.loadOrCreate()
        settings.streakCount = -5
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.streakCount, 0)
    }

    // MARK: - Valid Values Pass Through

    func testValidGoalPassesThrough() throws {
        let settings = try store.loadOrCreate()
        settings.dailyGoalMl = 2500
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.dailyGoalMl, 2500)
    }

    func testValidCustomAmountPassesThrough() throws {
        let settings = try store.loadOrCreate()
        settings.lastCustomAmountMl = 350
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.lastCustomAmountMl, 350)
    }

    // MARK: - Cache Invalidation

    func testInvalidateCacheForcesReload() throws {
        let settings = try store.loadOrCreate()
        let originalGoal = settings.dailyGoalMl

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()

        XCTAssertEqual(reloaded.dailyGoalMl, originalGoal)
        // After invalidation, it should re-fetch from SwiftData
    }

    // MARK: - Duck Nicknames

    func testDuckNicknamesRoundTrip() throws {
        let settings = try store.loadOrCreate()
        settings.duckNicknames = [1: "Quackers", 2: "Ducky"]
        try store.save()

        store.invalidateCache()
        let reloaded = try store.loadOrCreate()
        XCTAssertEqual(reloaded.duckNicknames[1], "Quackers")
        XCTAssertEqual(reloaded.duckNicknames[2], "Ducky")
    }

    func testDuckNicknamesEmptyByDefault() throws {
        let settings = try store.loadOrCreate()
        XCTAssertTrue(settings.duckNicknames.isEmpty)
    }
}
