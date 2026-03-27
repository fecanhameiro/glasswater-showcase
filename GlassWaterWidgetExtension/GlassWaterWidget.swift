//
//  GlassWaterWidget.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import ActivityKit
import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct GlassWaterWidgetEntry: TimelineEntry {
    let date: Date
    let currentMl: Int
    let goalMl: Int
    let lastEntryDate: Date?
    let lastEntryAmountMl: Int?
    let customAmountMl: Int
    var needsOnboarding: Bool = false
}

struct GlassWaterWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GlassWaterWidgetEntry {
        GlassWaterWidgetEntry(
            date: .now,
            currentMl: 1200,
            goalMl: AppConstants.defaultDailyGoalMl,
            lastEntryDate: Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -2, to: .now),
            lastEntryAmountMl: 250,
            customAmountMl: AppConstants.defaultCustomAmountMl
        )
    }

    func snapshot(
        for configuration: GlassWaterWidgetConfigurationIntent,
        in context: Context
    ) async -> GlassWaterWidgetEntry {
        SyncLog.info("[Widget] snapshot() called — isPreview=\(context.isPreview)")
        return await loadEntry(configuration: configuration).entry
    }

    func timeline(
        for configuration: GlassWaterWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<GlassWaterWidgetEntry> {
        SyncLog.info("[Widget] timeline() called — family=\(context.family.description)")
        let result = await loadEntry(configuration: configuration)
        SyncLog.info("[Widget] timeline() result — totalMl=\(result.entry.currentMl), goalMl=\(result.entry.goalMl), refreshAt=\(result.refreshDate.formatted(date: .omitted, time: .shortened))")

        var entries = [result.entry]

        // Schedule a midnight entry that resets to 0ml for the new day.
        // Without this, the widget shows yesterday's data until the next
        // reminder-based refresh (which could be hours after midnight).
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        // Only add if midnight is before the next scheduled refresh
        if tomorrow < result.refreshDate {
            let midnightEntry = GlassWaterWidgetEntry(
                date: tomorrow,
                currentMl: 0,
                goalMl: result.entry.goalMl,
                lastEntryDate: nil,
                lastEntryAmountMl: nil,
                customAmountMl: result.entry.customAmountMl
            )
            entries.append(midnightEntry)
        }

        return Timeline(entries: entries, policy: .after(result.refreshDate))
    }

    @MainActor
    private func loadEntry(
        configuration: GlassWaterWidgetConfigurationIntent
    ) async -> (entry: GlassWaterWidgetEntry, refreshDate: Date) {
        SyncLog.info("[Widget] loadEntry() START")
        let appGroupDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)

        // Check if user has completed onboarding
        let hasCompletedOnboarding = appGroupDefaults?.bool(forKey: AppConstants.appGroupOnboardingCompletedKey) ?? false
        if !hasCompletedOnboarding {
            let onboardingEntry = GlassWaterWidgetEntry(
                date: .now,
                currentMl: 0,
                goalMl: AppConstants.defaultDailyGoalMl,
                lastEntryDate: nil,
                lastEntryAmountMl: nil,
                customAmountMl: AppConstants.defaultCustomAmountMl,
                needsOnboarding: true
            )
            let refreshDate = Calendar.autoupdatingCurrent.date(byAdding: .minute, value: 30, to: .now) ?? .now
            return (onboardingEntry, refreshDate)
        }

        let storedCustomAmount = appGroupDefaults?.object(forKey: AppConstants.appGroupCustomAmountKey) as? Int

        let fallback = GlassWaterWidgetEntry(
            date: .now,
            currentMl: 0,
            goalMl: AppConstants.defaultDailyGoalMl,
            lastEntryDate: nil,
            lastEntryAmountMl: nil,
            customAmountMl: QuickAddOptions.resolvedCustomAmount(forGoalMl: AppConstants.defaultDailyGoalMl, customAmountMl: storedCustomAmount)
        )
        do {
            let snapshotStore = AppGroupHydrationSnapshotStore()
            let snapshot = snapshotStore.load()
            if let snapshot,
               Calendar.autoupdatingCurrent.isDate(snapshot.dayStart, inSameDayAs: .now)
            {
                SyncLog.info("[Widget] loadEntry() → SNAPSHOT path — totalMl=\(snapshot.totalMl), goalMl=\(snapshot.goalMl), source=\(snapshot.source.rawValue), snapshotAge=\(String(format: "%.1f", Date.now.timeIntervalSince(snapshot.updatedAt)))s")
                let entry = GlassWaterWidgetEntry(
                    date: snapshot.updatedAt,
                    currentMl: snapshot.totalMl,
                    goalMl: snapshot.goalMl,
                    lastEntryDate: snapshot.lastIntakeDate,
                    lastEntryAmountMl: snapshot.lastIntakeMl,
                    customAmountMl: QuickAddOptions.clampCustomAmount(snapshot.customAmountMl)
                )
                let refreshDate = Calendar.autoupdatingCurrent.date(byAdding: .minute, value: 15, to: .now) ?? .now
                return (entry, refreshDate)
            } else if let snapshot {
                SyncLog.info("[Widget] loadEntry() — snapshot EXISTS but NOT today (dayStart=\(snapshot.dayStart.formatted()), now=\(Date.now.formatted()))")
            } else {
                SyncLog.info("[Widget] loadEntry() — no snapshot found, falling back to SwiftData")
            }
            let container = try ModelContainerFactory.makeContainer()
            let context = container.mainContext
            let store = SwiftDataWaterStore(modelContext: context)
            let settingsStore = SwiftDataSettingsStore(modelContext: context)
            let settings = try settingsStore.loadOrCreate()
            let goal = settings.dailyGoalMl
            let total = try store.total(for: .now)
            let latestEntry = try store.latestTodayEntry(for: .now)
            let refreshDate = nextRefreshDate(settings: settings, referenceDate: .now)
            SyncLog.info("[Widget] loadEntry() → SWIFTDATA path — totalMl=\(total), goalMl=\(goal)")
            let entry = GlassWaterWidgetEntry(
                date: .now,
                currentMl: total,
                goalMl: goal,
                lastEntryDate: latestEntry?.date,
                lastEntryAmountMl: latestEntry?.amountMl,
                customAmountMl: QuickAddOptions.resolvedCustomAmount(forGoalMl: goal, customAmountMl: storedCustomAmount)
            )
            return (entry, refreshDate)
        } catch {
            SyncLog.error("[Widget] loadEntry() FAILED — using fallback: \(error.localizedDescription)")
            return (fallback, Calendar.autoupdatingCurrent.date(byAdding: .minute, value: 30, to: .now) ?? .now)
        }
    }

    private func nextRefreshDate(settings: UserSettings, referenceDate: Date) -> Date {
        guard settings.notificationsEnabled else {
            return Calendar.autoupdatingCurrent.date(byAdding: .minute, value: 30, to: referenceDate) ?? referenceDate
        }
        return ReminderSchedule.nextRefreshDate(
            referenceDate: referenceDate,
            startMinutes: settings.reminderStartMinutes,
            endMinutes: settings.reminderEndMinutes,
            intervalMinutes: settings.reminderIntervalMinutes
        ) ?? Calendar.autoupdatingCurrent.date(byAdding: .minute, value: 30, to: referenceDate) ?? referenceDate
    }
}

