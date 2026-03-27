//
//  WidgetSmallView.swift
//  GlassWaterWidgetExtension
//

import AppIntents
import SwiftUI
import WidgetKit

struct WidgetSmallView: View {
    let progress: Double
    let currentFormatted: String
    let goalFormatted: String
    let remainingFormatted: String
    let lastIntakeText: String
    let quickAddAmountMl: Int
    let customAmountMl: Int

    private var statusMessage: String {
        if progress >= 1.0 {
            return String(localized: "widget_status_complete")
        } else if progress >= 0.75 {
            return String(localized: "widget_status_almost")
        } else if progress >= 0.5 {
            return String(localized: "widget_status_halfway")
        } else if progress > 0 {
            return String(localized: "widget_status_keep_going")
        } else {
            return String(localized: "widget_status_start")
        }
    }

    private var statusIcon: String {
        if progress >= 1.0 { return "checkmark.circle.fill" }
        if progress >= 0.75 { return "flame.fill" }
        if progress >= 0.5 { return "bolt.fill" }
        return "drop.fill"
    }

    private var isGoalReached: Bool { progress >= 1.0 }
    private var ringColor: Color { isGoalReached ? .green : .cyan }

    var body: some View {
        VStack(spacing: 4) {
            // Progress ring with water drop
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ringColor.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 24,
                            endRadius: 42
                        )
                    )
                    .frame(width: 84, height: 84)

                // Background ring
                Circle()
                    .stroke(ringColor.opacity(0.15), lineWidth: 7)
                    .frame(width: 66, height: 66)

                // Progress ring with gradient
                Circle()
                    .trim(from: 0, to: min(progress, 1.0))
                    .stroke(
                        AngularGradient(
                            colors: isGoalReached
                                ? [Color.green.opacity(0.6), Color.green, Color.mint, Color.green.opacity(0.6)]
                                : [Color.cyan.opacity(0.6), Color.cyan, Color.blue, Color.cyan.opacity(0.6)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 66, height: 66)

                // Center content
                VStack(spacing: 1) {
                    Image(systemName: isGoalReached ? "checkmark.circle.fill" : "drop.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isGoalReached
                                    ? [Color.green, Color.mint]
                                    : [Color.cyan, Color.blue],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                // Sparkle decorations when goal reached
                if isGoalReached {
                    ForEach(0..<4, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 6, weight: .semibold))
                            .foregroundStyle(Color.green.opacity(0.6))
                            .offset(
                                x: CGFloat(cos(Double(i) * .pi / 2)) * 40,
                                y: CGFloat(sin(Double(i) * .pi / 2)) * 40
                            )
                    }
                }
            }

            // Values
            HStack(spacing: 3) {
                Text(currentFormatted)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("/")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)

                Text(goalFormatted)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Quick add buttons
            if #available(iOS 17.0, *) {
                HStack(spacing: 4) {
                    Button(intent: addIntent(for: quickAddAmountMl, source: .widget, widgetFamily: "small")) {
                        WidgetQuickAddButtonLabel(amountMl: quickAddAmountMl, iconSystemName: "plus", style: .small)
                    }
                    .buttonStyle(.plain)

                    Button(intent: addIntent(for: customAmountMl, source: .widget, widgetFamily: "small")) {
                        WidgetQuickAddButtonLabel(amountMl: customAmountMl, iconSystemName: "slider.horizontal.3", style: .small)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(progress * 100))%, \(currentFormatted) / \(goalFormatted). \(statusMessage)")
    }
}
