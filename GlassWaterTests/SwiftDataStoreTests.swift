//
//  SwiftDataStoreTests.swift
//  GlassWaterTests
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import SwiftData
import XCTest

@testable import GlassWater

@MainActor
final class SwiftDataWaterStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SwiftDataWaterStore!

    override func setUp() async throws {
        let schema = Schema([WaterEntry.self, UserSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        store = SwiftDataWaterStore(modelContext: container.mainContext)
    }

    // MARK: - Add Entry

    func testAddEntryReturnsEntry() throws {
        let entry = try store.addEntry(amountMl: 250, date: .now, isFromHealth: false, healthSampleId: nil)

        XCTAssertEqual(entry.amountMl, 250)
        XCTAssertFalse(entry.isFromHealth)
        XCTAssertNil(entry.healthSampleId)
    }

    func testAddEntryWithHealthKit() throws {
        let sampleId = UUID()
        let entry = try store.addEntry(amountMl: 300, date: .now, isFromHealth: true, healthSampleId: sampleId)

        XCTAssertTrue(entry.isFromHealth)
        XCTAssertEqual(entry.healthSampleId, sampleId)
    }

    func testAddEntryPersists() throws {
        let date = Date.now
        _ = try store.addEntry(amountMl: 500, date: date, isFromHealth: false, healthSampleId: nil)

        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let entries = try store.entries(from: start, to: end)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.amountMl, 500)
    }

    // MARK: - Fetch Entries

    func testEntriesFiltersByDateRange() throws {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        _ = try store.addEntry(amountMl: 100, date: today.addingTimeInterval(3600), isFromHealth: false, healthSampleId: nil)
        _ = try store.addEntry(amountMl: 200, date: yesterday.addingTimeInterval(3600), isFromHealth: false, healthSampleId: nil)

        let todayEnd = calendar.date(byAdding: .day, value: 1, to: today)!
        let todayEntries = try store.entries(from: today, to: todayEnd)

        XCTAssertEqual(todayEntries.count, 1)
        XCTAssertEqual(todayEntries.first?.amountMl, 100)
    }

    func testEntriesSortedByDate() throws {
        let calendar = Calendar.autoupdatingCurrent
        let noon = calendar.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        _ = try store.addEntry(amountMl: 300, date: noon.addingTimeInterval(-3600), isFromHealth: false, healthSampleId: nil)
        _ = try store.addEntry(amountMl: 100, date: noon.addingTimeInterval(-7200), isFromHealth: false, healthSampleId: nil)
        _ = try store.addEntry(amountMl: 200, date: noon, isFromHealth: false, healthSampleId: nil)

        let start = calendar.startOfDay(for: noon)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let entries = try store.entries(from: start, to: end)

        XCTAssertEqual(entries.map(\.amountMl), [100, 300, 200]) // sorted by date ascending
    }

    // MARK: - Total

    func testTotalForDay() throws {
        let now = Date.now
        _ = try store.addEntry(amountMl: 250, date: now, isFromHealth: false, healthSampleId: nil)
        _ = try store.addEntry(amountMl: 350, date: now.addingTimeInterval(-1800), isFromHealth: false, healthSampleId: nil)

        let total = try store.total(for: now)

        XCTAssertEqual(total, 600)
    }

    func testTotalForDayWithNoEntries() throws {
        let total = try store.total(for: .now)
        XCTAssertEqual(total, 0)
    }

    // MARK: - Latest Entry

    func testLatestEntryReturnsNewest() throws {
        let now = Date.now
        _ = try store.addEntry(amountMl: 100, date: now.addingTimeInterval(-7200), isFromHealth: false, healthSampleId: nil)
        _ = try store.addEntry(amountMl: 500, date: now, isFromHealth: false, healthSampleId: nil)

        let latest = try store.latestEntry()

        XCTAssertEqual(latest?.amountMl, 500)
    }

    func testLatestEntryNilWhenEmpty() throws {
        let latest = try store.latestEntry()
        XCTAssertNil(latest)
    }

    func testLatestEntryDate() throws {
        let now = Date.now
        _ = try store.addEntry(amountMl: 100, date: now, isFromHealth: false, healthSampleId: nil)

        let date = try store.latestEntryDate()
        XCTAssertNotNil(date)
    }

    // MARK: - Update Entry

    func testUpdateEntry() throws {
        let entry = try store.addEntry(amountMl: 200, date: .now, isFromHealth: false, healthSampleId: nil)
        let sampleId = UUID()

        try store.updateEntry(entry, amountMl: 400, date: entry.date, isFromHealth: true, healthSampleId: sampleId)

        XCTAssertEqual(entry.amountMl, 400)
        XCTAssertTrue(entry.isFromHealth)
        XCTAssertEqual(entry.healthSampleId, sampleId)
    }

    // MARK: - Delete Entry

    func testDeleteEntry() throws {
        let entry = try store.addEntry(amountMl: 250, date: .now, isFromHealth: false, healthSampleId: nil)

        try store.deleteEntry(entry)

        let total = try store.total(for: .now)
        XCTAssertEqual(total, 0)
    }

    // MARK: - Entries Missing Health Sample

    func testEntriesMissingHealthSample() throws {
        _ = try store.addEntry(amountMl: 250, date: .now, isFromHealth: false, healthSampleId: nil)
        _ = try store.addEntry(amountMl: 300, date: .now, isFromHealth: true, healthSampleId: UUID())

        let missing = try store.entriesMissingHealthSample()

        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.amountMl, 250)
    }
}

