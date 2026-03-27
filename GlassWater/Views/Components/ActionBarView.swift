//
//  ActionBarView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI
struct ActionBarView: View {
    let quickAddOptions: [QuickAddOption]
    let customAmountMl: Int
    let onAdd: (Int) -> Void
    let onCustom: () -> Void

    @State private var hapticTrigger = 0

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(quickAddOptions) { option in
                    Button {
                        hapticTrigger += 1
                        onAdd(option.amountMl)
                    } label: {
                        QuickAddButtonLabel(percent: option.percent, amountMl: option.amountMl)
                    }
                    .glassEffect(.regular.tint(Color.cyan.opacity(0.15)).interactive(), in: .capsule)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text(accessibilityLabel(for: option)))
                }

                Button {
                    hapticTrigger += 1
                    onCustom()
                } label: {
                    CustomAddButtonLabel(amountMl: customAmountMl)
                }
                .glassEffect(.regular.tint(Color.cyan.opacity(0.15)).interactive(), in: .capsule)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(customAccessibilityLabel))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    private func accessibilityLabel(for option: QuickAddOption) -> String {
        let formatted = VolumeFormatters.string(fromMl: option.amountMl, unitStyle: .short)
        return Localized.string(
            "home_add_percent_accessibility %d %@",
            option.percent,
            formatted
        )
    }

    private var customAccessibilityLabel: String {
        let formatted = VolumeFormatters.string(fromMl: customAmountMl, unitStyle: .short)
        return Localized.string("home_add_custom_accessibility %@", formatted)
    }
}

private struct QuickAddButtonLabel: View {
    let percent: Int
    let amountMl: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.lightenedNightBackground) private var lightenedNight

    private var hasLightBg: Bool {
        lightenedNight || TimeOfDayPeriod.current.hasLightBackground
    }
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white
            : hasLightBg ? Color(red: 0.08, green: 0.08, blue: 0.12) : .white
    }
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.85)
            : hasLightBg ? Color(red: 0.2, green: 0.2, blue: 0.25) : .white.opacity(0.85)
    }

    private var formattedAmount: String {
        VolumeFormatters.string(fromMl: amountMl, unitStyle: .short)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(Localized.string("home_add_percent %d", percent))
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)

            Text(Localized.string("home_add_amount %@", formattedAmount))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

private struct CustomAddButtonLabel: View {
    let amountMl: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.lightenedNightBackground) private var lightenedNight

    private var hasLightBg: Bool {
        lightenedNight || TimeOfDayPeriod.current.hasLightBackground
    }
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white
            : hasLightBg ? Color(red: 0.08, green: 0.08, blue: 0.12) : .white
    }
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.85)
            : hasLightBg ? Color(red: 0.2, green: 0.2, blue: 0.25) : .white.opacity(0.85)
    }

    private var formattedAmount: String {
        VolumeFormatters.string(fromMl: amountMl, unitStyle: .short)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("home_add_other")
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.waterDrop)

                Text(formattedAmount)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}
