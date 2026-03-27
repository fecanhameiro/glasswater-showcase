//
//  GlassWaterLiveActivityAttributes.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

#if os(iOS)
import ActivityKit
import Foundation

struct GlassWaterLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
        var currentMl: Int
        var remainingMl: Int
        var goalReached: Bool
        var lastIntakeMl: Int?
        var lastIntakeDate: Date?
        var isSensitive: Bool
        var customAmountMl: Int
    }

    var dailyGoalMl: Int
}
#endif
