//
//  TipJarViewModel.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 19/03/26.
//

import StoreKit
import SwiftUI

@MainActor
@Observable
final class TipJarViewModel {
    nonisolated deinit {}
    private let tipJarService: any TipJarServicing
    private let settingsStore: any SettingsStore
    private let analytics: any AnalyticsTracking
    private let crashReporter: any CrashReporting

    var products: [Product] = []
    var isLoading = true
    var purchasingProductID: String?
    var showThankYou = false
    var errorMessage: String?
    var hasTipped = false

    init(services: AppServices) {
        self.tipJarService = services.tipJar
        self.settingsStore = services.settingsStore
        self.analytics = services.analytics
        self.crashReporter = services.crashReporter
    }

    func loadTipStatus() {
        if let settings = try? settingsStore.loadOrCreate() {
            hasTipped = settings.hasTipped
        }
    }

    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            products = try await tipJarService.fetchProducts()
        } catch {
            crashReporter.record(error: error)
            errorMessage = String(localized: "settings_tip_jar_unavailable")
        }

        isLoading = false
    }

    private var thankYouTask: Task<Void, Never>?

    func purchase(_ product: Product) async {
        purchasingProductID = product.id
        errorMessage = nil
        defer { purchasingProductID = nil }

        do {
            let result = try await tipJarService.purchase(product)

            switch result {
            case .success:
                analytics.logEvent("tip_purchased", parameters: [
                    "tip_product_id": product.id,
                    "tip_price": product.displayPrice
                ])

                // Persist immediately but delay UI update
                do {
                    let settings = try settingsStore.loadOrCreate()
                    settings.hasTipped = true
                    try settingsStore.save()
                    NotificationCenter.default.post(name: .settingsDidChange, object: nil)
                } catch {
                    crashReporter.record(error: error)
                }

                thankYouTask?.cancel()
                withAnimation(.spring(.bouncy)) {
                    showThankYou = true
                }
                thankYouTask = Task {
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(.smooth)) {
                        showThankYou = false
                    }
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(.bouncy)) {
                        hasTipped = true
                    }
                }

            case .cancelled:
                break

            case .pending:
                break
            }
        } catch {
            crashReporter.record(error: error)
            errorMessage = String(localized: "settings_tip_jar_unavailable")
        }
    }
}