// MARK: - Main Widget View (Router)

struct GlassWaterWidgetView: View {
    let entry: GlassWaterWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var progress: Double {
        guard entry.goalMl > 0 else { return 0 }
        return min(Double(entry.currentMl) / Double(entry.goalMl), 1)
    }

    private var currentFormatted: String {
        VolumeFormatters.string(fromMl: entry.currentMl, unitStyle: .short)
    }

    private var goalFormatted: String {
        VolumeFormatters.string(fromMl: entry.goalMl, unitStyle: .short)
    }

    private var quickAddAmountMl: Int {
        QuickAddOptions.amount(forPercent: 10, goalMl: entry.goalMl)
    }

    private var remainingFormatted: String {
        let remaining = max(entry.goalMl - entry.currentMl, 0)
        return VolumeFormatters.string(fromMl: remaining, unitStyle: .short)
    }

    private var lastIntakeText: String {
        guard let date = entry.lastEntryDate else {
            return String(localized: "widget_last_intake_empty")
        }
        let time = date.formatted(date: .omitted, time: .shortened)
        guard let amount = entry.lastEntryAmountMl else {
            return time
        }
        let amountFormatted = VolumeFormatters.string(fromMl: amount, unitStyle: .short)
        return Localized.string("widget_last_intake_value %@ %@", amountFormatted, time)
    }

