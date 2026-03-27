//
//  GlassWaterError.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import Foundation

enum GlassWaterError: LocalizedError {
    case persistenceFailed(operation: String, underlying: Error)
    case healthKitUnavailable
    case healthKitAuthorizationDenied
    case healthKitSyncFailed(underlying: Error)
    case notificationSchedulingFailed(underlying: Error)
    case snapshotEncodingFailed
    case snapshotDecodingFailed
    case invalidAmount(Int)
    case invalidGoal(Int)
    case liveActivityUpdateFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let operation, _):
            return "Data operation failed: \(operation)"
        case .healthKitUnavailable:
            return "HealthKit is not available on this device"
        case .healthKitAuthorizationDenied:
            return "HealthKit authorization was denied"
        case .healthKitSyncFailed:
            return "Failed to sync with HealthKit"
        case .notificationSchedulingFailed:
            return "Failed to schedule notifications"
        case .snapshotEncodingFailed:
            return "Failed to encode hydration snapshot"
        case .snapshotDecodingFailed:
            return "Failed to decode hydration snapshot"
        case .invalidAmount(let amount):
            return "Invalid water amount: \(amount)ml"
        case .invalidGoal(let goal):
            return "Invalid daily goal: \(goal)ml"
        case .liveActivityUpdateFailed(let reason):
            return "Live Activity update failed: \(reason)"
        }
    }

    var underlyingError: Error? {
        switch self {
        case .persistenceFailed(_, let error),
             .healthKitSyncFailed(let error),
             .notificationSchedulingFailed(let error):
            return error
        default:
            return nil
        }
    }
}
