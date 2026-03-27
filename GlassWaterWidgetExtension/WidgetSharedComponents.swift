//
//  WidgetSharedComponents.swift
//  GlassWaterWidgetExtension
//

import SwiftUI
import WidgetKit

// MARK: - Intent Helper

func addIntent(
    for amount: Int,
    source: HydrationSnapshotSourceIntent,
    widgetFamily: String = ""
) -> AddWaterIntent {
    let intent = AddWaterIntent()
    intent.amountMl = amount
    intent.source = source
    intent.widgetFamily = widgetFamily
    return intent
}

// MARK: - Stat Card

struct WidgetStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(color.opacity(0.12))
                )

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.1), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(0.15), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Progress Ring (Gauge-based, for accessory widgets)

struct WidgetProgressRingView: View {
    let progress: Double

    private var percentText: String {
        "\(Int(progress * 100))%"
    }

    var body: some View {
        Gauge(value: progress) {
            Text(" ")
        } currentValueLabel: {
            Text(percentText)
                .font(.caption.weight(.semibold))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.accentColor)
        .frame(width: 72, height: 72)
    }
}

// MARK: - Accessory Circular

struct WidgetAccessoryCircularView: View {
    let progress: Double

    private var percentText: String {
        "\(Int(progress * 100))%"
    }

    var body: some View {
        Gauge(value: progress) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text(percentText)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.accentColor)
    }
}

// MARK: - Accessory Rectangular

struct WidgetAccessoryRectangularView: View {
    let remainingFormatted: String
    let lastIntakeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("widget_remaining")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(remainingFormatted)
                .font(.caption.weight(.semibold))

            Text("widget_last_intake")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(lastIntakeText)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Quick Add Button Label

struct WidgetQuickAddButtonLabel: View {
    enum Style {
        case small
        case medium
        case large

        var fontSize: CGFloat {
            switch self {
            case .small: return 11
            case .medium: return 11
            case .large: return 14
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 9
            case .medium: return 10
            case .large: return 12
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 14
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 12
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 10
            case .large: return 14
            }
        }

        var showIcon: Bool { true }
    }

    let amountMl: Int
    var iconSystemName: String = "plus"
    var style: Style = .large

    private var formattedAmount: String {
        VolumeFormatters.string(fromMl: amountMl, unitStyle: .short)
    }

    var body: some View {
        HStack(spacing: 3) {
            if style.showIcon {
                Image(systemName: iconSystemName)
                    .font(.system(size: style.iconSize, weight: .bold))
                    .foregroundStyle(Color.cyan)
            }

            Text(formattedAmount)
                .font(.system(size: style.fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.12), Color.cyan.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .stroke(Color.cyan.opacity(0.25), lineWidth: 0.5)
                )
        )
        .accessibilityLabel(Localized.string("home_add_amount_accessibility %@", formattedAmount))
    }
}

// MARK: - Onboarding Placeholder

struct WidgetOnboardingView: View {
    let family: WidgetFamily

    private var iconSize: CGFloat {
        switch family {
        case .systemLarge: return 44
        case .systemMedium: return 28
        default: return 32
        }
    }

    private var titleFont: Font {
        switch family {
        case .systemLarge: return .title3.weight(.bold)
        case .systemMedium: return .subheadline.weight(.bold)
        default: return .caption.weight(.bold)
        }
    }

    private var subtitleFont: Font {
        switch family {
        case .systemLarge: return .subheadline.weight(.medium)
        case .systemMedium: return .caption.weight(.medium)
        default: return .caption2.weight(.medium)
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "drop.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.cyan.opacity(0.6))
                }
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GlassWater")
                            .font(.caption.weight(.bold))
                        Text("widget_onboarding_subtitle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            default:
                VStack(spacing: family == .systemLarge ? 16 : 10) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.cyan.opacity(0.15), Color.cyan.opacity(0.03), .clear],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: iconSize * 0.8
                                )
                            )
                            .frame(width: iconSize * 1.6, height: iconSize * 1.6)

                        Image(systemName: "drop.fill")
                            .font(.system(size: iconSize, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .cyan.opacity(0.3), radius: 6, y: 2)
                    }

                    VStack(spacing: 4) {
                        Text("GlassWater")
                            .font(titleFont)
                            .foregroundStyle(.primary)

                        Text(family == .systemSmall ? "widget_onboarding_short" : "widget_onboarding_subtitle")
                            .font(subtitleFont)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
