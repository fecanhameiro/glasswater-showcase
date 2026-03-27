//
//  GlassWaterApp.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import BackgroundTasks
import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import AppIntents
import SwiftData
import SwiftUI
import WatchConnectivity

/// Thread-safe flag for checking foreground state from Darwin notification callbacks.
private final class AppActiveFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = true
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

@main
struct GlassWaterApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    private let services: AppServices
    private let backgroundRefreshService: BackgroundRefreshService
    private let changeObserver: HydrationChangeObserver
    private let _isAppActive = AppActiveFlag()
    private let phoneConnectivityService: PhoneConnectivityService?
    private let cloudKitObserver: CloudKitSyncObserver
    private let dayChangeObserver: NSObjectProtocol?
    private let transactionListenerTask: Task<Void, Never>

    init() {
        #if !DEBUG
        FirebaseApp.configure()
        #endif

        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        container = ModelContainerFactory.makeContainerWithFallback(cloudKitSync: !isRunningTests)
        ModelContainerFactory.shared = container

        let modelContext = container.mainContext
        let waterStore = SwiftDataWaterStore(modelContext: modelContext)
        let settingsStore = SwiftDataSettingsStore(modelContext: modelContext)
        #if DEBUG
        let analyticsService: AnalyticsTracking = NoopAnalyticsService()
        #else
        let analyticsService: AnalyticsTracking = FirebaseAnalyticsService()
        #endif
        let liveActivityService = LiveActivityService(analytics: analyticsService)
        let hydrationSnapshotStore = AppGroupHydrationSnapshotStore()
        let hydrationSnapshotProvider = HydrationSnapshotProvider(
            waterStore: waterStore,
            settingsStore: settingsStore
        )
        let connectivity = WCSession.isSupported() ? PhoneConnectivityService() : nil
        phoneConnectivityService = connectivity
        let hydrationBroadcaster = HydrationUpdateBroadcaster(
            snapshotStore: hydrationSnapshotStore,
            settingsStore: settingsStore,
            liveActivity: liveActivityService,
            phoneConnectivity: connectivity
        )
        #if DEBUG
        let crashReporter: CrashReporting = NoopCrashReportingService()
        #else
        let crashReporter: CrashReporting = FirebaseCrashReportingService()
        #endif
        let tipJarService = TipJarService()
        let capturedSettingsStore = settingsStore
        transactionListenerTask = tipJarService.listenForTransactions {
            await MainActor.run {
                if let settings = try? capturedSettingsStore.loadOrCreate() {
                    settings.hasTipped = true
                    try? capturedSettingsStore.save()
                    NotificationCenter.default.post(name: .settingsDidChange, object: nil)
                }
            }
        }
        services = AppServices(
            waterStore: waterStore,
            settingsStore: settingsStore,
            healthService: HealthKitService(),
            notificationService: NotificationService(crashReporter: crashReporter),
            haptics: HapticsService(),
            liveActivity: liveActivityService,
            hydrationSnapshotStore: hydrationSnapshotStore,
            hydrationSnapshotProvider: hydrationSnapshotProvider,
            hydrationBroadcaster: hydrationBroadcaster,
            phoneConnectivity: connectivity,
            sounds: SoundService(),
            crashReporter: crashReporter,
            analytics: analyticsService,
            tipJar: tipJarService
        )

        backgroundRefreshService = BackgroundRefreshService()

        let capturedServices = services
        let isActive = _isAppActive
        changeObserver = HydrationChangeObserver {
            guard isActive.value else {
                SyncLog.info("[Sync] Darwin notification received in background — skipping broadcast (BGRefresh handles this)")
                return
            }
            SyncLog.info("[Sync] Darwin notification received — broadcasting from SwiftData")
            await capturedServices.broadcastCurrentSnapshot()
            await capturedServices.notificationService.clearDeliveredReminders()
            NotificationCenter.default.post(name: .hydrationDidChangeExternally, object: nil)
        }
        changeObserver.startObserving()

        // Observe remote CloudKit sync changes
        cloudKitObserver = CloudKitSyncObserver {
            guard isActive.value else {
                SyncLog.info("[Sync] CloudKit change received in background — skipping broadcast")
                return
            }
            // Check if hydration data actually changed before triggering a full broadcast cycle.
            // CloudKit fires many notifications during token-expired recovery (full re-sync),
            // and broadcasting unchanged data creates a feedback loop with widget reloads.
            let existingSnapshot = capturedServices.hydrationSnapshotStore.load()
            let currentSnapshot = try? capturedServices.hydrationSnapshotProvider.snapshot(for: .now, source: .app)
            let dataChanged = existingSnapshot?.totalMl != currentSnapshot?.totalMl
                || existingSnapshot?.goalMl != currentSnapshot?.goalMl
            guard dataChanged else {
                SyncLog.info("[Sync] CloudKit change received — no hydration data change, skipping broadcast")
                return
            }
            SyncLog.info("[Sync] CloudKit change received — broadcasting from SwiftData")
            await capturedServices.broadcastCurrentSnapshot()
            await capturedServices.notificationService.clearDeliveredReminders()
            NotificationCenter.default.post(name: .hydrationDidChangeExternally, object: nil)
        }
        cloudKitObserver.startObserving()

        // Register App Shortcuts with Siri
        GlassWaterShortcuts.updateAppShortcutParameters()
        AppLog.info("[Siri] App Shortcuts registered", category: .lifecycle)

        // Detect midnight / timezone changes — resets LA & widgets to new day
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppLog.info("[Lifecycle] significantTimeChange — day rollover detected, broadcasting fresh snapshot", category: .lifecycle)
            Task { @MainActor in
                await capturedServices.broadcastCurrentSnapshot()
                NotificationCenter.default.post(name: .hydrationDidChangeExternally, object: nil)
            }
        }

        // Inject watchStateBuilder into broadcaster so it sends WatchState to watch
        hydrationBroadcaster.watchStateBuilder = { [capturedServices] in
            try capturedServices.buildWatchState()
        }

        // Watch sends commands (add/delete/getState), phone processes and replies with authoritative state
        phoneConnectivityService?.onCommandReceived = { command, reply in
            Task { @MainActor in
                let latency = Date.now.timeIntervalSince(command.sentAt)
                SyncLog.info("[Sync] onCommandReceived — action=\(command.action.rawValue), id=\(command.id), latency=\(String(format: "%.1f", latency))s")

                do {
                    switch command.action {
                    case .add:
                        guard let amountMl = command.amountMl,
                              let date = command.date
                        else {
                            SyncLog.info("[Sync] Watch add SKIPPED — missing amount or date")
                            let state = try capturedServices.buildWatchState(processedCommandIds: [command.id])
                            reply(state)
                            return
                        }

                        // Safety net: skip if this add was already undone via undoAdd
                        if capturedServices.isCommandUndone(command.id) {
                            SyncLog.info("[Sync] Watch add SKIPPED — command.id=\(command.id) was already undone")
                            let state = try capturedServices.buildWatchState(processedCommandIds: [command.id])
                            reply(state)
                            return
                        }

                        // Dedup: use command.id as healthSampleId
                        let existing = try capturedServices.waterStore.entryWithHealthSampleId(command.id)
                        var newEntry: WaterEntry?
                        if existing != nil {
                            SyncLog.info("[Sync] Watch add SKIPPED — duplicate command.id=\(command.id)")
                        } else {
                            newEntry = try capturedServices.waterStore.addEntry(
                                amountMl: amountMl,
                                date: date,
                                isFromHealth: false,
                                healthSampleId: command.id
                            )
                            SyncLog.info("[Sync] Watch add PERSISTED — id=\(newEntry!.id), amountMl=\(amountMl)")
                            capturedServices.storeEntryIdForCommand(command.id, entryId: newEntry!.id)
                        }

                        // Snapshot + widget reload FIRST (before HK save which can take 500ms-2s)
                        // This matches AddWaterIntent's pattern: visual update before best-effort HK
                        do {
                            let snapshot = try capturedServices.hydrationSnapshotProvider.snapshot(for: .now, source: .watch)
                            capturedServices.hydrationSnapshotStore.save(snapshot)
                            SyncLog.info("[Sync] Watch add — snapshot saved (totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl), dayStart=\(snapshot.dayStart.formatted()))")

                            WidgetReloadCoordinator.shared.requestReload(source: "watchAdd")
                        } catch {
                            SyncLog.error("[Sync] Watch add — snapshot/widget reload failed: \(error.localizedDescription)")
                        }

                        let state = try capturedServices.buildWatchState(processedCommandIds: [command.id])
                        reply(state)

                        // HealthKit save — best effort, after widget update
                        // CRITICAL: update entry with real HK sampleId to prevent syncHealthEntries
                        // from creating a duplicate (matches HomeViewModel.add() pattern)
                        if let entry = newEntry {
                            do {
                                let sampleId = try await capturedServices.healthService.saveWaterIntake(amountMl: amountMl, date: date)
                                try capturedServices.waterStore.updateEntry(
                                    entry,
                                    amountMl: amountMl,
                                    date: date,
                                    isFromHealth: true,
                                    healthSampleId: sampleId
                                )
                                SyncLog.info("[Sync] Watch add — HK saved & entry updated with sampleId=\(sampleId)")
                            } catch {
                                SyncLog.warning("[Sync] Watch add HK write failed (non-fatal): \(error.localizedDescription)")
                            }
                        }

                        // Full broadcast (LA update, etc.) — may be slow but widgets already updated
                        await capturedServices.broadcastCurrentSnapshot(source: .watch)
                        await capturedServices.notificationService.clearDeliveredReminders()
                        NotificationCenter.default.post(name: .hydrationDidChangeExternally, object: nil)

                    case .delete:
                        guard let entryId = command.entryId else {
                            SyncLog.info("[Sync] Watch delete SKIPPED — missing entryId")
                            let state = try capturedServices.buildWatchState(processedCommandIds: [command.id])
                            reply(state)
                            return
                        }

                        // Find entry by ID in today's entries
                        let calendar = Calendar.autoupdatingCurrent
                        let dayStart = calendar.startOfDay(for: .now)
                        let endOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? .now
                        let todayEntries = try capturedServices.waterStore.entries(from: dayStart, to: endOfDay)
                        var deletedSampleId: UUID?
                        if let entry = todayEntries.first(where: { $0.id == entryId }) {
                            deletedSampleId = entry.healthSampleId
                            try capturedServices.waterStore.deleteEntry(entry)
                            SyncLog.info("[Sync] Watch delete PERSISTED — entryId=\(entryId)")
                        } else {
                            SyncLog.info("[Sync] Watch delete SKIPPED — no entry found for id=\(entryId)")
                        }

                        // Snapshot + widget reload FIRST (before HK delete)
                        do {
                            let snapshot = try capturedServices.hydrationSnapshotProvider.snapshot(for: .now, source: .watch)
                            capturedServices.hydrationSnapshotStore.save(snapshot)
                            SyncLog.info("[Sync] Watch delete — snapshot saved (totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl))")
                            WidgetReloadCoordinator.shared.requestReload(source: "watchDelete")
                        } catch {
                            SyncLog.error("[Sync] Watch delete — snapshot/widget reload failed: \(error.localizedDescription)")
                        }

                        let state = try capturedServices.buildWatchState(processedCommandIds: [command.id])
                        reply(state)

                        // HealthKit delete — best effort, after widget update
                        if let deletedSampleId {
                            do {
                                try await capturedServices.healthService.deleteWaterSample(id: deletedSampleId)
                            } catch {
                                SyncLog.warning("[Sync] Watch delete HK failed (non-fatal): \(error.localizedDescription)")
                            }
                        }

                        // Full broadcast (LA update, etc.)
                        await capturedServices.broadcastCurrentSnapshot(source: .watch)
                        await capturedServices.notificationService.clearDeliveredReminders()
                        NotificationCenter.default.post(name: .hydrationDidChangeExternally, object: nil)

                    case .undoAdd:
                        guard let originalCommandId = command.entryId else {
                            SyncLog.warning("[Sync] Watch undoAdd SKIPPED — missing originalCommandId")
                            let state = try capturedServices.buildWatchState(processedCommandIds: [command.id])
                            reply(state)
                            return
                        }

                        SyncLog.info("[Sync] Watch undoAdd START — originalCmdId=\(originalCommandId), undoCmdId=\(command.id)")

                        // Track this command ID as undone (safety net for late-arriving adds)
                        capturedServices.markCommandAsUndone(originalCommandId)

                        // The original add used command.id as healthSampleId — find the entry by it.
                        // Fallback: if HealthKit save already updated healthSampleId, use stored mapping.
                        var deletedHKSampleId: UUID?
                        var entryToDelete: WaterEntry?

                        // Primary lookup: by healthSampleId (works if HK save hasn't run yet)
                        entryToDelete = try capturedServices.waterStore.entryWithHealthSampleId(originalCommandId)

                        // Fallback: by stored command→entry mapping (works after HK save updates healthSampleId)
                        if entryToDelete == nil, let mappedEntryId = capturedServices.entryIdForCommand(originalCommandId) {
                            let calendar = Calendar.autoupdatingCurrent
                            let dayStart = calendar.startOfDay(for: .now)
                            let endOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? .now
                            let todayEntries = try capturedServices.waterStore.entries(from: dayStart, to: endOfDay)
                            entryToDelete = todayEntries.first(where: { $0.id == mappedEntryId })
                            if entryToDelete != nil {
                                SyncLog.info("[Sync] Watch undoAdd — found entry via command→entry mapping (HK already updated healthSampleId)")
                            }
                        }

                        if let entry = entryToDelete {
                            deletedHKSampleId = entry.healthSampleId
                            let entryId = entry.id
                            let entryAmount = entry.amountMl
                            try capturedServices.waterStore.deleteEntry(entry)
                            SyncLog.info("[Sync] Watch undoAdd DELETED — entryId=\(entryId), amountMl=\(entryAmount), originalCmdId=\(originalCommandId)")
                        } else {
                            SyncLog.info("[Sync] Watch undoAdd — no entry found for originalCmdId=\(originalCommandId) (may not have been persisted yet)")
                        }

                        // Snapshot + widget reload
                        do {
                            let snapshot = try capturedServices.hydrationSnapshotProvider.snapshot(for: .now, source: .watch)
                            capturedServices.hydrationSnapshotStore.save(snapshot)
                            SyncLog.info("[Sync] Watch undoAdd — snapshot saved (totalMl=\(snapshot.totalMl))")
                            WidgetReloadCoordinator.shared.requestReload(source: "watchUndoAdd")
                        } catch {
                            SyncLog.error("[Sync] Watch undoAdd — snapshot/widget failed: \(error.localizedDescription)")
                        }

                        let state = try capturedServices.buildWatchState(processedCommandIds: [command.id])
                        reply(state)

                        // HealthKit delete — best effort
                        if let deletedHKSampleId {
                            do {
                                try await capturedServices.healthService.deleteWaterSample(id: deletedHKSampleId)
                                SyncLog.info("[Sync] Watch undoAdd — HK sample deleted: \(deletedHKSampleId)")
                            } catch {
                                SyncLog.warning("[Sync] Watch undoAdd HK delete failed (non-fatal): \(error.localizedDescription)")
                            }
                        }

                        // Full broadcast
                        await capturedServices.broadcastCurrentSnapshot(source: .watch)
                        await capturedServices.notificationService.clearDeliveredReminders()
                        NotificationCenter.default.post(name: .hydrationDidChangeExternally, object: nil)

                    case .getState:
                        let state = try capturedServices.buildWatchState()
                        reply(state)
                        SyncLog.info("[Sync] getState replied — totalMl=\(state.totalMl)")

                    case .setCustomAmount:
                        guard let amountMl = command.amountMl else {
                            SyncLog.info("[Sync] Watch setCustomAmount SKIPPED — missing amount")
                            let state = try capturedServices.buildWatchState()
                            reply(state)
                            return
                        }
                        let clamped = QuickAddOptions.clampCustomAmount(amountMl)
                        let settings = try capturedServices.settingsStore.loadOrCreate()
                        settings.lastCustomAmountMl = clamped
                        try capturedServices.settingsStore.save()
                        SyncLog.info("[Sync] Watch setCustomAmount PERSISTED — \(clamped)ml")

                        let state = try capturedServices.buildWatchState()
                        reply(state)

                        await capturedServices.broadcastCurrentSnapshot(source: .watch)
                    }
                } catch {
                    SyncLog.error("[Sync] onCommandReceived FAILED: \(error.localizedDescription)")
                    capturedServices.crashReporter.record(error: error)
                    reply(nil)
                }
            }
        }

        // Backfill onboarding flag in UserDefaults for users who completed onboarding
        // before this key existed — ensures RootView.init reads the correct state instantly.
        let appGroupDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if appGroupDefaults?.bool(forKey: AppConstants.appGroupOnboardingCompletedKey) != true {
            if let settings = try? settingsStore.loadOrCreate(), settings.hasCompletedOnboarding {
                appGroupDefaults?.set(true, forKey: AppConstants.appGroupOnboardingCompletedKey)
            }
        }

        appDelegate.configure(services: services)
        backgroundRefreshService.register()
        backgroundRefreshService.schedule()
        drainAnalyticsQueue()

        // Set initial Crashlytics context for debugging
        #if !DEBUG
        let healthService = services.healthService
        Task { @MainActor in
            let hkStatus = await healthService.authorizationStatus()
            Crashlytics.crashlytics().setCustomValue(String(describing: hkStatus), forKey: "health_kit_status")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, newPhase in
            AppLog.info("[Lifecycle] scenePhase → \(String(describing: newPhase))", category: .lifecycle)
            if newPhase == .background {
                _isAppActive.value = false
                backgroundRefreshService.schedule()
                backgroundRefreshService.scheduleMidnightRefresh()
                // Don't broadcast on background — data hasn't changed, and it can trigger
                // a Darwin notification → broadcast loop (broadcast storm) overnight.
            }
            if newPhase == .active {
                _isAppActive.value = true
                Task { await services.notificationService.clearDeliveredReminders() }
                services.settingsStore.invalidateCache()
                drainAnalyticsQueue()
                logAppOpen()
                uploadLogsIfNeeded()
                // refreshNotifications + broadcastCurrentSnapshot are handled by
                // HomeViewModel.load() which runs on HomeView's scenePhase → .active.
                // No need to duplicate here.
            }
        }
    }

    // MARK: - Log Upload

    #if DEBUG
    private let logUploadService: LogUploading = NoopLogUploadService()
    #else
    private let logUploadService: LogUploading = FirestoreLogUploadService()
    #endif

    private func uploadLogsIfNeeded() {
        Task {
            await logUploadService.uploadIfNeeded()
        }
    }

    // MARK: - Analytics

    private func logAppOpen() {
        var params: [String: Any] = [
            AnalyticsParams.timeOfDay: AnalyticsTimeOfDay.current()
        ]
        if let snapshot = services.hydrationSnapshotStore.load(),
           Calendar.autoupdatingCurrent.isDateInToday(snapshot.dayStart)
        {
            let goal = snapshot.goalMl
            let progress = goal > 0 ? Int(Double(snapshot.totalMl) / Double(goal) * 100) : 0
            params[AnalyticsParams.progressPercent] = progress
        }
        if let settings = try? services.settingsStore.loadOrCreate() {
            params[AnalyticsParams.streakDays] = settings.streakCount
        }
        services.analytics.logEvent(AnalyticsEvents.appOpen, parameters: params)
    }

    private func drainAnalyticsQueue() {
        let events = AnalyticsEventQueue().drainAll()
        for event in events {
            services.analytics.logEvent(event.name, parameters: event.parameters)
        }
        if events.contains(where: { $0.parameters["source"] == "widget" }) {
            services.analytics.setUserProperty("true", forName: AnalyticsUserProps.usesWidget)
        }
        if events.contains(where: { $0.parameters["source"] == "watch" }) {
            services.analytics.setUserProperty("true", forName: AnalyticsUserProps.usesWatch)
        }
        if events.contains(where: { $0.parameters["source"] == "liveActivity" }) {
            services.analytics.setUserProperty("true", forName: AnalyticsUserProps.usesLiveActivity)
        }
        if events.contains(where: { $0.parameters["source"] == "siri" }) {
            services.analytics.setUserProperty("true", forName: AnalyticsUserProps.usesSiri)
        }
    }
}

extension Notification.Name {
    /// Posted when hydration data changes from an external source (widget, LA, watch).
    /// HomeViewModel observes this to reload its data and may trigger celebration.
    static let hydrationDidChangeExternally = Notification.Name("hydrationDidChangeExternally")

    /// Posted when hydration data changes from an in-app edit (History view delete/edit).
    /// HomeViewModel observes this to reload its data WITHOUT triggering celebration.
    static let hydrationDidChangeFromHistory = Notification.Name("hydrationDidChangeFromHistory")

    /// Posted when the user changes the volume unit preference (ml/oz/auto).
    /// Views that display formatted volumes observe this to re-render.
    static let volumeUnitDidChange = Notification.Name("volumeUnitDidChange")

    /// Posted when settings change (e.g. swimming duck toggle).
    /// HomeView observes this to reload relevant settings.
    static let settingsDidChange = Notification.Name("settingsDidChange")
}
