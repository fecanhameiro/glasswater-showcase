//
//  HistoryView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Charts
import SwiftUI


struct HistoryView: View {
    @State private var viewModel: HistoryViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // Animation states
    @State private var hasAppeared = false
    @State private var showChart = false
    @State private var showInsights = false
    @State private var showList = false

    // Sheet state
    @State private var selectedDaySummary: DailyIntakeSummary?
    @State private var unitVersion = 0
    private let analytics: any AnalyticsTracking

    private var toolbarScheme: ColorScheme {
        if colorScheme == .dark {
            return .dark
        }
        return TimeOfDayPeriod.current.hasLightBackground ? .light : .dark
    }

    init(services: AppServices) {
        _viewModel = State(initialValue: HistoryViewModel(services: services))
        analytics = services.analytics
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Weekly Chart Section
                WeeklyChartSection(
                    weeklyPoints: viewModel.weeklyPoints,
                    dailyGoalMl: viewModel.dailyGoalMl,
                    selectedDate: $viewModel.selectedDate,
                    animate: showChart
                )
                .opacity(showChart ? 1 : 0)
                .scaleEffect(showChart ? 1 : 0.98)

                // Weekly Insights Card
                WeeklyInsightsCard(
                    weeklyTotalMl: viewModel.weeklyTotalMl,
                    weeklyAverageMl: viewModel.weeklyAverageMl,
                    bestDay: viewModel.bestDay,
                    currentStreak: viewModel.currentStreak,
                    weeklyProgress: viewModel.weeklyProgress,
                    weeklyGoalMl: viewModel.weeklyGoalMl,
                    daysMetGoal: viewModel.daysMetGoal,
                    weeklyInsight: viewModel.weeklyInsight,
                    animate: showInsights
                )
                .opacity(showInsights ? 1 : 0)
                .scaleEffect(showInsights ? 1 : 0.98)

                // Daily History Section
                DailyHistorySection(
                    dailySummaries: viewModel.dailySummaries,
                    currentStreak: viewModel.currentStreak,
                    animate: showList,
                    onSelectDay: { summary in
                        selectedDaySummary = summary
                    }
                )
                .opacity(showList ? 1 : 0)
            }
            .padding(20)
            .id(unitVersion)
        }
        .background {
            TimeOfDayBackgroundView()
        }
        .navigationTitle("history_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(toolbarScheme, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .onAppear {
            analytics.logScreenView(screenName: "history")
            Task { await viewModel.load() }
            startCascadeAnimation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .volumeUnitDidChange)) { _ in
            unitVersion += 1
        }
        .onChange(of: selectedDaySummary != nil) { _, isShowing in
            if isShowing, let summary = selectedDaySummary {
                analytics.logScreenView(screenName: "day_entries_sheet")
                let calendar = Calendar.autoupdatingCurrent
                let daysAgo = calendar.dateComponents([.day], from: summary.date, to: calendar.startOfDay(for: .now)).day ?? 0
                analytics.logEvent(AnalyticsEvents.historyDayViewed, parameters: [
                    AnalyticsParams.daysAgo: daysAgo
                ])
            }
        }
        .sheet(item: $selectedDaySummary) { summary in
            DayEntriesSheetView(
                summary: summary,
                onDelete: { entry in
                    Task {
                        await viewModel.deleteEntry(entry)
                        if let date = selectedDaySummary?.date,
                           let updated = viewModel.dailySummaries.first(where: {
                               Calendar.current.isDate($0.date, inSameDayAs: date)
                           }),
                           !updated.entries.isEmpty {
                            selectedDaySummary = updated
                        } else {
                            selectedDaySummary = nil
                        }
                    }
                },
                onUpdate: { entry, amount, date in
                    Task {
                        await viewModel.updateEntry(entry, amountMl: amount, date: date)
                        if let originalDate = selectedDaySummary?.date,
                           let updated = viewModel.dailySummaries.first(where: {
                               Calendar.current.isDate($0.date, inSameDayAs: originalDate)
                           }),
                           !updated.entries.isEmpty {
                            selectedDaySummary = updated
                        } else {
                            selectedDaySummary = nil
                        }
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }

    private func startCascadeAnimation() {
        guard !hasAppeared else { return }
        hasAppeared = true

        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.5)).delay(0.1)) {
            showChart = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.2)) {
            showInsights = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.3)) {
            showList = true
        }
    }
}

