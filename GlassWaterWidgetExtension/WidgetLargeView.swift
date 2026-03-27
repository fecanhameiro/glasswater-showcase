//
//  WidgetLargeView.swift
//  GlassWaterWidgetExtension
//

import AppIntents
import SwiftUI
import WidgetKit

struct WidgetLargeView: View {
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

    private var isGoalReached: Bool { progress >= 1.0 }
    private var ringColor: Color { isGoalReached ? .green : .cyan }

    var body: some View {
        VStack(spacing: 0) {
                // Hero section with ring and values
                HStack(spacing: 20) {
                    // Large progress ring
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [ringColor.opacity(0.15), Color.clear],
                                    center: .center,
                                    startRadius: 35,
                                    endRadius: 65
                                )
                            )
                            .frame(width: 130, height: 130)

                        // Background ring
                        Circle()
                            .stroke(ringColor.opacity(0.15), lineWidth: 10)
                            .frame(width: 100, height: 100)

                        // Progress ring
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
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 100, height: 100)

                        // Center content
                        VStack(spacing: 2) {
                            Image(systemName: isGoalReached ? "checkmark.circle.fill" : "drop.fill")
                                .font(.system(size: 20, weight: .medium))
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
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }

                        // Sparkle decorations when goal reached
                        if isGoalReached {
                            ForEach(0..<4, id: \.self) { i in
                                Image(systemName: "sparkle")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Color.green.opacity(0.6))
                                    .offset(
                                        x: CGFloat(cos(Double(i) * .pi / 2)) * 58,
                                        y: CGFloat(sin(Double(i) * .pi / 2)) * 58
                                    )
                            }
                        }
                    }

                    // Main info
                    VStack(alignment: .leading, spacing: 6) {
                        // Status badge
                        Text(statusMessage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ringColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(ringColor.opacity(0.15))
                            )

                        // Current value
                        Text(currentFormatted)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Text("/ \(goalFormatted)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 16)

                // Stats cards row
                HStack(spacing: 10) {
                    // Remaining card
                    WidgetStatCard(
                        icon: "arrow.down.to.line",
                        title: String(localized: "widget_remaining"),
                        value: remainingFormatted,
                        color: .orange
                    )

                    // Last intake card
                    WidgetStatCard(
                        icon: "clock",
                        title: String(localized: "widget_last_intake"),
                        value: lastIntakeText,
                        color: .blue
                    )
                }
                .padding(.bottom, 16)

                Spacer(minLength: 0)

                // Quick add buttons
                if #available(iOS 17.0, *) {
                    VStack(spacing: 8) {
                        Text("widget_quick_add")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 10) {
                            Button(intent: addIntent(for: quickAddAmountMl, source: .widget, widgetFamily: "large")) {
                                WidgetQuickAddButtonLabel(amountMl: quickAddAmountMl, iconSystemName: "plus", style: .large)
                            }
                            .buttonStyle(.plain)

                            Button(intent: addIntent(for: customAmountMl, source: .widget, widgetFamily: "large")) {
                                WidgetQuickAddButtonLabel(amountMl: customAmountMl, iconSystemName: "slider.horizontal.3", style: .large)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(progress * 100))%, \(currentFormatted) / \(goalFormatted). \(statusMessage). \(String(localized: "widget_remaining")): \(remainingFormatted)")
    }
}
