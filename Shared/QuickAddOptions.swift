//
//  QuickAddOptions.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

struct QuickAddOption: Identifiable, Hashable {
    let percent: Int
    let amountMl: Int

    var id: Int { percent }
}

struct QuickAddAmountOption: Identifiable, Hashable {
    let id: String
    let amountMl: Int
}

enum QuickAddOptions {
    private static let imperialStepOz = 0.5

    static func options(forGoalMl goalMl: Int) -> [QuickAddOption] {
        AppConstants.quickAddPercents.map { percent in
            QuickAddOption(
                percent: percent,
                amountMl: amount(forPercent: percent, goalMl: goalMl)
            )
        }
    }

    static func options(forGoalMl goalMl: Int, percents: [Int]) -> [QuickAddOption] {
        let resolvedPercents = resolvePercents(percents)
        return resolvedPercents.map { percent in
            QuickAddOption(
                percent: percent,
                amountMl: amount(forPercent: percent, goalMl: goalMl)
            )
        }
    }

    static func amount(forPercent percent: Int, goalMl: Int) -> Int {
        let rawAmount = Int(Double(goalMl) * Double(percent) / 100.0)
        let rounded = roundedForCurrentUnit(rawAmount, metricStepMl: AppConstants.quickAddStepMl)
        return max(AppConstants.quickAddMinMl, min(rounded, AppConstants.quickAddMaxMl))
    }

    static func resolvedCustomAmount(forGoalMl goalMl: Int, customAmountMl: Int?) -> Int {
        let fallbackPercent = AppConstants.quickAddPercents.last ?? 25
        let fallbackAmount = amount(forPercent: fallbackPercent, goalMl: goalMl)
        let resolved = customAmountMl ?? fallbackAmount
        return clampCustomAmount(resolved)
    }

    static func liveActivityOptions(forGoalMl goalMl: Int, customAmountMl: Int?) -> [QuickAddAmountOption] {
        let quickAddAmount = amount(forPercent: 10, goalMl: goalMl)
        let customAmount = resolvedCustomAmount(forGoalMl: goalMl, customAmountMl: customAmountMl)

        var result = [QuickAddAmountOption(id: "quick", amountMl: quickAddAmount)]
        if customAmount != quickAddAmount {
            result.append(QuickAddAmountOption(id: "custom", amountMl: customAmount))
        }
        return result
    }

    static func customAmounts() -> [Int] {
        stride(
            from: AppConstants.customAmountMinMl,
            through: AppConstants.customAmountMaxMl,
            by: AppConstants.customAmountStepMl
        ).map { $0 }
    }

    static func clampCustomAmount(_ amount: Int) -> Int {
        let rounded = roundedForCurrentUnit(amount, metricStepMl: AppConstants.customAmountStepMl)
        return max(AppConstants.customAmountMinMl, min(rounded, AppConstants.customAmountMaxMl))
    }

    static func stepMlForCurrentUnit(metricStepMl: Int) -> Int {
        guard VolumeFormatters.currentUnit.resolved == .oz else { return metricStepMl }
        return max(1, VolumeFormatters.ml(fromFluidOunces: imperialStepOz))
    }

    private static func roundedToStep(_ value: Int, step: Int) -> Int {
        guard step > 0 else { return value }
        return Int((Double(value) / Double(step)).rounded() * Double(step))
    }

    private static func roundedForCurrentUnit(_ value: Int, metricStepMl: Int) -> Int {
        roundedToStep(value, step: stepMlForCurrentUnit(metricStepMl: metricStepMl))
    }

    private static func resolvePercents(_ percents: [Int]) -> [Int] {
        let fallback = AppConstants.quickAddPercents
        let input = percents.isEmpty ? fallback : percents
        var seen = Set<Int>()
        return input.filter { percent in
            guard !seen.contains(percent) else { return false }
            seen.insert(percent)
            return true
        }
    }
}