// MARK: - Weekly Chart Section

private struct WeeklyChartSection: View {
    let weeklyPoints: [WeeklyIntakePoint]
    let dailyGoalMl: Int
    @Binding var selectedDate: Date?
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tooltipDismissTask: Task<Void, Never>?
    private var selectedPoint: WeeklyIntakePoint? {
        guard let date = selectedDate else { return nil }
        return weeklyPoints.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private var maxAmount: Int {
        max(weeklyPoints.map(\.amountMl).max() ?? 1, dailyGoalMl)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color.waterDrop)
                Text("history_weekly_title")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)

                Spacer()
            }

            // Chart
            Chart(weeklyPoints) { point in
                let isGoalMet = point.amountMl >= dailyGoalMl
                let isSelected = selectedDate.map { Calendar.current.isDate(point.date, inSameDayAs: $0) } ?? false

                BarMark(
                    x: .value("Dia", point.date, unit: .day),
                    y: .value("Volume", animate ? point.amountMl : 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(barGradient(isGoalMet: isGoalMet, isSelected: isSelected))
                .opacity(selectedDate == nil || isSelected ? 1.0 : 0.4)

                // Goal line
                RuleMark(y: .value("Meta", dailyGoalMl))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.waterDrop.opacity(0.3))
            }
            .frame(height: 160)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.weekday(.narrow))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.onTimeOfDaySecondaryText)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...Double(maxAmount) * 1.15)
            .chartXSelection(value: $selectedDate)
            .sensoryFeedback(.selection, trigger: selectedDate)
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let selectedDate,
                       let point = selectedPoint,
                       point.amountMl > 0 {
                        let startX = proxy.position(forX: selectedDate) ?? 0
                        let barHeight = CGFloat(point.amountMl) / CGFloat(maxAmount) * geo.size.height

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
            .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.6)), value: animate)
            .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.2)), value: selectedDate)
        }
        .padding(16)
        .background(Color.onTimeOfDayCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .overlay(alignment: .topTrailing) {
            if let point = selectedPoint {
                tooltipView(for: point)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .onChange(of: selectedDate) { _, newValue in
            tooltipDismissTask?.cancel()

            if newValue != nil {
                tooltipDismissTask = Task {
                    await Task.sleepIgnoringCancellation(seconds: 3)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.spring(.smooth(duration: 0.3))) {
                            selectedDate = nil
                        }
                    }
                }
            }
        }
    }

    private func tooltipView(for point: WeeklyIntakePoint) -> some View {
        let isGoalMet = point.amountMl >= dailyGoalMl
        let percent = dailyGoalMl > 0 ? Int(Double(point.amountMl) / Double(dailyGoalMl) * 100) : 0

        return HStack(spacing: 6) {
            Text(point.date, format: .dateTime.weekday(.abbreviated))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.onTimeOfDayText)

            Text("•")
                .foregroundStyle(Color.onTimeOfDayTertiaryText)

            Text(VolumeFormatters.string(fromMl: point.amountMl, unitStyle: .short))
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.onTimeOfDayText)

            Text("(\(percent)%)")
                .font(.caption2)
                .foregroundStyle(Color.onTimeOfDaySecondaryText)

            if isGoalMet {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color.onTimeOfDayCardBackground)
                .overlay {
                    Capsule().stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
                }
        }
    }

    private func barGradient(isGoalMet: Bool, isSelected: Bool) -> LinearGradient {
        if isGoalMet {
            return LinearGradient(
                colors: [Color.green.opacity(0.7), Color.green],
                startPoint: .bottom,
                endPoint: .top
            )
        } else {
            return LinearGradient(
                colors: [Color.waterGradientEnd.opacity(0.7), Color.waterGradientStart],
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }
}

// MARK: - Weekly Insights Card

private struct WeeklyInsightsCard: View {
    let weeklyTotalMl: Int
    let weeklyAverageMl: Int
    let bestDay: DailyIntakeSummary?
    let currentStreak: Int
    let weeklyProgress: Double
    let weeklyGoalMl: Int
    let daysMetGoal: Int
    let weeklyInsight: WeeklyInsight
    let animate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Stats Grid
            HStack(spacing: 0) {
                // Total
                statItem(
                    icon: "drop.fill",
                    iconColor: Color.waterDrop,
                    value: VolumeFormatters.string(fromMl: weeklyTotalMl, unitStyle: .short),
                    label: String(localized: "history_weekly_total")
                )

                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, 8)

                // Average
                statItem(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: Color.cyan,
                    value: VolumeFormatters.string(fromMl: weeklyAverageMl, unitStyle: .short),
                    label: String(localized: "history_daily_average")
                )
            }

            // Best day and streak row
            HStack(spacing: 12) {
                // Best day
                if let best = bestDay, best.amountMl > 0 {
                    HStack(spacing: 6) {
                        Text("🏆")
                            .font(.caption)
                        Text("history_best_day")
                            .font(.caption.weight(.medium))
                        Text(best.date, format: .dateTime.weekday(.abbreviated))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.waterDrop)
                    }
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }

                Spacer()

                // Streak
                if currentStreak > 0 {
                    HStack(spacing: 4) {
                        Text("🔥")
                            .font(.caption)
                        Text("history_streak_days \(currentStreak)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                    }
                }
            }

            // Weekly progress bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.onTimeOfDaySecondaryText.opacity(0.15))
                            .overlay {
                                Capsule()
                                    .stroke(Color.onTimeOfDayTertiaryText.opacity(0.1), lineWidth: 1)
                            }

                        Capsule()
                            .fill(LinearGradient.waterGradient)
                            .overlay {
                                Capsule()
                                    .fill(LinearGradient.glassHighlight(opacity: 0.6))
                                    .padding(2)
                            }
                            .frame(width: animate ? geo.size.width * weeklyProgress : 0)
                            .shadow(color: Color.waterDrop.opacity(0.4), radius: 4, y: 2)
                            .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.8)).delay(0.2), value: animate)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("history_weekly_goal \(VolumeFormatters.string(fromMl: weeklyGoalMl, unitStyle: .short))")
                        .font(.caption)
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)

                    Spacer()

                    Text("\(Int(weeklyProgress * 100))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.onTimeOfDayText)
                }
            }

            // Insight
            if let insightText = weeklyInsight.text {
                HStack(spacing: 6) {
                    Text(weeklyInsight.emoji)
                    Text(insightText)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.onTimeOfDaySecondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.onTimeOfDayCardBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
                        }
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
        .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)), value: animate)
    }

    private func statItem(icon: String, iconColor: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .shadow(color: iconColor.opacity(0.4), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.onTimeOfDayText)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Daily History Section

private struct DailyHistorySection: View {
    let dailySummaries: [DailyIntakeSummary]
    let currentStreak: Int
    let animate: Bool
    let onSelectDay: (DailyIntakeSummary) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.waterDrop)
                Text("history_daily_title")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)

                Spacer()

                Text("history_last_14_days")
                    .font(.caption)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
            }

            // Daily rows
            ForEach(Array(dailySummaries.enumerated()), id: \.element.id) { index, summary in
                let isStreakDay = index < currentStreak && summary.isGoalMet

                HistoryRowView(
                    summary: summary,
                    streakDay: isStreakDay && !summary.isToday,
                    onTap: {
                        onSelectDay(summary)
                    }
                )
                .opacity(animate ? 1 : 0)
                .offset(y: animate && !reduceMotion ? 0 : 20)
                .animation(
                    reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(Double(index) * 0.04),
                    value: animate
                )
                .sensoryFeedback(.impact(weight: .light), trigger: summary.id)
            }
        }
    }
}

