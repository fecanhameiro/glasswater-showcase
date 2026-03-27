//
//  WatchHomeViewModel.swift
//  GlassWaterWatch Watch App
//
//  Thin client view model. Sends commands to phone, receives authoritative state.
//  Local command queue handles offline scenarios with optimistic UI.
//

import Foundation
import Observation
import WatchKit
import WidgetKit

@MainActor
@Observable
final class WatchHomeViewModel {
    var dailyTotalMl: Int = 0
    var dailyGoalMl: Int = AppConstants.defaultDailyGoalMl
    var customAmountMl: Int = AppConstants.defaultCustomAmountMl
    var entries: [WatchStateEntry] = []

    var hasCompletedOnboarding: Bool = false

    // Premium state
    var recentlyAdded: Bool = false
    var justReachedGoal: Bool = false

    // Undo toast
    var showUndoToast: Bool = false
    var undoToastAmountMl: Int = 0
    var undoToastId: Int = 0
    private var undoToastTask: Task<Void, Never>?
    private var lastAddCommandId: UUID?

    private var connectivityService: (any WatchConnectivityServicing)?
    private let calendar = Calendar.autoupdatingCurrent
    private let appGroupDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    private let snapshotStore = AppGroupHydrationSnapshotStore()

    // Command queue for offline resilience
    private var pendingCommands: [WatchCommand] = []
    private let pendingCommandsKey = "glasswater.pendingWatchCommands"
    private let cachedStateKey = "glasswater.cachedWatchState"
    private let analytics = AnalyticsEventQueue()

    /// Quick-add amount: standard glass (10% of goal), or remaining when close to goal
    var quickAddAmountMl: Int {
        let standardGlass = QuickAddOptions.amount(forPercent: 10, goalMl: dailyGoalMl)
        let remaining = max(dailyGoalMl - dailyTotalMl, 0)

        if remaining > 0 && remaining < standardGlass {
            return QuickAddOptions.clampCustomAmount(remaining)
        }

        return standardGlass
    }

    /// Whether the quick-add is offering to complete the remaining goal
    var isCompletingGoal: Bool {
        let standardGlass = QuickAddOptions.amount(forPercent: 10, goalMl: dailyGoalMl)
        let remaining = max(dailyGoalMl - dailyTotalMl, 0)
        return remaining > 0 && remaining < standardGlass
    }

    var canUndo: Bool {
        entries.first != nil
    }

    var progress: Double {
        guard dailyGoalMl > 0 else { return 0 }
        return min(Double(dailyTotalMl) / Double(dailyGoalMl), 1.0)
    }

    var goalReached: Bool {
        dailyGoalMl > 0 && dailyTotalMl >= dailyGoalMl
    }

    /// Sum of pending add commands minus pending delete commands
    private var optimisticOffsetMl: Int {
        pendingCommands.reduce(0) { total, cmd in
            switch cmd.action {
            case .add: return total + (cmd.amountMl ?? 0)
            case .delete, .undoAdd: return total - (cmd.amountMl ?? 0)
            case .getState, .setCustomAmount: return total
            }
        }
    }

    init(connectivityService: (any WatchConnectivityServicing)? = nil) {
        self.connectivityService = connectivityService
        loadPendingCommands()
        setupConnectivity()
    }

    func load() {
        hasCompletedOnboarding = appGroupDefaults?
            .bool(forKey: AppConstants.appGroupOnboardingCompletedKey) ?? false
        loadDailyGoal()
        loadCustomAmount()
        applyCachedStateIfAvailable()
        SyncLog.info("[Sync] load() — after cache: totalMl=\(self.dailyTotalMl), goalMl=\(self.dailyGoalMl), pending=\(self.pendingCommands.count)")
        connectivityService?.requestState()
    }

    func add(amountMl: Int) {
        let wasGoalReached = goalReached
        SyncLog.info("[Sync] add() START — amountMl=\(amountMl), previousTotal=\(self.dailyTotalMl), goalMl=\(self.dailyGoalMl), pending=\(self.pendingCommands.count)")

        let command = WatchCommand.add(amountMl: amountMl)
        lastAddCommandId = command.id

        // Queue command
        pendingCommands.append(command)
        savePendingCommands()

        // Optimistic UI
        dailyTotalMl += amountMl
        triggerRecentlyAdded()

        if !wasGoalReached && goalReached {
            triggerCelebration()
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.click)
        }

