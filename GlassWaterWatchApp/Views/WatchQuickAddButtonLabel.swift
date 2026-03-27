//
//  WatchQuickAddButtonLabel.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchQuickAddButtonLabel: View {
    let amountMl: Int
    let isCompletingGoal: Bool
    let metrics: WatchLayoutMetrics

    private var formattedAmount: String {
        VolumeFormatters.string(fromMl: amountMl, unitStyle: .short)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isCompletingGoal ? "flag.checkered" : "drop.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.cyan)

            Text(formattedAmount)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.watchTextPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.buttonVerticalPadding)
        .accessibilityLabel(Text(isCompletingGoal
            ? "\(formattedAmount), \(String(localized: "watch_accessibility_complete_goal"))"
            : "\(formattedAmount)"))
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.watchButtonFillTop, Color.watchButtonFillBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.watchButtonBorderTop, Color.watchButtonBorderBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.watchButtonHighlight, Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
    }
}
