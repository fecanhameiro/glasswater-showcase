//
//  WatchComplicationProvider.swift
//  GlassWaterWatch Watch App
//

import SwiftUI
import WidgetKit

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let currentMl: Int
    let goalMl: Int
    let progress: Double
    let goalReached: Bool
    let remainingMl: Int
    let lastEntryDate: Date?
}

struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(
            date: .now,
            currentMl: 1200,
            goalMl: 2500,
            progress: 0.48,
            goalReached: false,
            remainingMl: 1300,
            lastEntryDate: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let calendar = Calendar.autoupdatingCurrent
        let entry = loadEntry()

        // Midnight entry resets progress to 0 (day rollover defense-in-depth)
        var entries = [entry]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) {
            let midnight = calendar.startOfDay(for: tomorrow)
            let midnightEntry = WatchComplicationEntry(
                date: midnight,
                currentMl: 0,
                goalMl: entry.goalMl,
                progress: 0,
                goalReached: false,
                remainingMl: entry.goalMl,
                lastEntryDate: nil
            )
            entries.append(midnightEntry)
        }

        let refreshDate = calendar.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: entries, policy: .after(refreshDate))
        completion(timeline)
    }

    private func loadEntry() -> WatchComplicationEntry {
        let snapshotStore = AppGroupHydrationSnapshotStore()
        if let snapshot = snapshotStore.load(),
           Calendar.autoupdatingCurrent.isDate(snapshot.dayStart, inSameDayAs: .now) {
            return WatchComplicationEntry(
                date: snapshot.updatedAt,
                currentMl: snapshot.totalMl,
                goalMl: snapshot.goalMl,
                progress: snapshot.progress,
                goalReached: snapshot.goalReached,
                remainingMl: snapshot.remainingMl,
                lastEntryDate: snapshot.lastIntakeDate
            )
        }
        return WatchComplicationEntry(
            date: .now,
            currentMl: 0,
            goalMl: AppConstants.defaultDailyGoalMl,
            progress: 0,
            goalReached: false,
            remainingMl: AppConstants.defaultDailyGoalMl,
            lastEntryDate: nil
        )
    }
}
