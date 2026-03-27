//
//  WidgetMediumView.swift
//  GlassWaterWidgetExtension
//

import AppIntents
import SwiftUI
import WidgetKit

struct WidgetMediumView: View {
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
        HStack(spacing: 12) {
                // Left section: Progress ring with info
                VStack(spacing: 6) {
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [ringColor.opacity(0.12), Color.clear],
                                    center: .center,
                                    startRadius: 25,
                                    endRadius: 45
                                )
                            )
                            .frame(width: 90, height: 90)

                        // Background ring
                        Circle()
                            .stroke(ringColor.opacity(0.15), lineWidth: 7)
                            .frame(width: 68, height: 68)

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
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 68, height: 68)

                        // Center content
                        VStack(spacing: 1) {
                            Image(systemName: isGoalReached ? "checkmark.circle.fill" : "drop.fill")
                                .font(.system(size: 12, weight: .medium))
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
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }

                        // Sparkle decorations when goal reached
                        if isGoalReached {
                            ForEach(0..<4, id: \.self) { i in
                                Image(systemName: "sparkle")
                                    .font(.system(size: 6, weight: .semibold))
                                    .foregroundStyle(Color.green.opacity(0.6))
                                    .offset(
                                        x: CGFloat(cos(Double(i) * .pi / 2)) * 42,
                                        y: CGFloat(sin(Double(i) * .pi / 2)) * 42
                                    )
                            }
                        }
                    }

                    // Main values below ring
                    VStack(spacing: 0) {
                        Text(currentFormatted)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("/ \(goalFormatted)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 95)

            // Right section: Status + Info + Buttons
            VStack(alignment: .leading, spacing: 8) {
                // Status badge
                HStack(spacing: 3) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 9, weight: .semibold))
                    Text(statusMessage)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(progress >= 1.0 ? Color.green : Color.cyan)

                // Info cards row - cyan theme
                HStack(spacing: 6) {
                    // Remaining card
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.cyan)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("widget_remaining")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(remainingFormatted)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.1), Color.cyan.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.cyan.opacity(0.15), lineWidth: 0.5)
                            )
                    )

                    // Last intake card
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.blue)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("widget_last_intake")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(lastIntakeText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.08), Color.blue.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.blue.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                }

                // Quick add buttons
                if #available(iOS 17.0, *) {
                    HStack(spacing: 6) {
                        Button(intent: addIntent(for: quickAddAmountMl, source: .widget, widgetFamily: "medium")) {
                            WidgetQuickAddButtonLabel(amountMl: quickAddAmountMl, iconSystemName: "plus", style: .medium)
                        }
                        .buttonStyle(.plain)

                        Button(intent: addIntent(for: customAmountMl, source: .widget, widgetFamily: "medium")) {
                            WidgetQuickAddButtonLabel(amountMl: customAmountMl, iconSystemName: "slider.horizontal.3", style: .medium)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(progress * 100))%, \(currentFormatted) / \(goalFormatted). \(statusMessage). \(String(localized: "widget_remaining")): \(remainingFormatted)")
    }
}
