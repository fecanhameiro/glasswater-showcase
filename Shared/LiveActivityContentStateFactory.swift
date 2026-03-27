//
//  LiveActivityContentStateFactory.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

#if os(iOS)
import Foundation

enum LiveActivityContentStateFactory {
    static func make(
        currentMl: Int,
        dailyGoalMl: Int,
        lastIntakeMl: Int?,
        lastIntakeDate: Date?,
        isSensitive: Bool,
        customAmountMl: Int?
    ) -> GlassWaterLiveActivityAttributes.ContentState {
        let progress = dailyGoalMl > 0 ? min(Double(currentMl) / Double(dailyGoalMl), 1) : 0
        let remainingMl = max(dailyGoalMl - currentMl, 0)
        let goalReached = dailyGoalMl > 0 && currentMl >= dailyGoalMl
        let resolvedCustomAmount = QuickAddOptions.resolvedCustomAmount(
            forGoalMl: dailyGoalMl,
            customAmountMl: customAmountMl
        )
        return GlassWaterLiveActivityAttributes.ContentState(
            progress: progress,
            currentMl: currentMl,
            remainingMl: remainingMl,
            goalReached: goalReached,
            lastIntakeMl: lastIntakeMl,
            lastIntakeDate: lastIntakeDate,
            isSensitive: isSensitive,
            customAmountMl: resolvedCustomAmount
        )
    }
}
#endif