// MARK: - Day Entries Sheet

private struct DayEntriesSheetView: View {
    let summary: DailyIntakeSummary
    let onDelete: (WaterEntry) -> Void
    let onUpdate: (WaterEntry, Int, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedEntry: WaterEntry?
    @State private var hasAppeared = false

    private var entriesByHour: [Int: Int] {
        var result: [Int: Int] = [:]
        for entry in summary.entries {
            let hour = Calendar.current.component(.hour, from: entry.date)
            result[hour, default: 0] += entry.amountMl
        }
        return result
    }

    private var groupedEntries: [(period: DayPeriod, entries: [WaterEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: summary.entries) { entry -> DayPeriod in
            let hour = calendar.component(.hour, from: entry.date)
            return DayPeriod.from(hour: hour)
        }

        return DayPeriod.allCases.compactMap { period in
            guard let entries = grouped[period], !entries.isEmpty else { return nil }
            let sorted = entries.sorted { $0.date > $1.date }
            return (period: period, entries: sorted)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if summary.entries.isEmpty {
                    emptyStateView
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    // Summary header
                    Section {
                        daySummaryHeader
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    // Grouped entries
                    ForEach(groupedEntries, id: \.period) { group in
                        Section {
                            ForEach(group.entries, id: \.id) { entry in
                                entryRow(entry: entry)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onDelete(entry)
                                        } label: {
                                            Label("common_delete", systemImage: "trash.fill")
                                        }
                                    }
                            }
                        } header: {
                            periodHeader(period: group.period, entries: group.entries)
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
            .navigationTitle(summary.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("common_done")
                            .font(.subheadline.weight(.medium))
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
                        onDelete(entry)
                    }
                )
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(0.1))
                    hasAppeared = true
                }
            }
        }
    }