// MARK: - Settings Store Tests

@MainActor
final class SwiftDataSettingsStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SwiftDataSettingsStore!

    override func setUp() async throws {
        let schema = Schema([WaterEntry.self, UserSettings.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        store = SwiftDataSettingsStore(modelContext: container.mainContext)
    }

    // MARK: - Load Or Create

    func testLoadOrCreateReturnsDefaultSettings() throws {
        let settings = try store.loadOrCreate()

        XCTAssertEqual(settings.dailyGoalMl, AppConstants.defaultDailyGoalMl)
        XCTAssertFalse(settings.notificationsEnabled)
        XCTAssertTrue(settings.hapticsEnabled)
    }

    func testLoadOrCreateReturnsSameInstance() throws {
        let first = try store.loadOrCreate()
        let second = try store.loadOrCreate()

        XCTAssertTrue(first === second) // Same reference (cached)
    }

    func testLoadOrCreatePersistsSettings() throws {
        let settings = try store.loadOrCreate()
        settings.dailyGoalMl = 3000

        try store.save()

        // Verify persistence via direct context fetch
        let descriptor = FetchDescriptor<UserSettings>()
        let fetched = try container.mainContext.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.dailyGoalMl, 3000)
    }

    // MARK: - Save Validation

    func testSaveClampsGoalToValidRange() throws {
        let settings = try store.loadOrCreate()
        settings.dailyGoalMl = 99999
        try store.save()

        XCTAssertEqual(settings.dailyGoalMl, AppConstants.maxDailyGoalMl)
    }

    func testSaveClampsGoalBelowMinimum() throws {
        let settings = try store.loadOrCreate()
        settings.dailyGoalMl = 10
        try store.save()

        XCTAssertEqual(settings.dailyGoalMl, AppConstants.minDailyGoalMl)
    }

    func testSaveClampsReminderInterval() throws {
        let settings = try store.loadOrCreate()
        settings.reminderIntervalMinutes = 5 // Below minimum 60
        try store.save()

        XCTAssertEqual(settings.reminderIntervalMinutes, 60)
    }

    func testSaveClampsNegativeStreak() throws {
        let settings = try store.loadOrCreate()
        settings.streakCount = -5
        try store.save()

        XCTAssertEqual(settings.streakCount, 0)
    }

    func testSaveClampsCustomAmount() throws {
        let settings = try store.loadOrCreate()
        settings.lastCustomAmountMl = 99999
        try store.save()

        XCTAssertEqual(settings.lastCustomAmountMl, AppConstants.customAmountMaxMl)
    }

    func testSaveNilCustomAmountStaysNil() throws {
        let settings = try store.loadOrCreate()
        settings.lastCustomAmountMl = nil
        try store.save()

        XCTAssertNil(settings.lastCustomAmountMl)
    }
}
