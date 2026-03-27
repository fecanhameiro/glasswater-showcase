//
//  SettingsView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import StoreKit
import SwiftUI
import UIKit

struct SettingsView: View {
    // MARK: - State
    @State private var viewModel: SettingsViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var showSmartNotificationsInfo = false
    @State private var notificationsUpdateTask: Task<Void, Never>?
    @State private var liveActivityUpdateTask: Task<Void, Never>?

    // Cascade animation states
    @State private var showGoalCard = false
    @State private var showNotificationsCard = false
    @State private var showLiveActivityCard = false
    @State private var showUnitsCard = false
    @State private var showHapticsCard = false
    @State private var showDuckCard = false
    @State private var showHealthCard = false
    @State private var showTipJarCard = false
    @State private var showAboutCard = false
    @State private var showFooter = false

    @State private var tipJarViewModel: TipJarViewModel

    private let analytics: any AnalyticsTracking

    private var controlColorScheme: ColorScheme {
        if colorScheme == .dark {
            return .dark
        }
        return TimeOfDayPeriod.current.hasLightBackground ? .light : .dark
    }

    private var toolbarScheme: ColorScheme {
        if colorScheme == .dark {
            return .dark
        }
        return TimeOfDayPeriod.current.hasLightBackground ? .light : .dark
    }
    // MARK: - Init
    init(services: AppServices) {
        _viewModel = State(initialValue: SettingsViewModel(services: services))
        _tipJarViewModel = State(initialValue: TipJarViewModel(services: services))
        analytics = services.analytics
    }

    // MARK: - Computed Properties
    private var goalFormatted: String {
        VolumeFormatters.string(fromMl: viewModel.dailyGoalMl, unitStyle: .medium)
    }

