//
//  GlassWaterLiveActivityView.swift
//  GlassWaterWidgetExtension
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
struct GlassWaterLiveActivityView: View {
    let context: ActivityViewContext<GlassWaterLiveActivityAttributes>
    @State private var pulse = false
    @State private var pulseTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentFormatted: String {
        VolumeFormatters.string(fromMl: context.state.currentMl, unitStyle: .short)
    }

    private var goalFormatted: String {
        VolumeFormatters.string(fromMl: context.attributes.dailyGoalMl, unitStyle: .short)
    }

    private var remainingFormatted: String {
        VolumeFormatters.string(fromMl: context.state.remainingMl, unitStyle: .short)
    }

    private var hasLastIntake: Bool {
        context.state.lastIntakeDate != nil
    }

    private var lastIntakeText: String {
        guard let date = context.state.lastIntakeDate else {
            return String(localized: "live_activity_last_intake_empty")
        }
        let time = date.formatted(date: .omitted, time: .shortened)
        guard let amount = context.state.lastIntakeMl else {
            return time
        }
        let amountFormatted = VolumeFormatters.string(fromMl: amount, unitStyle: .short)
        return Localized.string("live_activity_last_intake_value %@ %@", amountFormatted, time)
    }

    private var quickAddOptions: [QuickAddAmountOption] {
        QuickAddOptions.liveActivityOptions(
            forGoalMl: context.attributes.dailyGoalMl,
            customAmountMl: context.state.customAmountMl
        )
    }

    // MARK: - Stale State (Day Rollover)

    private var yesterdaySummaryText: String {
        let amount = VolumeFormatters.string(fromMl: context.state.currentMl, unitStyle: .short)
        let percent = "\(Int(context.state.progress * 100))%"
        return Localized.string("live_activity_yesterday %@ %@", amount, percent)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.35),
                    Color.accentColor.opacity(0.12),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label {
                        Text("live_activity_title")
                    } icon: {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .font(.headline.weight(.semibold))

                    Spacer()

                    if context.isStale {
                        Text("live_activity_new_day")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    } else if context.state.goalReached {
                        Text("home_goal_reached")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    } else {
                        Text(Localized.string("live_activity_missing_value %@", remainingFormatted))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                }

                if context.isStale {
                    VStack(alignment: .leading, spacing: 6) {
                        if !context.state.isSensitive {
                            HStack(spacing: 4) {
                                if context.state.goalReached {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.green)
                                }
                                Text(yesterdaySummaryText)
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        Text("live_activity_new_day_subtitle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    LiveActivityProgressCapsule(
                        progress: 0,
                        height: 6,
                        accentColor: .cyan
                    )

                    GlassWaterLiveActivityQuickAddRow(options: quickAddOptions, style: .regular)
                } else if context.state.isSensitive {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("live_activity_private_title")
                            .font(.title3.weight(.semibold))

                        Text("live_activity_private_subtitle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Localized.string("home_progress_value %@ %@", currentFormatted, goalFormatted))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 8)

                        HStack(spacing: 4) {
                            Text("live_activity_last_intake")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(lastIntakeText)
                                .font(hasLastIntake ? .caption.weight(.semibold) : .caption2)
                                .foregroundStyle(hasLastIntake ? .primary : .secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }

                    LiveActivityProgressCapsule(
                        progress: context.state.progress,
                        height: 6,
                        accentColor: context.state.goalReached ? .green : .cyan
                    )

                    if context.state.goalReached {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                            Text("live_activity_goal_celebration")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                    } else {
                        GlassWaterLiveActivityQuickAddRow(options: quickAddOptions, style: .regular)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .scaleEffect(pulse ? 1.02 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(pulse ? 0.35 : 0), lineWidth: 1)
        )
        .animation(.spring(.smooth(duration: 0.22)), value: pulse)
        .onChange(of: context.state.currentMl) { _, _ in
            triggerPulse()
        }
        .activityBackgroundTint(.clear)
    }

    private func triggerPulse() {
        guard !reduceMotion else { return }
        pulseTask?.cancel()
        pulse = true
        pulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            pulse = false
        }
    }
}

// MARK: - Progress Capsule

/// Clean gradient progress capsule for Live Activity and Dynamic Island.
/// Uses smooth fill instead of wave shape for crisp rendering at small sizes.
@available(iOS 16.2, *)
struct LiveActivityProgressCapsule: View {
    let progress: Double
    var height: CGFloat = 6
    var accentColor: Color = .cyan

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.6), accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(max(progress, 0), 1.0))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

// MARK: - Quick Add Row

@available(iOS 16.2, *)
struct GlassWaterLiveActivityQuickAddRow: View {
    enum Style {
        case regular
        case compact

        var font: Font {
            switch self {
            case .regular:
                return .subheadline.weight(.semibold)
            case .compact:
                return .caption.weight(.semibold)
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .regular:
                return 8
            case .compact:
                return 6
            }
        }
    }

    let options: [QuickAddAmountOption]
    let style: Style

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                Button(intent: addIntent(for: option.amountMl, source: .liveActivity)) {
                    let formatted = VolumeFormatters.string(fromMl: option.amountMl, unitStyle: .short)
                    HStack(spacing: 3) {
                        Image(systemName: iconName(for: option))
                            .font(.system(size: style == .regular ? 10 : 9, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text(formatted)
                            .font(style.font)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, style == .compact ? 8 : 0)
                    .padding(.vertical, style.verticalPadding)
                    .background(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.18), Color.cyan.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(Color.cyan.opacity(0.25), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconName(for option: QuickAddAmountOption) -> String {
        option.id == "custom" ? "slider.horizontal.3" : "plus"
    }
}
