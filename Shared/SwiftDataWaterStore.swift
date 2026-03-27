//
//  SwiftDataWaterStore.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import SwiftData

@MainActor
protocol WaterStore {
    func addEntry(
        amountMl: Int,
        date: Date,
        isFromHealth: Bool,
        healthSampleId: UUID?
    ) throws -> WaterEntry
    func entries(from startDate: Date, to endDate: Date) throws -> [WaterEntry]
    func entriesMissingHealthSample() throws -> [WaterEntry]
    func total(for date: Date) throws -> Int
    func latestEntry() throws -> WaterEntry?
    func latestTodayEntry(for date: Date) throws -> WaterEntry?
    func latestEntryDate() throws -> Date?
    func updateEntry(
        _ entry: WaterEntry,
        amountMl: Int,
        date: Date,
        isFromHealth: Bool,
        healthSampleId: UUID?
    ) throws
    func entryWithHealthSampleId(_ sampleId: UUID) throws -> WaterEntry?
    func deleteEntry(_ entry: WaterEntry) throws
    func save() throws
}

@MainActor
final class SwiftDataWaterStore: WaterStore {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .autoupdatingCurrent) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func addEntry(
        amountMl: Int,
        date: Date,
        isFromHealth: Bool,
        healthSampleId: UUID?
    ) throws -> WaterEntry {
        let entry = WaterEntry(
            date: date,
            amountMl: amountMl,
            isFromHealth: isFromHealth,
            healthSampleId: healthSampleId
        )
        modelContext.insert(entry)
        try modelContext.save()
        return entry
    }

    func entries(from startDate: Date, to endDate: Date) throws -> [WaterEntry] {
        let predicate = #Predicate<WaterEntry> { entry in
            entry.date >= startDate && entry.date < endDate
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\WaterEntry.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func entriesMissingHealthSample() throws -> [WaterEntry] {
        let predicate = #Predicate<WaterEntry> { entry in
            entry.isFromHealth == false && entry.healthSampleId == nil
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\WaterEntry.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func total(for date: Date) throws -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let entries = try entries(from: startOfDay, to: endOfDay)
        return entries.reduce(0) { $0 + $1.amountMl }
    }

    func latestEntry() throws -> WaterEntry? {
        var descriptor = FetchDescriptor<WaterEntry>(
            sortBy: [SortDescriptor(\WaterEntry.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func latestTodayEntry(for date: Date) throws -> WaterEntry? {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        let predicate = #Predicate<WaterEntry> { entry in
            entry.date >= dayStart && entry.date < dayEnd
        }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\WaterEntry.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func latestEntryDate() throws -> Date? {
        try latestEntry()?.date
    }

    func updateEntry(
        _ entry: WaterEntry,
        amountMl: Int,
        date: Date,
        isFromHealth: Bool,
        healthSampleId: UUID?
    ) throws {
        entry.amountMl = amountMl
        entry.date = date
        entry.isFromHealth = isFromHealth
        entry.healthSampleId = healthSampleId
        try modelContext.save()
    }

    func entryWithHealthSampleId(_ sampleId: UUID) throws -> WaterEntry? {
        let predicate = #Predicate<WaterEntry> { entry in
            entry.healthSampleId == sampleId
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func deleteEntry(_ entry: WaterEntry) throws {
        modelContext.delete(entry)
        try modelContext.save()
    }

    func save() throws {
        try modelContext.save()
    }
}
