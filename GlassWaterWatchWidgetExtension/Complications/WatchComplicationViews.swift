//
//  WatchComplicationViews.swift
//  GlassWaterWatch Watch App
//

import SwiftUI
import WidgetKit

// MARK: - Main Complication View (dispatches by family)

struct WatchComplicationView: View {
    let entry: WatchComplicationEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            WatchCircularComplicationView(progress: entry.progress)
        case .accessoryRectangular:
            WatchRectangularComplicationView(
                currentMl: entry.currentMl,
                goalMl: entry.goalMl,
                remainingMl: entry.remainingMl,
                goalReached: entry.goalReached,
                lastEntryDate: entry.lastEntryDate
            )
        case .accessoryCorner:
            WatchCornerComplicationView(progress: entry.progress)
        case .accessoryInline:
            WatchInlineComplicationView(
                currentMl: entry.currentMl,
                goalMl: entry.goalMl
            )
        default:
            WatchCircularComplicationView(progress: entry.progress)
        }
    }
}

// MARK: - Circular (Gauge + Drop Icon)

struct WatchCircularComplicationView: View {
    let progress: Double

    var body: some View {
        Gauge(value: min(progress, 1.0)) {
            Image(systemName: "drop.fill")
                .foregroundStyle(.cyan)
        } currentValueLabel: {
            Text("\(Int(progress * 100))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.cyan)
    }
}

// MARK: - Rectangular (Current/Goal + Remaining)

struct WatchRectangularComplicationView: View {
    let currentMl: Int
    let goalMl: Int
    let remainingMl: Int
    let goalReached: Bool
    let lastEntryDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)

                Text("\(VolumeFormatters.string(fromMl: currentMl, unitStyle: .short)) / \(VolumeFormatters.string(fromMl: goalMl, unitStyle: .short))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }

            if goalReached {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("watch_status_complete")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if let lastDate = lastEntryDate {
                Text(Localized.string("watch_complication_last_entry %@", lastDate.formatted(date: .omitted, time: .shortened)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(Localized.string("watch_remaining %@", VolumeFormatters.string(fromMl: remainingMl, unitStyle: .short)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Gauge(value: min(Double(currentMl) / max(Double(goalMl), 1), 1.0)) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(.cyan)
        }
    }
}

// MARK: - Corner (Percentage + Gauge)

struct WatchCornerComplicationView: View {
    let progress: Double

    var body: some View {
        Text("\(Int(progress * 100))%")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.cyan)
            .widgetLabel {
                Gauge(value: min(progress, 1.0)) {
                    Image(systemName: "drop.fill")
                }
                .gaugeStyle(.accessoryLinear)
                .tint(.cyan)
            }
    }
}

// MARK: - Inline (Text Summary)

struct WatchInlineComplicationView: View {
    let currentMl: Int
    let goalMl: Int

    var body: some View {
        Text("\(Image(systemName: "drop.fill")) \(VolumeFormatters.string(fromMl: currentMl, unitStyle: .short)) / \(VolumeFormatters.string(fromMl: goalMl, unitStyle: .short))")
    }
}

// MARK: - Widget Configuration

struct GlassWaterWatchComplication: Widget {
    let kind = "GlassWaterWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WatchComplicationProvider()
        ) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName("watch_complication_title")
        .description("watch_complication_description")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }
}
