//
//  HomeView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import StoreKit
import SwiftUI
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var showEntriesSheet = false
    @State private var showCustomAmountSheet = false
    @State private var customAmountSelection = AppConstants.defaultCustomAmountMl
    @State private var showRing = false
    @State private var hasBeenInBackground = false
    @State private var showActionBar = false
    @State private var undoPulse = false
    @State private var unitVersion = 0
    @State private var tappedDuckName: String = ""
    @State private var tappedDuckX: CGFloat = 0
    @State private var tappedDuckY: CGFloat = 0
    @State private var showDuckBubble = false
    @State private var bubbleDismissTask: Task<Void, Never>?
    @State private var waterAttractionX: CGFloat?
    @State private var waterAttractionStartTime: Double?
    @State private var previousAttractionX: CGFloat?
    @State private var tappedDuckIndex: Int?
    @State private var tappedDuckTime: Double?
    #if DEBUG
    @State private var showDebugSheet = false
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let analytics: any AnalyticsTracking
    init(services: AppServices) {
        _viewModel = State(initialValue: HomeViewModel(services: services))
        analytics = services.analytics
    }

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await viewModel.undoLastEntry() }
            } label: {
                Label("home_undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.onTimeOfDayText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .glassEffect(.regular.tint(Color.cyan.opacity(0.1)).interactive(), in: .capsule)
            .overlay {
                Capsule()
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 0.8)
                    .scaleEffect(undoPulse ? 1.3 : 1.0)
                    .opacity(undoPulse ? 0 : 0.6)
            }
            .opacity(viewModel.canUndo ? 1 : 0)
            .scaleEffect(viewModel.canUndo ? 1 : 0.8)
            .animation(.spring(.bouncy), value: viewModel.canUndo)
            .allowsHitTesting(viewModel.canUndo)
            .accessibilityHidden(!viewModel.canUndo)
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.canUndo)
            .onChange(of: viewModel.canUndo) { _, canUndo in
                if canUndo {
                    undoPulse = false
                    withAnimation(.spring(.smooth(duration: 0.6))) {
                        undoPulse = true
                    }
                }
            }

            ActionBarView(
                quickAddOptions: viewModel.quickAddOptions,
                customAmountMl: viewModel.customAmountMl,
                onAdd: { amount in
                    Task { await viewModel.add(amountMl: amount) }
                },
                onCustom: {
                    customAmountSelection = viewModel.customAmountMl
                    showCustomAmountSheet = true
                }
            )
            .id(unitVersion)
            .opacity(showActionBar ? 1 : 0)
            .scaleEffect(showActionBar ? 1 : 0.95, anchor: .bottom)
        }
    }

    private var greetingEmoji: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "☀️"
        case 12..<18: return "🌤️"
        default: return "🌙"
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return String(localized: "home_greeting_morning")
        case 12..<18:
            return String(localized: "home_greeting_afternoon")
        default:
            return String(localized: "home_greeting_evening")
        }
    }

    var body: some View {
        ZStack {
            TimeOfDayBackgroundView(lightenNight: true)
            WaterFillBackgroundView(
                progress: viewModel.progress,
                duckCount: viewModel.swimmingDuckEnabled
                    ? viewModel.sequencer.visibleDuckCount
                    : 0,
                attractionX: waterAttractionX,
                attractionStartTime: waterAttractionStartTime,
                previousAttractionX: previousAttractionX,
                tappedDuckIndex: tappedDuckIndex,
                tappedDuckTime: tappedDuckTime
            )
            .animation(.spring(.bouncy(duration: 0.8)), value: viewModel.sequencer.visibleDuckCount)

            // Water/duck tap gesture overlay
            waterTapOverlay

            VStack {
                if !isLandscape {
                    Spacer()
                } else {
                    Spacer().frame(height: 16)
                }

                FloatingActivityRingView(
                    progress: viewModel.progress,
                    currentMl: viewModel.todayTotalMl,
                    goalMl: viewModel.dailyGoalMl,
                    streakCount: viewModel.streakCount,
                    goalReached: viewModel.goalReached,
                    greetingEmoji: greetingEmoji,
                    greetingText: greetingText,
                    recentlyAdded: viewModel.recentlyAdded,
                    hydrationStatus: viewModel.hydrationStatus,
                    justReachedGoal: viewModel.sequencer.justReachedGoal,
                    onTap: { showEntriesSheet = true }
                )
                .id(unitVersion)
                .opacity(showRing ? 1 : 0)
                .scaleEffect(showRing ? 1 : 0.9, anchor: .center)

                Spacer()
            }
        }
        .overlay {
            // Duck reward overlay — must be outside ZStack to render above glass effects
            if viewModel.sequencer.showDuckReward {
                DuckRewardOverlay(
                    duckCount: viewModel.sequencer.visibleDuckCount,
                    isFirstTime: viewModel.sequencer.isFirstDuckReward,
                    duckImageName: viewModel.sequencer.rewardDuckImageName,
                    duckName: viewModel.sequencer.rewardDuckName,
                    onDismiss: { viewModel.dismissDuckReward() },
                    onRename: { newName in
                        viewModel.renameDuck(atCount: viewModel.sequencer.visibleDuckCount, to: newName)
                    }
                )
            }
        }
        .overlay {
            // Duck name bubble — above everything including glass effects
            if showDuckBubble {
                let bubbleY = viewModel.goalReached
                    ? tappedDuckY + 35   // goal reached: water at top, name below duck
                    : tappedDuckY - 30   // water lower: name above duck
                DuckNameBubble(name: tappedDuckName)
                    .position(x: tappedDuckX, y: bubbleY)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if viewModel.hasTipped {
                SupporterStarBadge()
                    .padding(.leading, 16)
                    .padding(.top, 0)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isLandscape {
                bottomBar
            }
        }
        .overlay(alignment: .bottom) {
            if isLandscape {
                bottomBar
                    .padding(.bottom, 4)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.isInForeground = true
            analytics.logScreenView(screenName: "home")
            Task { await viewModel.load() }

            // Animação de entrada em cascata
            if reduceMotion {
                showRing = true
                showActionBar = true
            } else {
                withAnimation(.spring(.bouncy(duration: 0.5)).delay(0.1)) {
                    showRing = true
                }
                withAnimation(.spring(.bouncy(duration: 0.4)).delay(0.25)) {
                    showActionBar = true
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.isInForeground = (newPhase == .active)
            if newPhase == .background {
                hasBeenInBackground = true
            }
            // Only reload on return from background (not on initial .active which overlaps with onAppear).
            // iOS transitions: background → inactive → active, so we track background visits explicitly.
            guard newPhase == .active, hasBeenInBackground else { return }
            hasBeenInBackground = false
            Task { await viewModel.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hydrationDidChangeExternally)) { _ in
            viewModel.refreshFromExternalChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hydrationDidChangeFromHistory)) { _ in
            Task { await viewModel.refreshFromHistoryChange() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .volumeUnitDidChange)) { _ in
            unitVersion += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidChange)) { _ in
            viewModel.reloadDuckSetting()
        }
        .onChange(of: showEntriesSheet) { _, isShowing in
            if isShowing { analytics.logScreenView(screenName: "home_entries_sheet") }
        }
        .onChange(of: showCustomAmountSheet) { _, isShowing in
            if isShowing { analytics.logScreenView(screenName: "custom_amount_sheet") }
        }
        .onChange(of: viewModel.shouldRequestReview) { _, shouldRequest in
            guard shouldRequest else { return }
            viewModel.shouldRequestReview = false
            requestReview()
        }
        .sheet(isPresented: $showEntriesSheet) {
            HomeEntriesSheetView(
                entries: viewModel.todayEntries,
                dailyGoalMl: viewModel.dailyGoalMl,
                onDelete: { entry in
                    Task { await viewModel.deleteEntry(entry) }
                },
                onUpdate: { entry, amount, date in
                    Task { await viewModel.updateEntry(entry, amountMl: amount, date: date) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showCustomAmountSheet) {
            CustomAmountSheetView(
                selection: $customAmountSelection,
                onSave: { amount in
                    Task { await viewModel.addCustom(amountMl: amount) }
                }
            )
        }
        #if DEBUG
        .onLongPressGesture(minimumDuration: 2) {
            showDebugSheet = true
        }
        .sheet(isPresented: $showDebugSheet) {
            DuckDebugSheet(viewModel: viewModel)
        }
        #endif
        .environment(\.lightenedNightBackground, true)
    }

    // MARK: - Water Tap Overlay

    private var waterTapOverlay: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { location in
                    handleWaterTap(at: location, in: geometry.size)
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(viewModel.swimmingDuckEnabled && !viewModel.sequencer.showDuckReward)
        .onDisappear {
            bubbleDismissTask?.cancel()
            bubbleDismissTask = nil
        }
    }

    private static let duckBubbleEmojisMorning = [
        "😊", "☀️", "🌅", "✨", "💧", "🎵", "🫧", "😄", "🌤️"
    ]
    private static let duckBubbleEmojisAfternoon = [
        "😊", "🌤️", "💧", "🎶", "✨", "🫧", "😄", "💦", "🌊"
    ]
    private static let duckBubbleEmojisEvening = [
        "😌", "🌙", "✨", "💧", "🎵", "🫧", "🌟", "💤", "🪿"
    ]

    private var duckBubbleEmojis: [String] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return Self.duckBubbleEmojisMorning
        case 12..<18: return Self.duckBubbleEmojisAfternoon
        default: return Self.duckBubbleEmojisEvening
        }
    }

    private func handleWaterTap(at location: CGPoint, in size: CGSize) {
        let now = Date.timeIntervalSinceReferenceDate
        let visibleDuckCount = viewModel.swimmingDuckEnabled
            ? viewModel.sequencer.visibleDuckCount
            : 0

        #if DEBUG
        AppLog.info("[DuckTap] tap=\(location) geoSize=\(size) visibleDucks=\(visibleDuckCount) progress=\(viewModel.progress)", category: .userAction)
        #endif

        // Compute current duck positions on-demand
        let positions = SwimmingDuckOverlay.currentPositions(
            time: now,
            wavePhase: (now / 14) * .pi * 2,  // matches WaveConfig.wave1Duration
            waveAmplitude: 10 * (1.0 - viewModel.progress * 0.3),  // matches WaveConfig.wave1Amplitude * calmFactor
            waveFrequency: 1.1,  // matches WaveConfig.wave1Frequency
            fillLevel: viewModel.progress,
            size: size,
            duckCount: visibleDuckCount,
            attractionX: waterAttractionX,
            attractionStartTime: waterAttractionStartTime,
            previousAttractionX: previousAttractionX
        )

        // Check if a duck was tapped — find the closest one (not just first hit)
        let tapRadius: CGFloat = 35
        var closestDuck: DuckPosition?
        var closestDistance: CGFloat = .infinity
        for position in positions {
            let dx = location.x - position.x
            let dy = location.y - position.y
            let distance = sqrt(dx * dx + dy * dy)
            let hitRadius = tapRadius + position.height * 0.3
            if distance < hitRadius && distance < closestDistance {
                closestDuck = position
                closestDistance = distance
            }
        }

        if let hit = closestDuck {
            let name = viewModel.duckName(forDuckCount: hit.index + 1)
            let emoji = duckBubbleEmojis.randomElement() ?? "💧"
            #if DEBUG
            AppLog.info("[DuckTap] HIT duck[\(hit.index)] name=\(name) dist=\(String(format: "%.1f", closestDistance))", category: .userAction)
            #endif
            tappedDuckName = "\(name) \(emoji)"
            tappedDuckX = hit.x
            tappedDuckY = hit.y
            tappedDuckIndex = hit.index
            tappedDuckTime = now

            withAnimation(.spring(.bouncy(duration: 0.3))) {
                showDuckBubble = true
            }
            viewModel.playDuckSound()

            bubbleDismissTask?.cancel()
            bubbleDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.0))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(.smooth(duration: 0.3))) {
                    showDuckBubble = false
                    }
                }
                return
            }

        // No duck hit — water tap: attract ducks toward tap X
        // Block new attraction while ducks are still swimming
        // Distance mirrors computeAttraction: origin → target (not center → tap)
        if let startTime = waterAttractionStartTime, let currentAttrX = waterAttractionX {
            let elapsed = now - startTime
            let origin = previousAttractionX ?? 0.5
            let distance = Double(abs(currentAttrX - origin))
            let duration = max(7.0, distance * 25.0)
            if elapsed < duration {
                #if DEBUG
                AppLog.info("[DuckAttract] BLOCKED — ducks still swimming (elapsed=\(String(format: "%.1f", elapsed))/\(String(format: "%.1f", duration))s)", category: .userAction)
                #endif
                return
            }
        }

        let relX = location.x / size.width
        previousAttractionX = waterAttractionX
        #if DEBUG
        AppLog.info("[DuckAttract] START tapX=\(location.x) relX=\(String(format: "%.3f", relX)) prevX=\(String(format: "%.3f", previousAttractionX ?? -1)) time=\(String(format: "%.2f", now))", category: .userAction)
        #endif
        waterAttractionX = relX
        waterAttractionStartTime = now
    }
}