    private var daySummaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress summary
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color.waterDrop)
                    .shadow(color: Color.waterDrop.opacity(0.5), radius: 4)

                Text(VolumeFormatters.string(fromMl: summary.amountMl, unitStyle: .short))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.onTimeOfDayText)

                Text("/")
                    .foregroundStyle(Color.onTimeOfDayTertiaryText)

                Text(VolumeFormatters.string(fromMl: summary.goalMl, unitStyle: .short))
                    .font(.subheadline)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)

                Spacer()

                if summary.isGoalMet {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                        Text("history_goal_met")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(Color.green.opacity(0.15))
                    }
                } else {
                    Text("\(Int(summary.progress * 100))%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))

                    Capsule()
                        .fill(summary.isGoalMet ? LinearGradient(colors: [.green.opacity(0.8), .green], startPoint: .leading, endPoint: .trailing) : LinearGradient.waterGradient)
                        .frame(width: hasAppeared ? geo.size.width * min(summary.progress, 1.0) : 0)
                        .shadow(color: Color.waterDrop.opacity(0.3), radius: 4, y: 2)
                        .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.6)), value: hasAppeared)
                }
            }
            .frame(height: 8)

            // Entry count
            Text("history_entries_count \(summary.entryCount)")
                .font(.caption)
                .foregroundStyle(Color.onTimeOfDaySecondaryText)
        }
        .padding(16)
        .background(Color.onTimeOfDayCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.98)
        .animation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)), value: hasAppeared)
    }

    private func periodHeader(period: DayPeriod, entries: [WaterEntry]) -> some View {
        let total = entries.reduce(0) { $0 + $1.amountMl }

        return HStack {
            HStack(spacing: 6) {
                Text(period.emoji)
                Text(period.localizedName)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.onTimeOfDayText)

            Spacer()

            Text(VolumeFormatters.string(fromMl: total, unitStyle: .short))
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.onTimeOfDaySecondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(Color.onTimeOfDayCardBackground)
                        .overlay {
                            Capsule().stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
                        }
                }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func entryRow(entry: WaterEntry) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            HStack(spacing: 12) {
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
                    Text(VolumeFormatters.string(fromMl: entry.amountMl, unitStyle: .short))
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
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.onTimeOfDayCardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 60)

            ZStack {
                Circle()
                    .fill(Color.waterDrop.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "drop.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient.waterGradient)
                    .shadow(color: Color.waterDrop.opacity(0.4), radius: 8)
            }

            VStack(spacing: 8) {
                Text("history_day_no_entries_title")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)

                Text("history_day_no_entries_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}
