//
//  TipJarViewModelTests.swift
//  GlassWaterTests
//
//  Tests for TipJarViewModel — product loading, purchase flow,
//  settings persistence, and error handling.
//

import XCTest

@testable import GlassWater

@MainActor
final class TipJarViewModelTests: XCTestCase {
    private var builder: TestServicesBuilder!
    private var vm: TipJarViewModel!

    override func setUp() async throws {
        builder = TestServicesBuilder()
        vm = TipJarViewModel(services: builder.services)
    }

    override func tearDown() {
        builder = nil
        vm = nil
        super.tearDown()
    }

    // MARK: - Load Tip Status

    func testLoadTipStatusFromSettings() {
        builder.settingsStore.settings.hasTipped = true
        vm.loadTipStatus()

        XCTAssertTrue(vm.hasTipped)
    }

    func testLoadTipStatusDefaultFalse() {
        vm.loadTipStatus()
        XCTAssertFalse(vm.hasTipped)
    }

    func testLoadTipStatusWithSettingsError() {
        builder.settingsStore.shouldThrow = true
        vm.loadTipStatus()

        XCTAssertFalse(vm.hasTipped, "Should default to false on error")
    }

    // MARK: - Load Products

    func testLoadProductsSuccess() async {
        // MockTipJarService returns empty products by default
        await vm.loadProducts()

        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(builder.tipJar.fetchCallCount, 1)
    }

    func testLoadProductsStopsLoadingAfterFetch() async {
        // isLoading starts as true from init
        XCTAssertTrue(vm.isLoading)

        await vm.loadProducts()

        XCTAssertFalse(vm.isLoading, "isLoading must be false after fetch completes")
    }

    func testLoadProductsError() async {
        builder.tipJar.shouldThrow = true

        await vm.loadProducts()

        XCTAssertFalse(vm.isLoading)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(builder.crashReporter.recordedErrors.isEmpty)
    }

    // MARK: - Purchase (without real Product — limited scope)
    // Note: StoreKit Product cannot be instantiated in tests without StoreKit Testing.
    // We test the ViewModel state machine logic that doesn't require a real Product.

    func testInitialPurchaseState() {
        XCTAssertNil(vm.purchasingProductID)
        XCTAssertFalse(vm.showThankYou)
        XCTAssertNil(vm.errorMessage)
    }
}