    /// Compact version showing only time (for medium widget where space is limited)
    private var lastIntakeTimeOnly: String {
        guard let date = entry.lastEntryDate else {
            return String(localized: "widget_last_intake_empty")
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Group {
            if entry.needsOnboarding {
                WidgetOnboardingView(family: family)
            } else {
                mainContent
            }
        }
        .containerBackground(for: .widget) {
            ZStack(alignment: .bottom) {
                Color(.systemBackground)
                timeOfDayTint

                if !entry.needsOnboarding, family == .systemSmall || family == .systemMedium || family == .systemLarge {
                    WidgetWaterWaveShape(
                        fillLevel: min(progress, 1.0),
                        phase: wavePhase,
                        amplitude: waveAmplitude,
                        frequency: waveFrequency
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                waveColor.opacity(waveTopOpacity),
                                waveColor.opacity(waveBottomOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch family {
            case .accessoryCircular:
                WidgetAccessoryCircularView(progress: progress)
            case .accessoryRectangular:
                WidgetAccessoryRectangularView(
                    remainingFormatted: remainingFormatted,
                    lastIntakeText: lastIntakeText
                )
            case .systemLarge:
                WidgetLargeView(
                    progress: progress,
                    currentFormatted: currentFormatted,
                    goalFormatted: goalFormatted,
                    remainingFormatted: remainingFormatted,
                    lastIntakeText: lastIntakeText,
                    quickAddAmountMl: quickAddAmountMl,
                    customAmountMl: entry.customAmountMl
                )
            case .systemMedium:
                WidgetMediumView(
                    progress: progress,
                    currentFormatted: currentFormatted,
                    goalFormatted: goalFormatted,
                    remainingFormatted: remainingFormatted,
                    lastIntakeText: lastIntakeTimeOnly,
                    quickAddAmountMl: quickAddAmountMl,
                    customAmountMl: entry.customAmountMl
                )
            default:
                WidgetSmallView(
                    progress: progress,
                    currentFormatted: currentFormatted,
                    goalFormatted: goalFormatted,
                    remainingFormatted: remainingFormatted,
                    lastIntakeText: lastIntakeTimeOnly,
                    quickAddAmountMl: quickAddAmountMl,
                    customAmountMl: entry.customAmountMl
                )
            }
        }
    }

    // MARK: - Water Wave Parameters (per family)

    private var waveColor: Color {
        progress >= 1.0 ? .green : .cyan
    }

    private var wavePhase: Double {
        switch family {
        case .systemSmall: return 1.0
        case .systemMedium: return 0.8
        default: return 0.5
        }
    }

    private var waveAmplitude: CGFloat {
        switch family {
        case .systemSmall: return 2.5
        case .systemMedium: return 3
        default: return 4
        }
    }

    private var waveFrequency: Double {
        switch family {
        case .systemLarge: return 1.5
        default: return 2
        }
    }

    private var waveTopOpacity: Double {
        switch family {
        case .systemSmall: return 0.06
        case .systemMedium: return 0.07
        default: return 0.08
        }
    }

    private var waveBottomOpacity: Double {
        switch family {
        case .systemSmall: return 0.02
        case .systemMedium: return 0.03
        default: return 0.03
        }
    }

    /// Subtle background tint that shifts with time of day
    private var timeOfDayTint: Color {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: entry.date)
        switch hour {
        case 6..<12:  return Color.cyan.opacity(0.04)     // Morning — fresh cyan
        case 12..<17: return Color.blue.opacity(0.03)     // Afternoon — calm blue
        case 17..<21: return Color.indigo.opacity(0.04)   // Evening — warm indigo
        default:      return Color.blue.opacity(0.05)     // Night — deep blue
        }
    }
}

// MARK: - Widget Declarations

struct GlassWaterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppConstants.widgetKind,
            intent: GlassWaterWidgetConfigurationIntent.self,
            provider: GlassWaterWidgetProvider()
        ) { entry in
            GlassWaterWidgetView(entry: entry)
        }
        .configurationDisplayName("widget_title")
        .description("widget_description")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

@available(iOS 16.2, *)
struct GlassWaterLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlassWaterLiveActivityAttributes.self) { context in
            GlassWaterLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland(expanded: {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("live_activity_title")
                            .font(.caption.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(liveActivityPercentage(for: effectiveProgress(for: context)))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(effectiveGoalReached(for: context) ? .green : .cyan)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        LiveActivityProgressCapsule(
                            progress: effectiveProgress(for: context),
                            height: 4,
                            accentColor: effectiveGoalReached(for: context) ? .green : .cyan
                        )

                        if effectiveGoalReached(for: context) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text("live_activity_goal_celebration")
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            GlassWaterLiveActivityQuickAddRow(
                                options: liveActivityQuickAddOptions(context),
                                style: .compact
                            )
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }, compactLeading: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }, compactTrailing: {
                if effectiveGoalReached(for: context) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(liveActivityPercentage(for: effectiveProgress(for: context)))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }, minimal: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            })
        }
    }

    private func effectiveProgress(
        for context: ActivityViewContext<GlassWaterLiveActivityAttributes>
    ) -> Double {
        context.isStale ? 0 : context.state.progress
    }

    private func effectiveGoalReached(
        for context: ActivityViewContext<GlassWaterLiveActivityAttributes>
    ) -> Bool {
        context.isStale ? false : context.state.goalReached
    }

    private func liveActivityPercentage(for progress: Double) -> String {
        "\(Int(progress * 100))%"
    }

    private func liveActivityQuickAddOptions(
        _ context: ActivityViewContext<GlassWaterLiveActivityAttributes>
    ) -> [QuickAddAmountOption] {
        QuickAddOptions.liveActivityOptions(
            forGoalMl: context.attributes.dailyGoalMl,
            customAmountMl: context.state.customAmountMl
        )
    }

    private func liveActivityMissingText(
        _ context: ActivityViewContext<GlassWaterLiveActivityAttributes>
    ) -> String {
        let remaining = VolumeFormatters.string(fromMl: context.state.remainingMl, unitStyle: .short)
        return Localized.string("live_activity_missing_value %@", remaining)
    }
}
