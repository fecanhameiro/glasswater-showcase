//
//  HomeEntriesSheetView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI


// MARK: - Daily Insight

private enum DailyInsight {
    case peakHour(hour: Int)
    case mostActivePeriod(period: DayPeriod)
    case wellDistributed
    case none

    var text: String? {
        switch self {
        case .peakHour(let hour):
            return String(localized: "insight_peak_hour \(hour)")
        case .mostActivePeriod(let period):
            switch period {
            case .morning:
                return String(localized: "insight_most_active_morning")
            case .afternoon:
                return String(localized: "insight_most_active_afternoon")
            case .night:
                return String(localized: "insight_most_active_night")
            }
        case .wellDistributed:
            return String(localized: "insight_well_distributed")
        case .none:
            return nil
        }
    }

    var emoji: String {
        switch self {
        case .peakHour: return "💧"
        case .mostActivePeriod(let period): return period.emoji
        case .wellDistributed: return "⚖️"
        case .none: return ""
        }
    }
}

// MARK: - Grouped Entry

private struct GroupedEntries: Identifiable {
    let period: DayPeriod
    let entries: [WaterEntry]
    var id: String { period.id }

    var totalMl: Int {
        entries.reduce(0) { $0 + $1.amountMl }
    }
}

// MARK: - Main View

struct HomeEntriesSheetView: View {
    let entries: [WaterEntry]
    let dailyGoalMl: Int
    let onDelete: (WaterEntry) -> Void
    let onUpdate: (WaterEntry, Int, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedEntry: WaterEntry?
    @State private var hasAppeared = false
    @State private var selectionHapticTrigger = false
    @State private var deleteHapticTrigger = false

    private var toolbarScheme: ColorScheme {
        if colorScheme == .dark {
            return .dark
        }
        return TimeOfDayPeriod.current.hasLightBackground ? .light : .dark
    }

    private var totalMl: Int {
        entries.reduce(0) { $0 + $1.amountMl }
    }

    private var progress: Double {
        guard dailyGoalMl > 0 else { return 0 }
        return min(Double(totalMl) / Double(dailyGoalMl), 1.0)
    }

    private var groupedEntries: [GroupedEntries] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry -> DayPeriod in
            let hour = calendar.component(.hour, from: entry.date)
            return DayPeriod.from(hour: hour)
        }

        return DayPeriod.allCases.compactMap { period in
            guard let periodEntries = grouped[period], !periodEntries.isEmpty else { return nil }
            let sorted = periodEntries.sorted { $0.date > $1.date }
            return GroupedEntries(period: period, entries: sorted)
        }
    }

    private var entriesByHour: [Int: Int] {
        let calendar = Calendar.current
        var result: [Int: Int] = [:]
        for entry in entries {
            let hour = calendar.component(.hour, from: entry.date)
            result[hour, default: 0] += entry.amountMl
        }
        return result
    }

    private var flatEntryIndex: [UUID: Int] {
        var index: [UUID: Int] = [:]
        var i = 0
        for group in groupedEntries {
            for entry in group.entries {
                index[entry.id] = i
                i += 1
            }
        }
        return index
    }

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    EmptyEntriesView()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        EntriesSummaryHeaderView(
                            totalMl: totalMl,
                            dailyGoalMl: dailyGoalMl,
                            progress: progress,
                            entryCount: entries.count,
                            entriesByHour: entriesByHour,
                            animate: hasAppeared
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    ForEach(groupedEntries) { group in
                        Section {
                            ForEach(group.entries, id: \.id) { entry in
                                let entryIndex = flatEntryIndex[entry.id] ?? 0

                                EntryRowView(entry: entry) {
                                    selectionHapticTrigger.toggle()
                                    selectedEntry = entry
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .opacity(hasAppeared ? 1 : 0)
                                .offset(y: hasAppeared && !reduceMotion ? 0 : (hasAppeared ? 0 : 20))
                                .animation(
                                    reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(Double(entryIndex) * 0.05),
                                    value: hasAppeared
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteHapticTrigger.toggle()
                                        onDelete(entry)
                                    } label: {
                                        Label("entries_edit_delete", systemImage: "trash.fill")
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(entryAccessibilityLabel(for: entry))
                                .accessibilityHint(String(localized: "home_entry_edit_title"))
                            }
                        } header: {
                            PeriodSectionHeader(
                                period: group.period,
                                totalMl: group.totalMl
                            )
                            .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                TimeOfDayBackgroundView()
            }
            .navigationTitle("home_entries_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(toolbarScheme, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        selectionHapticTrigger.toggle()
                        dismiss()
                    } label: {
                        Text("common_done")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.onTimeOfDayText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.tint(Color.cyan.opacity(0.15)).interactive(), in: .capsule)
                }
            }
            .sheet(item: $selectedEntry) { entry in
                EntryEditSheetView(
                    entry: entry,
                    onSave: { amount, date in
                        onUpdate(entry, amount, date)
                    },
                    onDelete: {
                        deleteHapticTrigger.toggle()
                        onDelete(entry)
                    }
                )
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .sensoryFeedback(.selection, trigger: selectionHapticTrigger)
            .sensoryFeedback(.impact(weight: .medium), trigger: deleteHapticTrigger)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(0.1))
                    hasAppeared = true
                }
            }
        }
    }

    private func entryAccessibilityLabel(for entry: WaterEntry) -> String {
        let amount = VolumeFormatters.string(fromMl: entry.amountMl, unitStyle: .short)
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        let healthSync = entry.isFromHealth ? ", \(String(localized: "entries_synced_health"))" : ""
        return "\(amount), \(time)\(healthSync)"
    }
}

