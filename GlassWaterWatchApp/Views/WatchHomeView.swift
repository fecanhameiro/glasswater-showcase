//
//  WatchHomeView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchHomeView: View {
    @Bindable var viewModel: WatchHomeViewModel
    @State private var showCustomAmountSheet = false
    @State private var customAmountSelection = AppConstants.defaultCustomAmountMl

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let metrics = WatchLayoutMetrics(screenWidth: geo.size.width)

                ZStack {
                    WatchGradientBackground()

                    if !viewModel.hasCompletedOnboarding {
                        watchOnboardingView
                    } else if isLuminanceReduced {
                        alwaysOnView(metrics: metrics)
                    } else {
                        mainContent(metrics: metrics)
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomAmountSheet) {
            WatchCustomAmountSheetView(selection: $customAmountSelection) { amount in
                viewModel.addCustom(amountMl: amount)
            }
        }
        .task {
            viewModel.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.load()
            }
        }
    }

    // MARK: - Main Content

    private func mainContent(metrics: WatchLayoutMetrics) -> some View {
        ScrollView {
            VStack(spacing: metrics.mainSpacing) {
                // Hero: Progress ring with celebration overlay
                ZStack {
                    progressSection(metrics: metrics)

                    WatchCelebrationOverlayView(isActive: viewModel.justReachedGoal)
                }

                // Two action buttons
                WatchQuickAddGridView(
                    quickAddAmountMl: viewModel.quickAddAmountMl,
                    isCompletingGoal: viewModel.isCompletingGoal,
                    customAmountMl: viewModel.customAmountMl,
                    metrics: metrics,
                    onAdd: { amount in
                        viewModel.add(amountMl: amount)
                    },
                    onCustom: {
                        customAmountSelection = viewModel.customAmountMl
                        showCustomAmountSheet = true
                    }
                )

            }
            .padding(.horizontal, metrics.scrollHorizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, metrics.scrollVerticalPadding)
        }
        .overlay(alignment: .topLeading) {
            if viewModel.showUndoToast {
                WatchUndoToastView(
                    onUndo: { viewModel.undoFromToast() },
                    duration: 8
                )
                .id(viewModel.undoToastId)
                .transition(.scale(scale: 0.5, anchor: .topLeading).combined(with: .opacity))
                .padding(.top, 2)
                .padding(.leading, 4)
            }
        }
        .animation(.spring(.bouncy(duration: 0.25)), value: viewModel.showUndoToast)
    }

    // MARK: - Progress Section

    private func progressSection(metrics: WatchLayoutMetrics) -> some View {
        VStack(spacing: metrics.cardSpacing) {
            WatchProgressRingView(
                progress: viewModel.progress,
                currentMl: viewModel.dailyTotalMl,
                goalMl: viewModel.dailyGoalMl,
                goalReached: viewModel.goalReached,
                recentlyAdded: viewModel.recentlyAdded,
                metrics: metrics
            )

            WatchStatusBadgeView(
                progress: viewModel.progress,
                goalReached: viewModel.goalReached
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Onboarding Placeholder

    private var watchOnboardingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.2), Color.cyan.opacity(0.04), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "drop.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .cyan.opacity(0.4), radius: 6, y: 2)
            }

            VStack(spacing: 6) {
                Text("GlassWater")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)

                Text("watch_onboarding_subtitle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Always-On Display

    private func alwaysOnView(metrics: WatchLayoutMetrics) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.cyan.opacity(0.1), lineWidth: metrics.aodStroke)
                    .frame(width: metrics.aodRingSize, height: metrics.aodRingSize)

                Circle()
                    .trim(from: 0, to: min(viewModel.progress, 1.0))
                    .stroke(
                        Color.cyan.opacity(0.6),
                        style: StrokeStyle(lineWidth: metrics.aodStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: metrics.aodRingSize, height: metrics.aodRingSize)

                VStack(spacing: 2) {
                    Image(systemName: viewModel.goalReached ? "checkmark" : "drop.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            viewModel.goalReached
                                ? Color.green.opacity(0.7)
                                : Color.cyan.opacity(0.7)
                        )

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Text(VolumeFormatters.string(fromMl: viewModel.dailyTotalMl, unitStyle: .short))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Int(viewModel.progress * 100))%, \(VolumeFormatters.string(fromMl: viewModel.dailyTotalMl, unitStyle: .short))"))
    }
}
