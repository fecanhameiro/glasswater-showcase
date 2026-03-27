//
//  HourlyChartView.swift
//  GlassWater
//

import Charts
import SwiftUI

struct HourlyDataPoint: Identifiable {
    let id = UUID()
    let hour: Int
    let amount: Int
    let isPeak: Bool
    let isCurrent: Bool

    var hourLabel: String {
        "\(hour)h"
    }
}

// MARK: - Premium Hourly Chart

struct HourlyChartView: View {
    let entriesByHour: [Int: Int]
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedHour: Int?
    @State private var animationProgress: CGFloat = 0
    @State private var tooltipDismissTask: Task<Void, Never>?

    private let currentHour = Calendar.current.component(.hour, from: Date())
    private let margin = 1 // Hours of margin on each side
    private let minRangeHours = 6 // Minimum hours to show (prevents bars from being too wide)

    // Dynamic hour range based on data
    private var hourRange: ClosedRange<Int> {
        let hoursWithData = entriesByHour.filter { $0.value > 0 }.keys

        guard !hoursWithData.isEmpty else {
            // Default: show around current hour if no data
            let halfRange = minRangeHours / 2
            let start = max(0, currentHour - halfRange)
            let end = min(23, currentHour + halfRange)
            return start...end
        }

        let minHour = hoursWithData.min() ?? currentHour
        let maxHour = hoursWithData.max() ?? currentHour

        // Include current hour in range
        let adjustedMin = min(minHour, currentHour)
        let adjustedMax = max(maxHour, currentHour)

        // Add margin
        var start = adjustedMin - margin
        var end = adjustedMax + margin

        // Ensure minimum range for good bar width
        let currentSpan = end - start
        if currentSpan < minRangeHours {
            let padding = (minRangeHours - currentSpan) / 2
            start -= padding
            end += padding
        }

        // Clamp to 0-23
        start = max(0, start)
        end = min(23, end)

        // If clamping made range too small, expand the other direction
        let finalSpan = end - start
        if finalSpan < minRangeHours {
            if start == 0 {
                end = min(23, minRangeHours)
            } else if end == 23 {
                start = max(0, 23 - minRangeHours)
            }
        }

        return start...end
    }

    // Number of bars in current range
    private var barCount: Int {
        hourRange.upperBound - hourRange.lowerBound + 1
    }

    private var chartData: [HourlyDataPoint] {
        let maxAmount = entriesByHour.values.max() ?? 0
        let peakHour = entriesByHour.max(by: { $0.value < $1.value })?.key

        return (hourRange).map { hour in
            HourlyDataPoint(
                hour: hour,
                amount: entriesByHour[hour] ?? 0,
                isPeak: hour == peakHour && maxAmount > 0,
                isCurrent: hour == currentHour
            )
        }
    }

    private var maxAmount: Int {
        max(entriesByHour.values.max() ?? 1, 1)
    }

    // Dynamic labels based on range
    private var displayHours: [Int] {
        let range = hourRange
        let span = range.upperBound - range.lowerBound

        if span <= 6 {
            // Small range: show every 2 hours
            return stride(from: range.lowerBound, through: range.upperBound, by: 2).map { $0 }
        } else if span <= 12 {
            // Medium range: show every 3 hours
            return stride(from: range.lowerBound, through: range.upperBound, by: 3).map { $0 }
        } else {
            // Large range: show every 4-6 hours
            return stride(from: range.lowerBound, through: range.upperBound, by: 4).map { $0 }
        }
    }

