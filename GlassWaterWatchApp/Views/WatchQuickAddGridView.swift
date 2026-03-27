//
//  WatchQuickAddGridView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchQuickAddGridView: View {
    let quickAddAmountMl: Int
    let isCompletingGoal: Bool
    let customAmountMl: Int
    let metrics: WatchLayoutMetrics
    let onAdd: (Int) -> Void
    let onCustom: () -> Void

    var body: some View {
        HStack(spacing: metrics.buttonSpacing) {
            Button {
                onAdd(quickAddAmountMl)
            } label: {
                WatchQuickAddButtonLabel(
                    amountMl: quickAddAmountMl,
                    isCompletingGoal: isCompletingGoal,
                    metrics: metrics
                )
            }
            .buttonStyle(.plain)

            Button {
                onCustom()
            } label: {
                WatchCustomButtonLabel(
                    amountMl: customAmountMl,
                    metrics: metrics
                )
            }
            .buttonStyle(.plain)
        }
    }
}