// MARK: - Summary Header

private struct EntriesSummaryHeaderView: View {
    let totalMl: Int
    let dailyGoalMl: Int
    let progress: Double
    let entryCount: Int
    let entriesByHour: [Int: Int]
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var formattedTotal: String {
        VolumeFormatters.string(fromMl: totalMl, unitStyle: .short)
    }

    private var formattedGoal: String {
        VolumeFormatters.string(fromMl: dailyGoalMl, unitStyle: .short)
    }

    private var percentText: String {
        "\(Int(progress * 100))%"
    }

    private var dailyInsight: DailyInsight {
        // Mínimo de horas com dados para mostrar insight
        let activeHours = entriesByHour.filter { $0.value > 0 }.count
        guard activeHours >= 3 else { return .none }

        // Calcular totais por período
        let morningTotal = (5..<12).reduce(0) { $0 + (entriesByHour[$1] ?? 0) }
        let afternoonTotal = (12..<18).reduce(0) { $0 + (entriesByHour[$1] ?? 0) }
        let nightTotal = (18..<24).reduce(0) { $0 + (entriesByHour[$1] ?? 0) }
        let total = morningTotal + afternoonTotal + nightTotal

        guard total > 0 else { return .none }

        // Encontrar período dominante
        let periods: [(DayPeriod, Int)] = [
            (.morning, morningTotal),
            (.afternoon, afternoonTotal),
            (.night, nightTotal)
        ]
        let activePeriods = periods.filter { $0.1 > 0 }.count

        if let dominant = periods.max(by: { $0.1 < $1.1 }) {
            let ratio = Double(dominant.1) / Double(total)

            if activePeriods >= 2 && ratio < 0.5 {
                return .wellDistributed
            } else if ratio >= 0.5 {
                return .mostActivePeriod(period: dominant.0)
            }
        }

        // Fallback: mostrar pico horário
        if let peak = entriesByHour.max(by: { $0.value < $1.value }), peak.value > 0 {
            return .peakHour(hour: peak.key)
        }

        return .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title row
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color.waterDrop)
                    .shadow(color: Color.waterDrop.opacity(0.5), radius: 4)
                Text("entries_header_today")
                    .font(.headline)
                    .foregroundStyle(Color.onTimeOfDayText)

                Spacer()

