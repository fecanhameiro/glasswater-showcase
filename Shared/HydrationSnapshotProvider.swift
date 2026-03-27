//
//  HydrationSnapshotProvider.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

@MainActor
protocol HydrationSnapshotProviding {
    func snapshot(for date: Date, source: HydrationSnapshotSource) throws -> HydrationSnapshot
}

@MainActor
final class HydrationSnapshotProvider: HydrationSnapshotProviding {
    nonisolated deinit {}
    private let waterStore: WaterStore
    private let settingsStore: SettingsStore
    private let calendar: Calendar

    init(
        waterStore: WaterStore,
        settingsStore: SettingsStore,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.waterStore = waterStore
        self.settingsStore = settingsStore
        self.calendar = calendar
    }

    func snapshot(for date: Date, source: HydrationSnapshotSource) throws -> HydrationSnapshot {
        let settings = try settingsStore.loadOrCreate()
        let dayStart = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        let entries = try waterStore.entries(from: dayStart, to: endOfDay)
        let total = entries.reduce(0) { $0 + $1.amountMl }
        let lastEntry = entries.max(by: { $0.date < $1.date })
        let goal = settings.dailyGoalMl
        let progress = goal > 0 ? min(Double(total) / Double(goal), 1) : 0
        let remaining = max(goal - total, 0)
        let customAmount = QuickAddOptions.resolvedCustomAmount(
            forGoalMl: goal,
            customAmountMl: settings.lastCustomAmountMl
        )

        return HydrationSnapshot(
            updatedAt: date,
            dayStart: dayStart,
            totalMl: total,
            goalMl: goal,
            progress: progress,
            remainingMl: remaining,
            goalReached: goal > 0 && total >= goal,
            lastIntakeMl: lastEntry?.amountMl,
            lastIntakeDate: lastEntry?.date,
            customAmountMl: customAmount,
            source: source
        )
    }
}
