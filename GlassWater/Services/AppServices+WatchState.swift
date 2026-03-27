//
//  AppServices+WatchState.swift
//  GlassWater
//
//  Builds authoritative WatchState from SwiftData for the watch.
//

import Foundation
private let processedCommandIdsKey = "glasswater.processedWatchCommandIds"
private let undoneCommandIdsKey = "glasswater.undoneWatchCommandIds"
private let commandEntryMapKey = "glasswater.commandEntryMap"
private let maxProcessedIds = 20
private let maxUndoneIds = 20
private let maxCommandEntryMapEntries = 20

@MainActor
extension AppServices {
    func buildWatchState(processedCommandIds: [UUID] = []) throws -> WatchState {
        let settings = try settingsStore.loadOrCreate()
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: .now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? .now
        let entries = try waterStore.entries(from: dayStart, to: endOfDay)
        let total = entries.reduce(0) { $0 + $1.amountMl }
        let goal = settings.dailyGoalMl
        let progress = goal > 0 ? min(Double(total) / Double(goal), 1) : 0
        let remaining = max(goal - total, 0)
        let customAmount = QuickAddOptions.resolvedCustomAmount(
            forGoalMl: goal,
            customAmountMl: settings.lastCustomAmountMl
        )

        // Build recent entries (last 8, most recent first)
        let sortedEntries = entries.sorted { $0.date > $1.date }
        let recentEntries = sortedEntries.prefix(8).map { entry in
            WatchStateEntry(
                id: entry.id,
                amountMl: entry.amountMl,
                date: entry.date
            )
        }

        // Maintain rolling window of processed command IDs
        let allProcessedIds = mergeProcessedCommandIds(processedCommandIds)

        return WatchState(
            updatedAt: .now,
            dayStart: dayStart,
            totalMl: total,
            goalMl: goal,
            progress: progress,
            remainingMl: remaining,
            goalReached: goal > 0 && total >= goal,
            customAmountMl: customAmount,
            volumeUnit: settings.preferredVolumeUnit,
            entries: Array(recentEntries),
            processedCommandIds: allProcessedIds
        )
    }

    private func mergeProcessedCommandIds(_ newIds: [UUID]) -> [UUID] {
        let defaults = UserDefaults.standard
        var existing: [UUID] = []
        if let data = defaults.data(forKey: processedCommandIdsKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data)
        {
            existing = decoded
        }

        // Append new IDs and keep only the most recent ones
        var merged = existing
        for id in newIds where !merged.contains(id) {
            merged.append(id)
        }
        if merged.count > maxProcessedIds {
            merged = Array(merged.suffix(maxProcessedIds))
        }

        if let data = try? JSONEncoder().encode(merged) {
            defaults.set(data, forKey: processedCommandIdsKey)
        }

        return merged
    }

    // MARK: - Undone Command Tracking (Phone-Side Safety Net)

    /// Mark an original add command ID as undone so late-arriving adds are skipped.
    func markCommandAsUndone(_ originalCommandId: UUID) {
        let defaults = UserDefaults.standard
        var ids: [UUID] = []
        if let data = defaults.data(forKey: undoneCommandIdsKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            ids = decoded
        }
        guard !ids.contains(originalCommandId) else { return }
        ids.append(originalCommandId)
        if ids.count > maxUndoneIds {
            ids = Array(ids.suffix(maxUndoneIds))
        }
        if let data = try? JSONEncoder().encode(ids) {
            defaults.set(data, forKey: undoneCommandIdsKey)
        }
        SyncLog.info("[Sync] markCommandAsUndone — originalCmdId=\(originalCommandId), totalTracked=\(ids.count)")
    }

    /// Check if an add command was already undone.
    func isCommandUndone(_ commandId: UUID) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: undoneCommandIdsKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data)
        else { return false }
        return ids.contains(commandId)
    }

    // MARK: - Command → Entry ID Mapping

    /// Store a mapping from watch command ID to SwiftData entry ID.
    /// Used by undoAdd to find the entry even after HealthKit updates the healthSampleId.
    func storeEntryIdForCommand(_ commandId: UUID, entryId: UUID) {
        let defaults = UserDefaults.standard
        var map: [[String: String]] = []
        if let data = defaults.data(forKey: commandEntryMapKey),
           let decoded = try? JSONDecoder().decode([[String: String]].self, from: data) {
            map = decoded
        }
        map.append(["cmd": commandId.uuidString, "entry": entryId.uuidString])
        if map.count > maxCommandEntryMapEntries {
            map = Array(map.suffix(maxCommandEntryMapEntries))
        }
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: commandEntryMapKey)
        }
    }

    /// Look up the SwiftData entry ID for a given watch command ID.
    func entryIdForCommand(_ commandId: UUID) -> UUID? {
        guard let data = UserDefaults.standard.data(forKey: commandEntryMapKey),
              let map = try? JSONDecoder().decode([[String: String]].self, from: data)
        else { return nil }
        let cmdStr = commandId.uuidString
        guard let pair = map.first(where: { $0["cmd"] == cmdStr }),
              let entryStr = pair["entry"]
        else { return nil }
        return UUID(uuidString: entryStr)
    }
}