        showUndoToastFor(amountMl: amountMl)

        // Persist for watch widgets
        persistSnapshotForWidgets()
        WidgetCenter.shared.reloadAllTimelines()

        // Send to phone
        connectivityService?.sendCommand(command) { [weak self] state in
            self?.applyAuthoritativeState(state)
        }

        SyncLog.info("[Sync] add() DONE — optimisticTotal=\(self.dailyTotalMl), commandId=\(command.id)")

        analytics.enqueue("water_added", parameters: [
            "amount_ml": "\(amountMl)",
            "source": "watch",
            "time_of_day": watchTimeOfDay()
        ])
    }

    func addCustom(amountMl: Int) {
        let clamped = QuickAddOptions.clampCustomAmount(amountMl)
        customAmountMl = clamped
        saveCustomAmount(clamped)
        syncCustomAmountToPhone(clamped)
        add(amountMl: clamped)
    }

    func undoLastEntry() {
        guard let entry = entries.first else {
            SyncLog.warning("[Sync] undoLastEntry — no entries to undo")
            return
        }

        SyncLog.info("[Sync] undoLastEntry START — entryId=\(entry.id), amountMl=\(entry.amountMl), currentTotal=\(self.dailyTotalMl)")

        let command = WatchCommand.delete(entryId: entry.id, amountMl: entry.amountMl)

        // Queue command
        pendingCommands.append(command)
        savePendingCommands()

        // Optimistic UI
        dailyTotalMl = max(dailyTotalMl - entry.amountMl, 0)
        entries.removeAll { $0.id == entry.id }
        WKInterfaceDevice.current().play(.click)

        // Persist for watch widgets
        persistSnapshotForWidgets()
        WidgetCenter.shared.reloadAllTimelines()

        // Send to phone
        connectivityService?.sendCommand(command) { [weak self] state in
            self?.applyAuthoritativeState(state)
        }

        SyncLog.info("[Sync] undoLastEntry DONE — optimisticTotal=\(self.dailyTotalMl), commandId=\(command.id)")

        analytics.enqueue("water_undone")
    }

    func undoFromToast() {
        dismissUndoToast()

        guard let cmdId = lastAddCommandId else {
            SyncLog.warning("[Sync] undoFromToast — no lastAddCommandId, falling back to undoLastEntry")
            undoLastEntry()
            return
        }

        // Capture the amount before removing the command
        let pendingIdx = pendingCommands.firstIndex(where: { $0.id == cmdId })
        let amount = pendingIdx.map { pendingCommands[$0].amountMl ?? undoToastAmountMl } ?? undoToastAmountMl

        // Remove the original add from pending (if still there)
        if let idx = pendingIdx {
            pendingCommands.remove(at: idx)
            SyncLog.info("[Sync] undoFromToast — removed pending add cmdId=\(cmdId)")
        } else {
            SyncLog.info("[Sync] undoFromToast — add cmdId=\(cmdId) already processed by phone")
        }

        // Create undoAdd command — kept in pendingCommands with negative offset
        // to counterbalance any stale add reply that arrives before phone processes the undo
        let undoCmd = WatchCommand.undoAdd(originalCommandId: cmdId, amountMl: amount)
        pendingCommands.append(undoCmd)
        savePendingCommands()

        // Optimistic UI revert
        dailyTotalMl = max(dailyTotalMl - amount, 0)
        lastAddCommandId = nil
        WKInterfaceDevice.current().play(.click)

        // Persist for watch widgets
        persistSnapshotForWidgets()
        WidgetCenter.shared.reloadAllTimelines()

        SyncLog.info("[Sync] undoFromToast DONE — undoCmdId=\(undoCmd.id), originalCmdId=\(cmdId), amount=\(amount), revertedTotal=\(self.dailyTotalMl), pendingCount=\(self.pendingCommands.count)")

        // Send undoAdd to phone — phone will delete the entry and reply with authoritative state
        connectivityService?.sendCommand(undoCmd) { [weak self] state in
            self?.applyAuthoritativeState(state)
        }

        analytics.enqueue("water_undone", parameters: [
            "source": "watch",
            "undo_type": "toast"
        ])
    }

    // MARK: - Authoritative State

    func applyAuthoritativeState(_ state: WatchState) {
        // Ignore sentinel settings-only updates (totalMl == -1)
        guard state.totalMl >= 0 else {
            if state.goalMl > 0 {
                dailyGoalMl = clampDailyGoal(state.goalMl)
                customAmountMl = QuickAddOptions.clampCustomAmount(state.customAmountMl)
                if let volumeUnit = state.volumeUnit {
                    appGroupDefaults?.set(volumeUnit, forKey: AppConstants.appGroupVolumeUnitKey)
                }
            }
            SyncLog.info("[Sync] applyAuthoritativeState — settings-only update: goalMl=\(state.goalMl)")
            return
        }

        // Remove acknowledged commands
        let processed = Set(state.processedCommandIds)
        let beforeCount = pendingCommands.count
        pendingCommands.removeAll { processed.contains($0.id) }

        // Clear stale pending commands from a different day
        pendingCommands.removeAll { cmd in
            guard let date = cmd.date else { return false }
            return !calendar.isDate(date, inSameDayAs: state.dayStart)
        }

        savePendingCommands()
        cacheState(state)

        // Receiving state from phone means onboarding is complete
        if !hasCompletedOnboarding {
            hasCompletedOnboarding = true
            appGroupDefaults?.set(true, forKey: AppConstants.appGroupOnboardingCompletedKey)
        }

        // Apply settings
        dailyGoalMl = clampDailyGoal(state.goalMl)
        customAmountMl = QuickAddOptions.clampCustomAmount(state.customAmountMl)
        if let volumeUnit = state.volumeUnit {
            appGroupDefaults?.set(volumeUnit, forKey: AppConstants.appGroupVolumeUnitKey)
        }

        // Apply entries from authoritative state
        entries = state.entries

        // Total = authoritative + optimistic offset from still-pending commands
        let offset = optimisticOffsetMl
        dailyTotalMl = max(state.totalMl + offset, 0)

        SyncLog.info("[Sync] applyAuthoritativeState — serverTotal=\(state.totalMl), offset=\(offset), displayTotal=\(self.dailyTotalMl), pendingBefore=\(beforeCount), pendingAfter=\(self.pendingCommands.count), entries=\(state.entries.count)")

        // Update watch widgets
        persistSnapshotForWidgets()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Connectivity

    private func setupConnectivity() {
        connectivityService?.onStateReceived = { [weak self] state in
            self?.applyAuthoritativeState(state)
        }
    }

    // MARK: - Snapshot for Watch Widgets

    private func persistSnapshotForWidgets() {
        let goal = dailyGoalMl
        let snapshotProgress = goal > 0 ? min(Double(dailyTotalMl) / Double(goal), 1) : 0
        let remaining = max(goal - dailyTotalMl, 0)
        let lastEntry = entries.first
        let snapshot = HydrationSnapshot(
            updatedAt: .now,
            dayStart: calendar.startOfDay(for: .now),
            totalMl: dailyTotalMl,
            goalMl: goal,
            progress: snapshotProgress,
            remainingMl: remaining,
            goalReached: goal > 0 && dailyTotalMl >= goal,
            lastIntakeMl: lastEntry?.amountMl,
            lastIntakeDate: lastEntry?.date,
            customAmountMl: customAmountMl,
            source: .watch
        )
        snapshotStore.save(snapshot)
    }

    // MARK: - Cached State Persistence

    private func cacheState(_ state: WatchState) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: cachedStateKey)
        }
    }

    private func applyCachedStateIfAvailable() {
        guard let data = UserDefaults.standard.data(forKey: cachedStateKey),
              let state = try? JSONDecoder().decode(WatchState.self, from: data),
              calendar.isDate(state.dayStart, inSameDayAs: .now)
        else {
            // Also try the app group snapshot as fallback
            if let snapshot = snapshotStore.load(),
               calendar.isDate(snapshot.dayStart, inSameDayAs: .now)
            {
                dailyTotalMl = snapshot.totalMl
                dailyGoalMl = snapshot.goalMl
                customAmountMl = QuickAddOptions.clampCustomAmount(snapshot.customAmountMl)
                SyncLog.info("[Sync] applyCachedStateIfAvailable — snapshot fallback: totalMl=\(snapshot.totalMl)")
            } else {
                SyncLog.info("[Sync] applyCachedStateIfAvailable — no valid cache found")
            }
            return
        }

        dailyGoalMl = clampDailyGoal(state.goalMl)
        customAmountMl = QuickAddOptions.clampCustomAmount(state.customAmountMl)
        entries = state.entries

        // Apply total + optimistic offset from pending commands
        let offset = optimisticOffsetMl
        dailyTotalMl = max(state.totalMl + offset, 0)

        if let volumeUnit = state.volumeUnit {
            appGroupDefaults?.set(volumeUnit, forKey: AppConstants.appGroupVolumeUnitKey)
        }

        SyncLog.info("[Sync] applyCachedStateIfAvailable — applied: totalMl=\(state.totalMl)+offset=\(offset)=\(self.dailyTotalMl), goalMl=\(state.goalMl), entries=\(state.entries.count), age=\(String(format: "%.1f", Date.now.timeIntervalSince(state.updatedAt)))s")
    }

    // MARK: - Pending Commands Persistence

    private func loadPendingCommands() {
        guard let data = UserDefaults.standard.data(forKey: pendingCommandsKey),
              let commands = try? JSONDecoder().decode([WatchCommand].self, from: data)
        else { return }
        pendingCommands = commands
    }

    private func savePendingCommands() {
        if pendingCommands.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingCommandsKey)
        } else if let data = try? JSONEncoder().encode(pendingCommands) {
            UserDefaults.standard.set(data, forKey: pendingCommandsKey)
        }
    }

    // MARK: - Undo Toast

    private func showUndoToastFor(amountMl: Int) {
        undoToastTask?.cancel()
        undoToastAmountMl = amountMl
        undoToastId += 1
        showUndoToast = true
        undoToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            showUndoToast = false
        }
    }

    private func dismissUndoToast() {
        undoToastTask?.cancel()
        showUndoToast = false
    }

    // MARK: - Animation Triggers

    private func triggerRecentlyAdded() {
        recentlyAdded = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            recentlyAdded = false
        }
    }

    private func triggerCelebration() {
        justReachedGoal = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            justReachedGoal = false
        }
    }

    // MARK: - Private Helpers

    private func loadDailyGoal() {
        if let storedGoal = appGroupDefaults?.object(forKey: AppConstants.appGroupDailyGoalKey) as? Int {
            dailyGoalMl = clampDailyGoal(storedGoal)
        } else {
            dailyGoalMl = AppConstants.defaultDailyGoalMl
        }
    }

    private func loadCustomAmount() {
        if let storedAmount = appGroupDefaults?.object(forKey: AppConstants.appGroupCustomAmountKey) as? Int {
            customAmountMl = QuickAddOptions.clampCustomAmount(storedAmount)
        } else {
            customAmountMl = QuickAddOptions.resolvedCustomAmount(forGoalMl: dailyGoalMl, customAmountMl: nil)
        }
    }

    private func saveCustomAmount(_ amount: Int) {
        appGroupDefaults?.set(amount, forKey: AppConstants.appGroupCustomAmountKey)
    }

    private func syncCustomAmountToPhone(_ amount: Int) {
        let command = WatchCommand.setCustomAmount(amount)
        connectivityService?.sendCommand(command, onReply: nil)
        SyncLog.info("[Sync] syncCustomAmountToPhone — sent \(amount)ml to phone")
    }

    private func clampDailyGoal(_ value: Int) -> Int {
        let step = max(AppConstants.dailyGoalStepMl, 1)
        let rounded = Int((Double(value) / Double(step)).rounded() * Double(step))
        return max(AppConstants.minDailyGoalMl, min(rounded, AppConstants.maxDailyGoalMl))
    }

    private func watchTimeOfDay() -> String {
        let hour = calendar.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "morning"
        case 12..<18: return "afternoon"
        default: return "evening"
        }
    }
}