    private var selectedDataPoint: HourlyDataPoint? {
        guard let hour = selectedHour else { return nil }
        return chartData.first { $0.hour == hour }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Tooltip
            tooltipView
                .frame(height: 28)
                .zIndex(100)

            // Chart
            chartView
                .frame(height: 80)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(chartAccessibilityLabel)
                .accessibilityHint(String(localized: "chart_accessibility_hint"))

            // Hour labels
            hourLabelsView
        }
        .onAppear {
            if animate {
                if reduceMotion {
                    animationProgress = 1
                } else {
                    withAnimation(.spring(.smooth(duration: 0.8))) {
                        animationProgress = 1
                    }
                }
            }
        }
        .onChange(of: animate) { _, newValue in
            if newValue {
                if reduceMotion {
                    animationProgress = 1
                } else {
                    withAnimation(.spring(.smooth(duration: 0.8))) {
                        animationProgress = 1
                    }
                }
            }
        }
        .onChange(of: selectedHour) { _, newValue in
            // Cancel any existing dismiss task
            tooltipDismissTask?.cancel()

            // Start new dismiss timer if we have a selection
            if newValue != nil {
                tooltipDismissTask = Task {
                    await Task.sleepIgnoringCancellation(seconds: 3)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if reduceMotion {
                            selectedHour = nil
                        } else {
                            withAnimation(.spring(.smooth(duration: 0.3))) {
                                selectedHour = nil
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Accessibility

    private var chartAccessibilityLabel: String {
        let hoursWithData = chartData.filter { $0.amount > 0 }
        guard !hoursWithData.isEmpty else {
            return String(localized: "chart_accessibility_no_data")
        }

        let totalAmount = hoursWithData.reduce(0) { $0 + $1.amount }
        let formattedTotal = VolumeFormatters.string(fromMl: totalAmount, unitStyle: .short)

        if let peak = hoursWithData.max(by: { $0.amount < $1.amount }) {
            let peakFormatted = VolumeFormatters.string(fromMl: peak.amount, unitStyle: .short)
            return String(localized: "chart_accessibility_summary \(formattedTotal) \(hoursWithData.count) \(peak.hour) \(peakFormatted)")
        }

        return String(localized: "chart_accessibility_total \(formattedTotal)")
    }

    // MARK: - Tooltip View

    @ViewBuilder
    private var tooltipView: some View {
        if let dataPoint = selectedDataPoint, dataPoint.amount > 0 {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(Color.waterDrop)

                Text("\(dataPoint.hour)h")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)

                Text("•")
                    .foregroundStyle(Color.onTimeOfDayTertiaryText)

                Text(VolumeFormatters.string(fromMl: dataPoint.amount, unitStyle: .short))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)

                if dataPoint.isPeak {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .opacity
            ))
        } else {
            // Hint text when no selection
            Text(String(localized: "chart_tap_hint"))
                .font(.caption)
                .foregroundStyle(Color.onTimeOfDayTertiaryText)
                .opacity(animate ? 0.6 : 0)
                .animation(.spring(.smooth(duration: 0.5)).delay(1.0), value: animate)
        }
    }

    // MARK: - Chart View

    private var chartView: some View {
        Chart(chartData) { dataPoint in
            BarMark(
                x: .value("Hora", dataPoint.hour),
                y: .value("Volume", animate ? Double(dataPoint.amount) : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(barGradient(for: dataPoint))
            .opacity(barOpacity(for: dataPoint))

            // Current hour indicator
            if dataPoint.isCurrent {
                RuleMark(x: .value("Agora", currentHour))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Color.waterDrop.opacity(0.5))
                    .annotation(position: .top, spacing: 4) {
                        Circle()
                            .fill(Color.waterDrop)
                            .frame(width: 6, height: 6)
                            .shadow(color: Color.waterDrop.opacity(0.5), radius: 4)
                    }
            }
        }
        .chartXScale(domain: hourRange)
        .chartYScale(domain: 0...(Double(maxAmount) * 1.15))
        .chartXAxis {
            AxisMarks(values: displayHours) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.onTimeOfDayTertiaryText.opacity(0.3))
            }
        }
        .chartYAxis(.hidden)
        .chartXSelection(value: $selectedHour)
        .sensoryFeedback(.selection, trigger: selectedHour)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // Get raw value and round to nearest hour
                        if let rawHour: Double = proxy.value(atX: location.x) {
                            let hour = Int(rawHour.rounded())
                            // Clamp to valid range
                            let clampedHour = max(hourRange.lowerBound, min(hourRange.upperBound, hour))

                            if reduceMotion {
                                if selectedHour == clampedHour {
                                    selectedHour = nil
                                } else {
                                    selectedHour = clampedHour
                                }
                            } else {
                                withAnimation(.spring(.smooth(duration: 0.2))) {
                                    if selectedHour == clampedHour {
                                        selectedHour = nil
                                    } else {
                                        selectedHour = clampedHour
                                    }
                                }
                            }
                        }
                    }
            }
        }
        .chartBackground { proxy in
            // Glow effect layer
            GeometryReader { geo in
                if let selectedHour,
                   let dataPoint = chartData.first(where: { $0.hour == selectedHour }),
                   dataPoint.amount > 0 {
                    let startX = proxy.position(forX: selectedHour) ?? 0
                    let barHeight = CGFloat(dataPoint.amount) / CGFloat(maxAmount) * geo.size.height

                    // Vertical glow along the bar
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.waterDrop.opacity(0.4), Color.waterGradientEnd.opacity(0.2), Color.clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .blur(radius: 12)
                        .frame(width: 30, height: barHeight * 0.8)
                        .position(x: startX, y: geo.size.height - barHeight * 0.4)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.5)), value: animate)
        .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.2)), value: selectedHour)
    }

    // MARK: - Hour Labels

    private var hourLabelsView: some View {
        HStack {
            ForEach(displayHours, id: \.self) { hour in
                Text("\(hour)h")
                    .font(.system(size: 10, weight: hour == currentHour ? .semibold : .regular))
                    .foregroundStyle(hour == currentHour ? Color.waterDrop : Color.onTimeOfDaySecondaryText)

                if hour != displayHours.last {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private func barGradient(for dataPoint: HourlyDataPoint) -> LinearGradient {
        if dataPoint.amount == 0 {
            return LinearGradient(
                colors: [Color.onTimeOfDayTertiaryText.opacity(0.15), Color.onTimeOfDayTertiaryText.opacity(0.25)],
                startPoint: .bottom,
                endPoint: .top
            )
        }

        if dataPoint.isPeak {
            // Premium peak bar with liquid glass effect
            return LinearGradient(
                colors: [
                    Color.waterGradientEnd,
                    Color.waterGradientStart,
                    Color.waterDrop,
                    Color.waterGradientStart.opacity(0.9) // Slight highlight at top
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }

        // Normal bar with subtle highlight
        return LinearGradient(
            colors: [
                Color.waterGradientEnd.opacity(0.7),
                Color.waterGradientStart,
                Color.waterGradientEnd.opacity(0.85),
                Color.waterGradientStart.opacity(0.6) // Soft highlight at top
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func barOpacity(for dataPoint: HourlyDataPoint) -> Double {
        if let selected = selectedHour {
            return dataPoint.hour == selected ? 1.0 : 0.5
        }
        return dataPoint.amount > 0 ? 1.0 : 0.4
    }
}