// MARK: - Duck Name Bubble

private struct DuckNameBubble: View {
    let name: String
    @State private var appeared = false

    var body: some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.onTimeOfDayText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.onTimeOfDayCardBackground)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            )
            .scaleEffect(appeared ? 1.0 : 0.5)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(.bouncy(duration: 0.3))) {
                    appeared = true
                }
            }
    }
}

// MARK: - Debug Sheet

#if DEBUG
private struct DuckDebugSheet: View {
    let viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("State") {
                    LabeledContent("Duck Count", value: "\(viewModel.sequencer.visibleDuckCount)")
                    LabeledContent("Ducks Enabled", value: viewModel.swimmingDuckEnabled ? "Yes" : "No")
                    LabeledContent("Goal Reached", value: viewModel.goalReached ? "Yes" : "No")
                    LabeledContent("Today Total", value: "\(viewModel.todayTotalMl) / \(viewModel.dailyGoalMl) ml")
                }

                Section("Full Reset") {
                    Button("Reset all + goal 100ml (ready to test)") {
                        dismiss()
                        Task { @MainActor in
                            await viewModel.debugResetForFirstDuckTest()
                        }
                    }
                    .fontWeight(.semibold)
                }

                Section("Preview Overlays") {
                    Button("Show first-time reward") {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.3))
                            viewModel.debugTriggerDuckReward(asFirstTime: true)
                        }
                    }
                    Button("Show normal reward") {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.3))
                            viewModel.debugTriggerDuckReward(asFirstTime: false)
                        }
                    }
                }

                Section("Duck Count") {
                    ForEach([1, 2, 3, 4, 5], id: \.self) { count in
                        Button("Set to \(count) duck\(count > 1 ? "s" : "")") {
                            viewModel.debugSetDuckCount(count)
                        }
                    }
                }
            }
            .navigationTitle("Duck Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