    private var reminderIntervalFormatted: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: TimeInterval(viewModel.reminderIntervalMinutes * 60)) ?? "\(viewModel.reminderIntervalMinutes)m"
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dailyGoalCard
                unitsCard
                notificationsCard
                liveActivityCard
                hapticsCard
                swimmingDuckCard
                healthCard
                tipJarCard
                aboutCard

                SettingsFooterView(showFooter: showFooter)
            }
            .padding(20)
        }
        .background {
            TimeOfDayBackgroundView()
        }
        .navigationTitle("settings_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(toolbarScheme, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .onAppear {
            analytics.logScreenView(screenName: "settings")
            Task { await viewModel.load() }
            if !tipJarViewModel.showThankYou {
                tipJarViewModel.loadTipStatus()
            }
            Task { await tipJarViewModel.loadProducts() }
            animateEntrance()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.load() }
        }
        .onChange(of: viewModel.dailyGoalMl) { _, _ in
            scheduleNotificationsUpdate()
            scheduleLiveActivityUpdate()
        }
        .onChange(of: viewModel.notificationsEnabled) { _, _ in
            scheduleNotificationsUpdate()
            scheduleLiveActivityUpdate()
        }
        .onChange(of: viewModel.reminderStartMinutes) { _, _ in
            scheduleNotificationsUpdate()
            scheduleLiveActivityUpdate()
        }
        .onChange(of: viewModel.reminderEndMinutes) { _, _ in
            scheduleNotificationsUpdate()
            scheduleLiveActivityUpdate()
        }
        .onChange(of: viewModel.reminderIntervalMinutes) { _, _ in
            scheduleNotificationsUpdate()
        }
        .onChange(of: viewModel.intelligentNotificationsEnabled) { _, _ in
            scheduleNotificationsUpdate()
        }
        .onChange(of: viewModel.hapticsEnabled) { _, newValue in
            viewModel.trackSettingToggle("haptics", enabled: newValue)
            viewModel.persistChanges()
        }
        .onChange(of: viewModel.swimmingDuckEnabled) { _, newValue in
            viewModel.trackSettingToggle("swimming_duck", enabled: newValue)
            viewModel.persistChanges()
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
        .onChange(of: viewModel.preferredVolumeUnit) { _, newValue in
            viewModel.trackSettingToggle("volume_unit_\(newValue.rawValue)", enabled: true)
            viewModel.persistChanges()
            Task { await viewModel.broadcastForUnitChange() }
            NotificationCenter.default.post(name: .volumeUnitDidChange, object: nil)
        }
        .onChange(of: viewModel.liveActivitiesEnabled) { _, _ in
            scheduleLiveActivityUpdate()
        }
        .onChange(of: viewModel.liveActivitySensitiveModeEnabled) { _, _ in
            scheduleLiveActivityUpdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidChange)) { _ in
            viewModel.reloadDuckState()
        }
        .onDisappear {
            notificationsUpdateTask?.cancel()
            liveActivityUpdateTask?.cancel()
            notificationsUpdateTask = nil
            liveActivityUpdateTask = nil
        }
        .sheet(isPresented: $showSmartNotificationsInfo) {
            smartNotificationsSheet
        }
        .sensoryFeedback(.selection, trigger: showSmartNotificationsInfo)
    }

    // MARK: - Animation
    private func animateEntrance() {
        guard !showGoalCard else { return }

        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4))) {
            showGoalCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.05)) {
            showUnitsCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.1)) {
            showNotificationsCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.15)) {
            showLiveActivityCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.2)) {
            showHapticsCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.225)) {
            showDuckCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.275)) {
            showHealthCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.3)) {
            showTipJarCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.35)) {
            showAboutCard = true
        }
        withAnimation(reduceMotion ? .none : .spring(.smooth(duration: 0.4)).delay(0.4)) {
            showFooter = true
        }
    }

    // MARK: - Update Scheduling
    private func scheduleNotificationsUpdate() {
        notificationsUpdateTask?.cancel()
        notificationsUpdateTask = Task { @MainActor in
            await Task.sleepIgnoringCancellation(milliseconds: 120)
            guard !Task.isCancelled else { return }
            await viewModel.updateNotifications()
        }
    }

    private func scheduleLiveActivityUpdate() {
        liveActivityUpdateTask?.cancel()
        liveActivityUpdateTask = Task { @MainActor in
            await Task.sleepIgnoringCancellation(milliseconds: 120)
            guard !Task.isCancelled else { return }
            await viewModel.updateLiveActivities()
        }
    }

    // MARK: - Daily Goal Card (Hero Card)
    private var dailyGoalCard: some View {
        VStack(spacing: 16) {
            // Large goal display
            VStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color.cyan)
                    .shadow(color: Color.cyan.opacity(0.5), radius: 8)

                Text(goalFormatted)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(Color.onTimeOfDayText)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(.bouncy), value: viewModel.dailyGoalMl)

                Text("settings_daily_goal")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
            }

            // Glass stepper
            glassStepper(
                value: $viewModel.dailyGoalMl,
                range: AppConstants.minDailyGoalMl...AppConstants.maxDailyGoalMl,
                step: AppConstants.dailyGoalStepMl
            )
            .sensoryFeedback(.selection, trigger: viewModel.dailyGoalMl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color.onTimeOfDayCardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .opacity(showGoalCard ? 1 : 0)
        .scaleEffect(showGoalCard ? 1 : 0.98)
    }

    // MARK: - Notifications Card
    private var notificationsCard: some View {
        settingsCard(icon: "bell.fill", title: "settings_notifications", show: showNotificationsCard) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("settings_notifications_toggle", isOn: $viewModel.notificationsEnabled)
                    .tint(Color.cyan)
                    .foregroundStyle(Color.onTimeOfDayText)
                    .sensoryFeedback(.selection, trigger: viewModel.notificationsEnabled)
                    .disabled(viewModel.notificationsStatus == .denied)

                if viewModel.notificationsStatus == .denied {
                    Text("permissions_notifications_denied")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)

                    settingsButton("permissions_open_settings") {
                        openAppSettings()
                    }
                }

                if viewModel.notificationsEnabled {
                    Divider()
                        .background(Color.onTimeOfDayTertiaryText)

                    // Smart Notifications
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("settings_smart_notifications_title")
                                .foregroundStyle(Color.onTimeOfDayText)

                            Button {
                                showSmartNotificationsInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("settings_smart_notifications_info_accessibility")

                            Spacer()

                            Toggle("", isOn: $viewModel.intelligentNotificationsEnabled)
                                .labelsHidden()
                                .tint(Color.cyan)
                                .sensoryFeedback(.selection, trigger: viewModel.intelligentNotificationsEnabled)
                        }

                        Text("settings_smart_notifications_subtitle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    }

                    // Time Range
                    VStack(spacing: 8) {
                        reminderTimeRow(
                            title: "settings_reminder_start",
                            selection: Binding(
                                get: { viewModel.reminderStartDate },
                                set: { viewModel.reminderStartDate = $0 }
                            )
                        )
                        .sensoryFeedback(.selection, trigger: viewModel.reminderStartMinutes)

                        reminderTimeRow(
                            title: "settings_reminder_end",
                            selection: Binding(
                                get: { viewModel.reminderEndDate },
                                set: { viewModel.reminderEndDate = $0 }
                            )
                        )
                        .sensoryFeedback(.selection, trigger: viewModel.reminderEndMinutes)
                    }

                    // Interval
                    HStack {
                        Text(Localized.string(
                            "settings_reminder_interval_value %@",
                            reminderIntervalFormatted
                        ))
                        .foregroundStyle(Color.onTimeOfDayText)

                        Spacer()

                        glassStepper(
                            value: $viewModel.reminderIntervalMinutes,
                            range: 60...240,
                            step: 30
                        )
                        .sensoryFeedback(.selection, trigger: viewModel.reminderIntervalMinutes)
                    }
                }
            }
        }
    }

    // MARK: - Live Activity Card
    private var liveActivityCard: some View {
        settingsCard(icon: "circle.dotted.circle", title: "settings_live_activity", show: showLiveActivityCard) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("settings_live_activity_toggle", isOn: $viewModel.liveActivitiesEnabled)
                    .tint(Color.cyan)
                    .foregroundStyle(Color.onTimeOfDayText)
                    .sensoryFeedback(.selection, trigger: viewModel.liveActivitiesEnabled)

                Toggle("settings_live_activity_silent_toggle", isOn: $viewModel.liveActivitySensitiveModeEnabled)
                    .tint(Color.cyan)
                    .foregroundStyle(Color.onTimeOfDayText)
                    .sensoryFeedback(.selection, trigger: viewModel.liveActivitySensitiveModeEnabled)
                    .disabled(!viewModel.liveActivitiesEnabled)
                    .opacity(viewModel.liveActivitiesEnabled ? 1 : 0.6)
            }
        }
    }

    // MARK: - Haptics Card
    private var hapticsCard: some View {
        settingsCard(icon: "waveform", title: "settings_haptics", show: showHapticsCard) {
            Toggle("settings_haptics_toggle", isOn: $viewModel.hapticsEnabled)
                .tint(Color.cyan)
                .foregroundStyle(Color.onTimeOfDayText)
                .sensoryFeedback(.selection, trigger: viewModel.hapticsEnabled)
        }
    }

    // MARK: - Duck Pond Card
    @State private var renamingDuckIndex: Int? = nil
    @State private var renamingDuckText: String = ""
    @FocusState private var duckNameFieldFocused: Bool

    private var swimmingDuckCard: some View {
        settingsCard(icon: "sparkles", title: "settings_duck_pond", show: showDuckCard) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("settings_duck_pond_toggle", isOn: $viewModel.swimmingDuckEnabled)
                    .tint(Color.yellow)
                    .foregroundStyle(Color.onTimeOfDayText)
                    .sensoryFeedback(.selection, trigger: viewModel.swimmingDuckEnabled)

                if viewModel.duckCount > 0 {
                    duckPondRow
                }

                Text("settings_duck_description")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.onTimeOfDayTertiaryText)

                if viewModel.duckCount < AppConstants.maxVisibleDucks && viewModel.duckCount > 0 {
                    Text(Localized.string("settings_duck_remaining %d", AppConstants.maxVisibleDucks - viewModel.duckCount))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDayTertiaryText)
                }
            }
        }
    }

    @State private var duckBobPhase = false

    @ViewBuilder
    private var duckPondRow: some View {
        let visibleCount = min(viewModel.duckCount, AppConstants.maxVisibleDucks)
        let startIndex = max(1, viewModel.duckCount - AppConstants.maxVisibleDucks + 1)

        if visibleCount > 0 {
            HStack(spacing: 0) {
                ForEach(startIndex...(startIndex + visibleCount - 1), id: \.self) { duckIndex in
                let bobDelay = Double(duckIndex - startIndex) * 0.3

                VStack(spacing: 5) {
                    Image(viewModel.duckImageName(forCount: duckIndex))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .offset(y: duckBobPhase ? -2 : 2)
                        .animation(
                            .spring(.smooth(duration: 1.8 + bobDelay))
                            .repeatForever(autoreverses: true)
                            .delay(bobDelay),
                            value: duckBobPhase
                        )

                    if renamingDuckIndex == duckIndex {
                        TextField("", text: $renamingDuckText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.onTimeOfDayText)
                            .multilineTextAlignment(.center)
                            .focused($duckNameFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { commitDuckRename() }
                            .frame(width: 58)
                            .onChange(of: renamingDuckText) { _, newValue in
                                if newValue.count > 10 {
                                    renamingDuckText = String(newValue.prefix(10))
                                }
                            }
                    } else {
                        Text(viewModel.duckName(forCount: duckIndex))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                            .lineLimit(1)
                            .frame(maxWidth: 58)
                            .truncationMode(.tail)
                            .onTapGesture {
                                renamingDuckIndex = duckIndex
                                renamingDuckText = viewModel.duckName(forCount: duckIndex)
                                duckNameFieldFocused = true
                            }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            duckBobPhase = true
        }
        .sensoryFeedback(.selection, trigger: renamingDuckIndex)
        }
    }

    private func commitDuckRename() {
        guard let index = renamingDuckIndex else { return }
        let trimmed = renamingDuckText.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.renameDuck(atCount: index, to: String(trimmed.prefix(10)))
        renamingDuckIndex = nil
        duckNameFieldFocused = false
    }

    // MARK: - Health Card
    private var healthCard: some View {
        settingsCard(icon: "heart.fill", title: "settings_health", show: showHealthCard) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("settings_health_status")
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(healthStatusColor)
                            .frame(width: 8, height: 8)

                        Text(viewModel.healthStatusKey)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.onTimeOfDayText)
                    }
                }

                if viewModel.healthStatus == .denied {
                    Text("permissions_health_denied")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)

                    settingsButton("permissions_open_settings") {
                        openAppSettings()
                    }
                }

                if viewModel.healthStatus != .authorized {
                    settingsButton("settings_health_request_access", isLoading: viewModel.isRequestingHealthAccess) {
                        Task { await viewModel.requestHealthAccess() }
                    }
                    .disabled(viewModel.isRequestingHealthAccess)
                }
            }
        }
    }

    private var healthStatusColor: Color {
        switch viewModel.healthStatus {
        case .authorized: return .green
        case .denied: return .red
        case .notDetermined, .unknown: return .orange
        }
    }

    // MARK: - Units Card
    private var unitsCard: some View {
        settingsCard(icon: "ruler", title: "settings_units", show: showUnitsCard) {
            VStack(alignment: .leading, spacing: 10) {
                unitSegmentedControl
                    .sensoryFeedback(.selection, trigger: viewModel.preferredVolumeUnit)

                if viewModel.preferredVolumeUnit == .auto {
                    let resolvedName = VolumeUnit.auto.resolved == .ml
                        ? String(localized: "settings_units_ml")
                        : String(localized: "settings_units_oz")
                    Text(Localized.string("settings_units_auto_hint %@", resolvedName))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }
            }
        }
    }

    private var unitSegmentedControl: some View {
        HStack(spacing: 6) {
            unitSegmentButton(title: "settings_units_auto", unit: .auto)
            unitSegmentButton(title: "settings_units_ml", unit: .ml)
            unitSegmentButton(title: "settings_units_oz", unit: .oz)
        }
        .padding(4)
        .background(
            Color.onTimeOfDayText.opacity(TimeOfDayPeriod.current.hasLightBackground ? 0.06 : 0.12),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func unitSegmentButton(title: LocalizedStringKey, unit: VolumeUnit) -> some View {
        let isSelected = viewModel.preferredVolumeUnit == unit
        return Button {
            viewModel.preferredVolumeUnit = unit
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color(white: 0.15) : Color.onTimeOfDayText.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.92))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.clear)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(.snappy), value: viewModel.preferredVolumeUnit)
    }

    // MARK: - Tip Jar Card
    private var tipJarCard: some View {
        settingsCard(icon: "heart.circle.fill", title: "settings_tip_jar", show: showTipJarCard) {
            VStack(alignment: .leading, spacing: 12) {
                if tipJarViewModel.hasTipped && !tipJarViewModel.showThankYou {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                        Text("settings_tip_jar_supporter")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.onTimeOfDayText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color.pink.opacity(0.12),
                        in: Capsule()
                    )
                }

                if tipJarViewModel.showThankYou {
                    tipThankYouBanner
                } else {
                    Text("settings_tip_jar_description")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                        .transition(.opacity)
                }

                if tipJarViewModel.isLoading {
                    ProgressView()
                        .tint(Color.onTimeOfDaySecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if tipJarViewModel.products.isEmpty && tipJarViewModel.errorMessage == nil {
                    Text("settings_tip_jar_unavailable")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDayTertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                } else if !tipJarViewModel.showThankYou {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(tipJarViewModel.products, id: \.id) { product in
                            tipButton(for: product)
                        }
                    }
                    .transition(.opacity)
                }

                if let error = tipJarViewModel.errorMessage {
                    Text(error)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red.opacity(0.9))
                }
            }
            .animation(.spring(.smooth), value: tipJarViewModel.showThankYou)
        }
        .sensoryFeedback(.success, trigger: tipJarViewModel.showThankYou) { _, new in
            new == true
        }
    }

    @State private var tipDuckCelebrating = false
    @State private var tipHeartScale: CGFloat = 1.0
    @State private var tipHeartGlow: Double = 0.3
    @State private var tipHeartbeatTask: Task<Void, Never>?
    @State private var tipHeartLub = 0
    @State private var tipHeartDub = 0

    private var tipThankYouBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                // Duck celebrating
                Image("duck_glass")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(tipDuckCelebrating ? -12 : 12))
                    .offset(y: tipDuckCelebrating ? -4 : 2)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .animation(
                        .spring(.bouncy(duration: 0.4)).repeatCount(5, autoreverses: true),
                        value: tipDuckCelebrating
                    )

                // Pulsing heart
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.pink.opacity(tipHeartGlow), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .red.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .pink.opacity(0.4), radius: 8, y: 4)
                        .scaleEffect(tipHeartScale)
                }
            }

            Text("settings_tip_jar_thank_you")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onTimeOfDayText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            Color.cyan.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .transition(.scale.combined(with: .opacity))
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: tipHeartLub)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: tipHeartDub)
        .onAppear {
            tipDuckCelebrating = true
            tipHeartbeatTask?.cancel()
            tipHeartbeatTask = Task { @MainActor in
                await Task.sleepIgnoringCancellation(milliseconds: 400)
                guard !Task.isCancelled else { return }
                await tipHeartbeatLoop()
            }
        }
        .onDisappear {
            tipDuckCelebrating = false
            tipHeartbeatTask?.cancel()
            tipHeartbeatTask = nil
            tipHeartScale = 1.0
            tipHeartGlow = 0.3
        }
    }

    private func tipHeartbeatLoop() async {
        while !Task.isCancelled {
            tipHeartLub += 1
            withAnimation(.spring(.bouncy(duration: 0.15))) {
                tipHeartScale = 1.15
                tipHeartGlow = 0.6
            }

            await Task.sleepIgnoringCancellation(milliseconds: 150)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(.smooth(duration: 0.15))) {
                tipHeartScale = 1.0
                tipHeartGlow = 0.3
            }

            await Task.sleepIgnoringCancellation(milliseconds: 120)
            guard !Task.isCancelled else { return }
            tipHeartDub += 1
            withAnimation(.spring(.bouncy(duration: 0.15))) {
                tipHeartScale = 1.10
                tipHeartGlow = 0.5
            }

            await Task.sleepIgnoringCancellation(milliseconds: 150)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(.smooth(duration: 0.2))) {
                tipHeartScale = 1.0
                tipHeartGlow = 0.3
            }

            await Task.sleepIgnoringCancellation(milliseconds: 600)
        }
    }

    @ViewBuilder
    private func tipButton(for product: Product) -> some View {
        let isPurchasing = tipJarViewModel.purchasingProductID == product.id
        Button {
            Task { await tipJarViewModel.purchase(product) }
        } label: {
            VStack(spacing: 4) {
                Text(tipEmoji(for: product.id))
                    .font(.title2)
                Text(product.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)
                    .lineLimit(1)
                ZStack {
                    Text(product.displayPrice)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.onTimeOfDayText)
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing {
                        ProgressView()
                            .tint(Color.onTimeOfDayText)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .glassEffect(
            .regular.tint(Color.cyan.opacity(0.15)).interactive(),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .disabled(tipJarViewModel.purchasingProductID != nil)
    }

    private func tipEmoji(for productID: String) -> String {
        switch productID {
        case "com.glasswater.tip.droplet2": "💧"
        case "com.glasswater.tip.glass2": "🥤"
        case "com.glasswater.tip.wave2": "🌊"
        case "com.glasswater.tip.waterfall2": "🏞️"
        default: "💧"
        }
    }

    // MARK: - About Card
    private var aboutCard: some View {
        settingsCard(icon: "info.circle", title: "settings_about", show: showAboutCard) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    if let url = URL(string: "https://glasswaterapp.com/privacy") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Text("settings_privacy_policy")
                            .foregroundStyle(Color.onTimeOfDayText)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    }
                }
                .buttonStyle(.plain)

                Divider()
                    .background(Color.onTimeOfDayTertiaryText)

                Button {
                    if let url = URL(string: "https://glasswaterapp.com/terms") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Text("settings_terms")
                            .foregroundStyle(Color.onTimeOfDayText)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    }
                }
                .buttonStyle(.plain)

                Divider()
                    .background(Color.onTimeOfDayTertiaryText)

                Button {
                    if let url = URL(string: "https://apps.apple.com/app/id\(AppConstants.appStoreId)?action=write-review") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Text("settings_rate_app")
                            .foregroundStyle(Color.onTimeOfDayText)
                        Spacer()
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    }
                }
                .buttonStyle(.plain)

                Divider()
                    .background(Color.onTimeOfDayTertiaryText)

                HStack {
                    Text("settings_app_version")
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(Color.onTimeOfDayText)
                        .font(.body.weight(.medium))
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        #if DEBUG
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
        #else
        return version
        #endif
    }

    // MARK: - Smart Notifications Sheet
    private var smartNotificationsSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.cyan)

                    Text("settings_smart_notifications_sheet_title")
                        .font(.title3.weight(.bold))
                }

                Text("settings_smart_notifications_sheet_body")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: - Reusable Components
    @ViewBuilder
    private func settingsCard<Content: View>(
        icon: String,
        title: LocalizedStringKey,
        show: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.cyan)
                    .shadow(color: Color.cyan.opacity(0.4), radius: 4)

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)
            }

            content()
        }
        .padding(16)
        .background(Color.onTimeOfDayCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .opacity(show ? 1 : 0)
        .scaleEffect(show ? 1 : 0.98)
    }

    @ViewBuilder
    private func settingsButton(
        _ title: LocalizedStringKey,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .tint(Color.onTimeOfDayText)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.onTimeOfDayText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .glassEffect(.regular.tint(Color.cyan.opacity(0.1)).interactive(), in: .capsule)
        .opacity(isLoading ? 0.6 : 1)
    }

    @ViewBuilder
    private func reminderTimeRow(
        title: LocalizedStringKey,
        selection: Binding<Date>
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.onTimeOfDayText)

            Spacer()

            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Color.cyan)
                .environment(\.colorScheme, controlColorScheme)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Color.onTimeOfDayText.opacity(TimeOfDayPeriod.current.hasLightBackground ? 0.08 : 0.16),
                    in: Capsule()
                )
        }
    }

    @ViewBuilder
    private func glassStepper(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack(spacing: 0) {
            Button {
                let newValue = value.wrappedValue - step
                if newValue >= range.lowerBound {
                    value.wrappedValue = newValue
                }
            } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)
                    .frame(width: 44, height: 44)
            }
            .disabled(value.wrappedValue <= range.lowerBound)
            .opacity(value.wrappedValue <= range.lowerBound ? 0.4 : 1)

            Divider()
                .frame(height: 20)
                .background(Color.onTimeOfDayTertiaryText)

            Button {
                let newValue = value.wrappedValue + step
                if newValue <= range.upperBound {
                    value.wrappedValue = newValue
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)
                    .frame(width: 44, height: 44)
            }
            .disabled(value.wrappedValue >= range.upperBound)
            .opacity(value.wrappedValue >= range.upperBound ? 0.4 : 1)
        }
        .glassEffect(.regular.tint(Color.cyan.opacity(0.08)).interactive(), in: .capsule)
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
    }

    // MARK: - Helpers
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
