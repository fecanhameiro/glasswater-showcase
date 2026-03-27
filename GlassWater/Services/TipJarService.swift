//
//  TipJarService.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 19/03/26.
//

import StoreKit

enum TipJarPurchaseResult {
    case success
    case cancelled
    case pending
}

protocol TipJarServicing: Sendable {
    func fetchProducts() async throws -> [Product]
    func purchase(_ product: Product) async throws -> TipJarPurchaseResult
    func listenForTransactions(onVerified: @escaping @Sendable () async -> Void) -> Task<Void, Never>
}

final class TipJarService: TipJarServicing {
    private static let productIDs: [String] = [
        "com.glasswater.tip.droplet2",
        "com.glasswater.tip.glass2",
        "com.glasswater.tip.wave2",
        "com.glasswater.tip.waterfall2"
    ]

    func fetchProducts() async throws -> [Product] {
        let products = try await Product.products(for: Self.productIDs)
        return products.sorted { $0.price < $1.price }
    }

    func purchase(_ product: Product) async throws -> TipJarPurchaseResult {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            return .success

        case .userCancelled:
            return .cancelled

        case .pending:
            return .pending

        @unknown default:
            return .cancelled
        }
    }

    func listenForTransactions(onVerified: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await onVerified()
                case .unverified:
                    break
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.unknown
        case .verified(let value):
            return value
        }
    }
}
