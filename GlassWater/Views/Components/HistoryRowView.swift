//
//  HistoryRowView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI

struct HistoryRowView: View {
    let summary: DailyIntakeSummary
    let streakDay: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    init(summary: DailyIntakeSummary, streakDay: Bool = false, onTap: @escaping () -> Void) {
        self.summary = summary
        self.streakDay = streakDay
        self.onTap = onTap
    }

    private var formattedAmount: String {
        VolumeFormatters.string(fromMl: summary.amountMl, unitStyle: .short)
    }

    private var formattedDate: String {
        if summary.isToday {
            return String(localized: "history_today")
        } else if summary.isYesterday {
            return String(localized: "history_yesterday")
        } else {
            return summary.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }

    private var progressPercent: String {
        "\(Int(summary.progress * 100))%"
    }

    private var entriesLabel: String {
        let count = summary.entryCount
        if count == 0 {
            return String(localized: "history_no_entries")
        } else if count == 1 {
            return String(localized: "history_one_entry")
        } else {
            return String(localized: "history_entries_count \(count)")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Glowing drop icon
            dropIcon

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Date and badge row
                HStack(spacing: 8) {
                    Text(formattedDate)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.onTimeOfDayText)

                    if summary.isGoalMet {
                        goalMetBadge
                    } else if streakDay {
                        streakBadge
                    }

                    Spacer()
                }

                // Amount and entries
                HStack(spacing: 6) {
                    Text(formattedAmount)
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.onTimeOfDayText)

                    Text("•")
                        .foregroundStyle(Color.onTimeOfDayTertiaryText)

                    Text(entriesLabel)
                        .font(.caption)
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }

                // Mini progress bar
                progressBar
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.onTimeOfDayTertiaryText)
        }
        .padding(14)
        .background(Color.onTimeOfDayCardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1.0)
        .brightness(isPressed ? 0.05 : 0)
        .animation(reduceMotion ? .none : .spring(.snappy), value: isPressed)
        .contentShape(Rectangle())
        .sensoryFeedback(.selection, trigger: isPressed) { old, new in
            !old && new
        }
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            isPressed = pressing
        }, perform: {
            onTap()
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(String(localized: "history_row_accessibility_hint"))
    }

    // MARK: - Subviews

    private var dropIcon: some View {
        ZStack {
            // Glow circle
            Circle()
                .fill(Color.waterDrop.opacity(summary.isGoalMet ? 0.25 : 0.15))
                .frame(width: 44, height: 44)

            // Drop icon
            Image(systemName: "drop.fill")
                .font(.body)
                .foregroundStyle(summary.amountMl > 0 ? Color.waterDrop : Color.onTimeOfDayTertiaryText)
                .shadow(
                    color: summary.isGoalMet ? Color.waterDrop.opacity(0.5) : Color.clear,
                    radius: 6
                )
        }
    }

    private var goalMetBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
            Text("history_goal_met")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(Color.green.opacity(0.15))
        }
    }

    private var streakBadge: some View {
        HStack(spacing: 2) {
            Text("🔥")
                .font(.caption2)
            Text("history_streak")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(Color.orange.opacity(0.15))
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.onTimeOfDayTertiaryText.opacity(0.16))

                // Progress fill
                Capsule()
                    .fill(progressGradient)
                    .frame(width: geo.size.width * min(summary.progress, 1.0))
                    .shadow(
                        color: summary.progress > 0.5 ? Color.waterDrop.opacity(0.3) : Color.clear,
                        radius: 4,
                        y: 1
                    )
            }
        }
        .frame(height: 5)
    }

    private var progressGradient: LinearGradient {
        if summary.isGoalMet {
            return LinearGradient(
                colors: [Color.green.opacity(0.8), Color.green],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient.waterGradient
        }
    }

    private var accessibilityLabel: String {
        var label = "\(formattedDate), \(formattedAmount)"
        if summary.isGoalMet {
            label += ", \(String(localized: "history_goal_met"))"
        }
        label += ", \(entriesLabel)"
        label += ", \(progressPercent) \(String(localized: "history_of_goal"))"
        return label
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        HistoryRowView(
            summary: DailyIntakeSummary(
                date: Date(),
                amountMl: 2100,
                goalMl: 2000,
                entryCount: 6,
                entries: []
            ),
            streakDay: false,
            onTap: {}
        )

        HistoryRowView(
            summary: DailyIntakeSummary(
                date: Date().addingTimeInterval(-86400),
                amountMl: 1850,
                goalMl: 2000,
                entryCount: 4,
                entries: []
            ),
            streakDay: true,
            onTap: {}
        )

        HistoryRowView(
            summary: DailyIntakeSummary(
                date: Date().addingTimeInterval(-86400 * 2),
                amountMl: 500,
                goalMl: 2000,
                entryCount: 2,
                entries: []
            ),
            streakDay: false,
            onTap: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