                Text("entries_count \(entryCount)")
                    .font(.subheadline)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
            }

            // Premium hourly chart
            HourlyChartView(entriesByHour: entriesByHour, animate: animate)
                .frame(height: 120)

            // Insight (if available)
            if let insightText = dailyInsight.text {
                HStack(spacing: 6) {
                    Text(insightText)
                    Text(dailyInsight.emoji)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.onTimeOfDaySecondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.onTimeOfDayCardBackground, in: Capsule())
                .overlay { Capsule().stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5) }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track with inner shadow effect
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            }
                            .frame(height: 10)

                        // Progress fill with glow
                        Capsule()
                            .fill(LinearGradient.waterGradient)
                            .overlay {
                                // Inner highlight
                                Capsule()
                                    .fill(LinearGradient.glassHighlight(opacity: 0.6))
                                    .padding(2)
                            }
                            .frame(width: animate ? geo.size.width * progress : 0, height: 10)
                            .shadow(color: Color.waterDrop.opacity(0.4), radius: 4, y: 2)
                            .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.8)).delay(0.2), value: animate)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text(Localized.string("entries_header_progress %@ %@", formattedTotal, formattedGoal))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDayText)

                    Spacer()

                    Text(Localized.string("entries_header_percent %@", percentText))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }
            }
        }
        .padding(16)
        .background(Color.onTimeOfDayCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .opacity(animate ? 1 : 0)
        .scaleEffect(animate ? 1 : 0.98)
        .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)), value: animate)
    }
}

// MARK: - Period Section Header

private struct PeriodSectionHeader: View {
    let period: DayPeriod
    let totalMl: Int

    private var formattedTotal: String {
        VolumeFormatters.string(fromMl: totalMl, unitStyle: .short)
    }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(period.emoji)
                Text(period.localizedName)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.onTimeOfDayText)

            Spacer()

            Text(formattedTotal)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.onTimeOfDaySecondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.onTimeOfDayCardBackground, in: Capsule())
                .overlay { Capsule().stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5) }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - Entry Row

private struct EntryRowView: View {
    let entry: WaterEntry
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false

    private var formattedAmount: String {
        VolumeFormatters.string(fromMl: entry.amountMl, unitStyle: .short)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Glowing drop icon
            ZStack {
                Circle()
                    .fill(Color.waterDrop.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: "drop.fill")
                    .font(.body)
                    .foregroundStyle(Color.waterDrop)
                    .shadow(color: Color.waterDrop.opacity(0.4), radius: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedAmount)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)

                if entry.isFromHealth {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text("entries_synced_health")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.onTimeOfDayTertiaryText)
                }
            }

            Spacer()

            Text(entry.date, style: .time)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.onTimeOfDaySecondaryText)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.onTimeOfDayTertiaryText)
        }
        .padding(12)
        .background(Color.onTimeOfDayCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1.0)
        .brightness(isPressed ? (colorScheme == .dark ? 0.05 : -0.02) : 0)
        .animation(reduceMotion ? .none : .spring(.snappy), value: isPressed)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            isPressed = pressing
        }, perform: {
            // Long press opens edit too
            onTap()
        })
    }
}

// MARK: - Empty State

private struct EmptyEntriesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 40)

            ZStack {
                // Glow rings (static when reduceMotion)
                Circle()
                    .fill(Color.waterDrop.opacity(0.08))
                    .frame(width: 120, height: 120)
                    .scaleEffect(reduceMotion ? 1.0 : (isPulsing ? 1.2 : 0.9))

                Circle()
                    .fill(Color.waterDrop.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .scaleEffect(reduceMotion ? 1.0 : (isPulsing ? 1.1 : 0.95))

                // Main drop with glow
                Image(systemName: "drop.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(LinearGradient.waterVerticalGradient)
                    .shadow(color: Color.waterDrop.opacity(0.5), radius: 12)
                    .scaleEffect(reduceMotion ? 1.0 : (isPulsing ? 1.05 : 0.95))
            }
            .opacity(reduceMotion ? 1.0 : (isPulsing ? 1.0 : 0.7))
            .animation(
                reduceMotion ? .none : .spring(.smooth(duration: 1.0)).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                if !reduceMotion {
                    isPulsing = true
                }
            }

            VStack(spacing: 8) {
                Text("entries_empty_title")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)

                Text("entries_empty_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.onTimeOfDayCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}
