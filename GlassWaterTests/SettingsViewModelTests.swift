//
//  SettingsViewModelTests.swift
//  GlassWaterTests
//
//  Tests for SettingsViewModel — settings persistence, watch sync,
//  notification authorization, live activity toggling, and analytics.
//

import XCTest

@testable import GlassWater

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var vm: SettingsViewModel!

    override func setUp() async throws {
        AppServices.lastBroadcastRequestDate = nil
        builder = TestServicesBuilder()
        vm = SettingsViewModel(services: builder.services)
    }

    override func tearDown() {
        AppServices.lastBroadcastRequestDate = nil
        builder = nil
        vm = nil
        super.tearDown()
    }

    // MARK: - Initial State from Settings

    func testInitialStateLoadsFromSettings() {
        builder.settingsStore.settings.dailyGoalMl = 3000
        builder.settingsStore.settings.notificationsEnabled = true
        builder.settingsStore.settings.hapticsEnabled = false
        builder.settingsStore.settings.liveActivitiesEnabled = false
        builder.settingsStore.settings.reminderStartMinutes = 8 * 60
        builder.settingsStore.settings.reminderEndMinutes = 22 * 60
        builder.settingsStore.settings.reminderIntervalMinutes = 90

        let customVm = SettingsViewModel(services: builder.services)

        XCTAssertEqual(customVm.dailyGoalMl, 3000)
        XCTAssertTrue(customVm.notificationsEnabled)
        XCTAssertFalse(customVm.hapticsEnabled)
        XCTAssertFalse(customVm.liveActivitiesEnabled)
        XCTAssertEqual(customVm.reminderStartMinutes, 8 * 60)
        XCTAssertEqual(customVm.reminderEndMinutes, 22 * 60)
        XCTAssertEqual(customVm.reminderIntervalMinutes, 90)
    }

    func testInitialStateWithSettingsError() {
        builder.settingsStore.shouldThrow = true
        let errorVm = SettingsViewModel(services: builder.services)

        // Should use defaults and report error
        XCTAssertEqual(errorVm.dailyGoalMl, AppConstants.defaultDailyGoalMl)
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }

    // MARK: - Persist Changes

    func testPersistChangesWritesToStore() {
        vm.dailyGoalMl = 3000
        vm.hapticsEnabled = false
        vm.persistChanges()

        XCTAssertEqual(builder.settingsStore.saveCallCount, 1)
    }

    func testPersistChangesSendsToWatch() {
        vm.dailyGoalMl = 3000
        vm.persistChanges()

        XCTAssertEqual(builder.phoneConnectivity.sendSettingsCallCount, 1)
        XCTAssertEqual(builder.phoneConnectivity.lastSentGoalMl, 3000)
    }

    func testPersistChangesWithSaveError() {
        builder.settingsStore.shouldThrow = true

        // loadOrCreate succeeds first (init), then we break save
        let errorVm = SettingsViewModel(services: builder.services)
        builder.settingsStore.shouldThrow = true
        errorVm.persistChanges()

        // Should report error to crash reporter
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }

    // MARK: - Goal Change Analytics

    func testGoalChangeLogsAnalytics() {
        // Init loads goal as default (2500)
        vm.dailyGoalMl = 3000
        vm.persistChanges()

        let goalEvents = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.goalChanged }
        XCTAssertEqual(goalEvents.count, 1)
        XCTAssertEqual(goalEvents.first?.parameters?[AnalyticsParams.oldValue] as? Int, AppConstants.defaultDailyGoalMl)
        XCTAssertEqual(goalEvents.first?.parameters?[AnalyticsParams.newValue] as? Int, 3000)
    }

    func testGoalUnchangedNoAnalytics() {
        // Don't change goal
        vm.persistChanges()

        let goalEvents = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.goalChanged }
        XCTAssertTrue(goalEvents.isEmpty, "Should not log goal_changed when goal hasn't changed")
    }

    // MARK: - Notifications

    func testUpdateNotificationsRequestsAuth() async {
        vm.notificationsEnabled = true
        await vm.updateNotifications()

        // MockNotificationService.requestAuthorization returns true by default
        XCTAssertTrue(vm.notificationsEnabled)
        XCTAssertEqual(builder.notificationService.updateRemindersCallCount, 1)
    }

    func testUpdateNotificationsDisabling() async {
        vm.notificationsEnabled = false
        await vm.updateNotifications()

        // Should still update reminders (with isEnabled=false)
        XCTAssertEqual(builder.notificationService.updateRemindersCallCount, 1)
    }

    // MARK: - Live Activities

    func testUpdateLiveActivitiesEnablingBroadcasts() async {
        vm.liveActivitiesEnabled = true
        await vm.updateLiveActivities()

        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
        XCTAssertEqual(builder.liveActivity.endCallCount, 0)
    }

    func testDisableLiveActivityEnds() async {
        vm.liveActivitiesEnabled = false
        await vm.updateLiveActivities()

        XCTAssertEqual(builder.liveActivity.endCallCount, 1)
        XCTAssertEqual(builder.broadcaster.broadcastCallCount, 0)
    }

    func testLiveActivityToggleLogsAnalytics() async {
        vm.liveActivitiesEnabled = true
        await vm.updateLiveActivities()

        let events = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.settingChanged }
        let laEvent = events.first { ($0.parameters?[AnalyticsParams.setting] as? String) == "live_activities" }
        XCTAssertNotNil(laEvent)
    }

    // MARK: - Reminder Date Conversion

    func testReminderStartDateConversion() {
        vm.reminderStartMinutes = 9 * 60 + 30 // 09:30

        let date = vm.reminderStartDate
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 30)
    }

    func testReminderStartDateSetterConvertsBack() {
        // Set via date
        let cal = Calendar.autoupdatingCurrent
        let startOfDay = cal.startOfDay(for: .now)
        let targetDate = cal.date(byAdding: .minute, value: 10 * 60 + 15, to: startOfDay)!

        vm.reminderStartDate = targetDate

        XCTAssertEqual(vm.reminderStartMinutes, 10 * 60 + 15)
    }

    // MARK: - Health Access

    func testRequestHealthAccess() async {
        builder.healthService.status = .authorized
        await vm.requestHealthAccess()

        XCTAssertEqual(vm.healthStatus, .authorized)
        XCTAssertFalse(vm.isRequestingHealthAccess, "Should reset loading flag")
    }

    func testRequestHealthAccessPreventsDouble() async {
        // Simulate already requesting
        builder.healthService.status = .authorized

        // First call
        await vm.requestHealthAccess()
        XCTAssertFalse(vm.isRequestingHealthAccess)
    }

    // MARK: - Setting Toggle Tracking

    func testTrackSettingToggle() {
        vm.trackSettingToggle("haptics", enabled: false)

        let events = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.settingChanged }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.parameters?[AnalyticsParams.setting] as? String, "haptics")
    }
}
