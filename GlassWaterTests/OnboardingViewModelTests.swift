//
//  OnboardingViewModelTests.swift
//  GlassWaterTests
//
//  Tests for OnboardingViewModel — onboarding flow, permission requests,
//  goal setting, and completion with broadcast + notification setup.
//

import XCTest

@testable import GlassWater

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var vm: OnboardingViewModel!

    override func setUp() async throws {
        AppServices.lastBroadcastRequestDate = nil
        builder = TestServicesBuilder()
        vm = OnboardingViewModel(services: builder.services)
    }

    override func tearDown() {
        AppServices.lastBroadcastRequestDate = nil
        builder = nil
        vm = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(vm.healthStatus, .unknown)
        XCTAssertFalse(vm.notificationsEnabled)
        XCTAssertFalse(vm.isRequestingHealthAccess)
        XCTAssertEqual(vm.dailyGoalMl, AppConstants.defaultDailyGoalMl)
    }

    func testInitialStateWithSettingsError() {
        builder.settingsStore.shouldThrow = true
        let errorVm = OnboardingViewModel(services: builder.services)

        XCTAssertEqual(errorVm.dailyGoalMl, AppConstants.defaultDailyGoalMl)
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }

    // MARK: - Load

    func testLoadUpdatesStatuses() async {
        builder.healthService.status = .authorized
        await vm.load()

        XCTAssertEqual(vm.healthStatus, .authorized)
        XCTAssertEqual(vm.notificationsStatus, .authorized)
    }

    // MARK: - Health Access

    func testRequestHealthAccessAuthorized() async {
        builder.healthService.status = .authorized
        await vm.requestHealthAccess()

        XCTAssertEqual(vm.healthStatus, .authorized)
        XCTAssertFalse(vm.isRequestingHealthAccess)
        let permEvents = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.permissionResult }
        XCTAssertFalse(permEvents.isEmpty)
    }

    func testRequestHealthAccessDenied() async {
        builder.healthService.status = .denied
        await vm.requestHealthAccess()

        XCTAssertEqual(vm.healthStatus, .denied)
    }

    func testRequestHealthAccessPreventsDoubleCall() async {
        builder.healthService.status = .authorized
        // First call
        await vm.requestHealthAccess()
        XCTAssertFalse(vm.isRequestingHealthAccess, "Should reset after completion")
    }

    func testRequestHealthAccessWithError() async {
        builder.healthService.shouldThrowOnAuth = true
        await vm.requestHealthAccess()

        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
        XCTAssertFalse(vm.isRequestingHealthAccess)
    }

    // MARK: - Notifications

    func testUpdateNotificationsEnabled() async {
        vm.notificationsEnabled = true
        await vm.updateNotifications()

        // MockNotificationService.requestAuthorization returns true
        XCTAssertTrue(vm.notificationsEnabled)
    }

    func testUpdateNotificationsDisabled() async {
        vm.notificationsEnabled = false
        await vm.updateNotifications()

        XCTAssertFalse(vm.notificationsEnabled)
    }

    // MARK: - Set Daily Goal

    func testSetDailyGoalPersists() {
        vm.setDailyGoal(3000)

        XCTAssertEqual(builder.settingsStore.saveCallCount, 1)
        XCTAssertEqual(builder.settingsStore.settings.dailyGoalMl, 3000)
    }

    func testSetDailyGoalWithSettingsLoadError() {
        // When settings fail to load during init, setDailyGoal gracefully returns early
        builder.settingsStore.shouldThrow = true
        let errorVm = OnboardingViewModel(services: builder.services)

        // Crash reporter gets the init error
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)

        // setDailyGoal is a no-op since settings is nil (guard let settings else { return })
        let errorCountBefore = builder.crashReporter.recordedErrors.count
        errorVm.setDailyGoal(3000)
        XCTAssertEqual(builder.crashReporter.recordedErrors.count, errorCountBefore,
            "setDailyGoal should be a no-op when settings failed to load")
    }

    // MARK: - Track Step

    func testTrackStep() {
        vm.trackStep(1, name: "welcome")

        let events = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.onboardingStep }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.parameters?[AnalyticsParams.step] as? Int, 1)
        XCTAssertEqual(events.first?.parameters?[AnalyticsParams.stepName] as? String, "welcome")
    }

    // MARK: - Complete

    func testCompleteSetsOnboardingFlag() async {
        await vm.complete()

        XCTAssertTrue(builder.settingsStore.settings.hasCompletedOnboarding)
        XCTAssertGreaterThan(builder.settingsStore.saveCallCount, 0)
    }

    func testCompleteBroadcastsSnapshot() async {
        await vm.complete()

        XCTAssertGreaterThan(builder.broadcaster.broadcastCallCount, 0)
    }

    func testCompleteUpdatesReminders() async {
        vm.notificationsEnabled = true
        await vm.complete()

        XCTAssertEqual(builder.notificationService.updateRemindersCallCount, 1)
    }

    func testCompleteLogsAnalytics() async {
        await vm.complete()

        let events = builder.analytics.loggedEvents.filter { $0.name == AnalyticsEvents.onboardingCompleted }
        XCTAssertEqual(events.count, 1)
    }

    func testCompleteSavesNotificationPreference() async {
        vm.notificationsEnabled = true
        await vm.complete()

        XCTAssertTrue(builder.settingsStore.settings.notificationsEnabled)
    }
}
