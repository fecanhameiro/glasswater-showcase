//
//  OnboardingView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI
import UIKit

struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel
    @State private var currentStep = 0
    @State private var showContent = false
    @State private var stepTransitionTrigger = 0

    // Water transition for completion step (at root level for full screen)
    @State private var completionWaterProgress: Double = 0.1
    @State private var waterRiseHaptic = 0

    let onComplete: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private let totalSteps = 6

    private let analytics: any AnalyticsTracking

    private static let stepNames = ["welcome", "health", "notifications", "goal", "widget_preview", "complete"]

    init(services: AppServices, onComplete: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(services: services))
        self.onComplete = onComplete
        analytics = services.analytics
    }

    var body: some View {
        ZStack {
            TimeOfDayBackgroundView()

            // Water background for completion step - at root level for full screen coverage
            if currentStep == 5 {
                WaterFillBackgroundView(progress: completionWaterProgress)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                // Step indicator (hidden on welcome and completion)
                if currentStep > 0 && currentStep < totalSteps - 1 {
                    OnboardingStepIndicator(currentStep: currentStep - 1, totalSteps: 4)
                        .padding(.top, isLandscape ? 16 : 60)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 0)

                // Step content
                Group {
                    switch currentStep {
                    case 0:
                        WelcomeStepView(isLandscape: isLandscape, onContinue: nextStep)
                    case 1:
                        HealthStepView(
                            isLandscape: isLandscape,
                            viewModel: viewModel,
                            onContinue: nextStep,
                            onOpenSettings: openAppSettings
                        )
                    case 2:
                        NotificationsStepView(
                            isLandscape: isLandscape,
                            viewModel: viewModel,
                            onContinue: nextStep,
                            onOpenSettings: openAppSettings
                        )
                    case 3:
                        GoalSetupStepView(
                            isLandscape: isLandscape,
                            viewModel: viewModel,
                            onContinue: nextStep
                        )
                    case 4:
                        WidgetPreviewStepView(
                            isLandscape: isLandscape,
                            goalMl: viewModel.dailyGoalMl,
                            onContinue: nextStep
                        )
                    case 5:
                        CompletionStepView(
                            isLandscape: isLandscape,
                            waterProgress: $completionWaterProgress,
                            waterRiseHaptic: $waterRiseHaptic,
                            onComplete: complete
                        )
                    default:
                        EmptyView()
                    }
                }
                .id(currentStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 0)
            }
        }
        .sensoryFeedback(.selection, trigger: stepTransitionTrigger)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: waterRiseHaptic)
        .onAppear {
            Task { await viewModel.load() }
            viewModel.trackStep(0, name: Self.stepNames[0])
            analytics.logScreenView(screenName: "onboarding_\(Self.stepNames[0])")
        }
        .onChange(of: currentStep) { _, newStep in
            guard newStep < Self.stepNames.count else { return }
            viewModel.trackStep(newStep, name: Self.stepNames[newStep])
            analytics.logScreenView(screenName: "onboarding_\(Self.stepNames[newStep])")
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.load() }
        }
        .onChange(of: viewModel.notificationsEnabled) { _, _ in
            Task { await viewModel.updateNotifications() }
        }
    }

    private func nextStep() {
        stepTransitionTrigger += 1
        withAnimation(.spring(.smooth(duration: 0.5))) {
            currentStep += 1
        }
    }

    private func complete() {
        Task {
            await viewModel.complete()
            onComplete()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

// MARK: - Step Indicator

private struct OnboardingStepIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index == currentStep ? Color.cyan.opacity(0.6) : Color.clear)
                        .frame(width: index == currentStep ? 24 : 8, height: 8)
                        .glassEffect(
                            index == currentStep
                                ? .regular.tint(Color.cyan.opacity(0.3))
                                : .regular,
                            in: .capsule
                        )
                        .animation(.spring(.bouncy), value: currentStep)
                }
            }
        }
    }
}

// MARK: - Welcome Step

private struct WelcomeStepView: View {
    let isLandscape: Bool
    let onContinue: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var dropScale: CGFloat = 0.3
    @State private var dropOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var floatOffset: CGFloat = 0
    @State private var hapticTrigger = 0
    @State private var splashHaptic = 0
    @State private var splashTask: Task<Void, Never>?

    // Interactive drop states
    @State private var dropTapped = false
    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 0
    @State private var hintOpacity: Double = 1.0
    @State private var dropTapHaptic = 0
    @State private var dropBounceScale: CGFloat = 1.0

    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "home_greeting_morning")
        case 12..<18: return String(localized: "home_greeting_afternoon")
        default: return String(localized: "home_greeting_evening")
        }
    }

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: splashHaptic)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: dropTapHaptic)
        .onAppear {
            withAnimation(.spring(.smooth(duration: 0.6)).delay(0.1)) {
                titleOpacity = 1.0
            }
            splashTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                splashHaptic += 1
            }
            withAnimation(.spring(.bouncy(duration: 0.8)).delay(0.3)) {
                dropScale = 1.0
                dropOpacity = 1.0
                glowOpacity = 1.0
            }
            withAnimation(.spring(.smooth).delay(0.6)) {
                textOpacity = 1.0
            }
            withAnimation(.spring(.smooth).delay(0.8)) {
                buttonOpacity = 1.0
            }
            withAnimation(.spring(.smooth(duration: 2.5)).repeatForever(autoreverses: true).delay(1.2)) {
                floatOffset = -12
            }
        }
        .onDisappear {
            splashTask?.cancel()
        }
    }

    // MARK: Portrait

    private var portraitBody: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 40) {
                    Text("GlassWater")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.waterGradientStart, Color.waterGradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.waterDrop.opacity(0.3), radius: 8, y: 4)
                        .opacity(titleOpacity)

                    dropVisual(iconSize: 140, glowSize: 200, glowRadius: 100, rippleSize: 160)

                    Text("onboarding_tap_drop_hint")
                        .font(.caption)
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                        .opacity(hintOpacity * textOpacity)

                    VStack(spacing: 6) {
                        Text(timeBasedGreeting)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.onTimeOfDayText)

                        Text("onboarding_greeting_invitation")
                            .font(.body)
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .opacity(textOpacity)

                    continueButton
                        .opacity(buttonOpacity)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Landscape

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            dropVisual(iconSize: 100, glowSize: 160, glowRadius: 80, rippleSize: 130)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                Text("GlassWater")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.waterGradientStart, Color.waterGradientEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: Color.waterDrop.opacity(0.3), radius: 8, y: 4)
                    .opacity(titleOpacity)

                VStack(alignment: .leading, spacing: 6) {
                    Text(timeBasedGreeting)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.onTimeOfDayText)
                    Text("onboarding_greeting_invitation")
                        .font(.body)
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(textOpacity)

                continueButton
                    .opacity(buttonOpacity)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Shared Components

    private func dropVisual(iconSize: CGFloat, glowSize: CGFloat, glowRadius: CGFloat, rippleSize: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        Color.waterDrop.opacity(0.4 - Double(index) * 0.1),
                        lineWidth: 2
                    )
                    .frame(width: rippleSize, height: rippleSize)
                    .scaleEffect(rippleScale + CGFloat(index) * 0.25)
                    .opacity(rippleOpacity)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.waterDrop.opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: glowRadius
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: 25)
                .opacity(glowOpacity)

            Image(systemName: "drop.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.waterGradientStart, Color.waterGradientEnd],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.waterDrop.opacity(0.3), radius: 20, y: 10)
                .scaleEffect(dropScale * dropBounceScale)
                .opacity(dropOpacity)
        }
        .offset(y: floatOffset)
        .onTapGesture {
            triggerDropSplash()
        }
    }

    private var continueButton: some View {
        Button {
            hapticTrigger += 1
            onContinue()
        } label: {
            Text("onboarding_continue")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onTimeOfDayText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .glassEffect(
            .regular.tint(Color.cyan.opacity(0.25)).interactive(),
            in: .capsule
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    private func triggerDropSplash() {
        dropTapHaptic += 1

        if !dropTapped {
            dropTapped = true
            withAnimation(.spring(.smooth(duration: 0.4))) {
                hintOpacity = 0
            }
        }

        withAnimation(.spring(.bouncy(duration: 0.2))) {
            dropBounceScale = 1.15
        }

        rippleOpacity = 0.8
        rippleScale = 0.5
        withAnimation(.spring(.smooth(duration: 0.8))) {
            rippleScale = 1.8
            rippleOpacity = 0
        }

        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(.smooth(duration: 0.3))) {
                dropBounceScale = 1.0
            }
        }
    }
}

// MARK: - Health Step

private struct HealthStepView: View {
    let isLandscape: Bool
    @Bindable var viewModel: OnboardingViewModel
    let onContinue: () -> Void
    let onOpenSettings: () -> Void

    @State private var iconScale: CGFloat = 0.5
    @State private var contentOpacity: Double = 0
    @State private var hapticTrigger = 0
    @State private var heartbeatScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.4
    @State private var heartbeatHapticLub = 0
    @State private var heartbeatHapticDub = 0
    @State private var heartbeatTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: heartbeatHapticLub)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: heartbeatHapticDub)
        .onAppear {
            withAnimation(.spring(.bouncy(duration: 0.6)).delay(0.1)) {
                iconScale = 1.0
            }
            withAnimation(.spring(.smooth).delay(0.3)) {
                contentOpacity = 1.0
            }
            heartbeatTask?.cancel()
            heartbeatTask = Task {
                await Task.sleepIgnoringCancellation(milliseconds: 800)
                guard !Task.isCancelled else { return }
                await startHeartbeatLoop()
            }
        }
        .onDisappear {
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }

    // MARK: Portrait

    private var portraitBody: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    heartVisual(iconSize: 90, glowSize: 160, glowRadius: 80)

                    VStack(spacing: 12) {
                        Text("onboarding_health_title")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.onTimeOfDayText)

                        Text("onboarding_health_body")
                            .font(.body)
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(contentOpacity)

                    statusAndActions
                        .opacity(contentOpacity)
                        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Landscape

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            heartVisual(iconSize: 80, glowSize: 130, glowRadius: 65)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding_health_title")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.onTimeOfDayText)

                    Text("onboarding_health_body")
                        .font(.body)
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }
                .opacity(contentOpacity)

                statusAndActions
                    .opacity(contentOpacity)
                    .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Shared Components

    private func heartVisual(iconSize: CGFloat, glowSize: CGFloat, glowRadius: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.pink.opacity(glowOpacity), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: glowRadius
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: 25)

            Image(systemName: "heart.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink, Color.red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.pink.opacity(0.4), radius: 15, y: 8)
                .scaleEffect(heartbeatScale)
        }
        .scaleEffect(iconScale)
    }

    private var statusAndActions: some View {
        VStack(spacing: 16) {
            if viewModel.healthStatus == .authorized {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.statusSuccess)
                    Text("onboarding_health_connected")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDayText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .glassEffect(.regular, in: .capsule)

            } else if viewModel.healthStatus == .denied {
                Text("permissions_health_denied")
                    .font(.footnote)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    .multilineTextAlignment(isLandscape ? .leading : .center)

                Button {
                    hapticTrigger += 1
                    onOpenSettings()
                } label: {
                    Text("permissions_open_settings")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDayText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: .capsule)

            } else {
                Button {
                    hapticTrigger += 1
                    Task {
                        await viewModel.requestHealthAccess()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.pink)
                        ZStack {
                            Text("onboarding_health_button")
                                .opacity(viewModel.isRequestingHealthAccess ? 0 : 1)
                            if viewModel.isRequestingHealthAccess {
                                ProgressView()
                                    .tint(Color.onTimeOfDayText)
                            }
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .opacity(viewModel.isRequestingHealthAccess ? 0.6 : 1)
                .disabled(viewModel.isRequestingHealthAccess)
            }

            if viewModel.healthStatus != .notDetermined {
                OnboardingPrimaryButton(title: "onboarding_continue") {
                    hapticTrigger += 1
                    onContinue()
                }
            }
        }
    }

    private func startHeartbeatLoop() async {
        while !Task.isCancelled {
            heartbeatHapticLub += 1
            withAnimation(.spring(.bouncy(duration: 0.15))) {
                heartbeatScale = 1.12
                glowOpacity = 0.6
            }

            await Task.sleepIgnoringCancellation(milliseconds: 150)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(.smooth(duration: 0.15))) {
                heartbeatScale = 1.0
                glowOpacity = 0.4
            }

            await Task.sleepIgnoringCancellation(milliseconds: 120)
            guard !Task.isCancelled else { return }
            heartbeatHapticDub += 1
            withAnimation(.spring(.bouncy(duration: 0.15))) {
                heartbeatScale = 1.08
                glowOpacity = 0.55
            }

            await Task.sleepIgnoringCancellation(milliseconds: 150)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(.smooth(duration: 0.2))) {
                heartbeatScale = 1.0
                glowOpacity = 0.4
            }

            await Task.sleepIgnoringCancellation(milliseconds: 600)
            guard !Task.isCancelled else { return }
        }
    }
}

// MARK: - Notifications Step

private struct NotificationsStepView: View {
    let isLandscape: Bool
    @Bindable var viewModel: OnboardingViewModel
    let onContinue: () -> Void
    let onOpenSettings: () -> Void

    @State private var iconScale: CGFloat = 0.5
    @State private var contentOpacity: Double = 0
    @State private var bellRotation: Double = 0
    @State private var glowOpacity: Double = 0.4
    @State private var hapticTrigger = 0
    @State private var bellDingHaptic = 0
    @State private var bellTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: bellDingHaptic)
        .onAppear {
            withAnimation(.spring(.bouncy(duration: 0.6)).delay(0.1)) {
                iconScale = 1.0
            }
            withAnimation(.spring(.smooth).delay(0.3)) {
                contentOpacity = 1.0
            }
            bellTask?.cancel()
            bellTask = Task {
                await Task.sleepIgnoringCancellation(milliseconds: 500)
                guard !Task.isCancelled else { return }
                bellDingHaptic += 1
                withAnimation(.spring(.bouncy(duration: 0.3))) {
                    bellRotation = 15
                    glowOpacity = 0.6
                }
                await Task.sleepIgnoringCancellation(milliseconds: 150)
                guard !Task.isCancelled else { return }
                bellDingHaptic += 1
                withAnimation(.spring(.bouncy(duration: 0.3))) {
                    bellRotation = -10
                }
                await Task.sleepIgnoringCancellation(milliseconds: 150)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(.bouncy(duration: 0.3))) {
                    bellRotation = 0
                }
                await Task.sleepIgnoringCancellation(milliseconds: 200)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(.smooth(duration: 2.0)).repeatForever(autoreverses: true)) {
                    glowOpacity = 0.55
                }
            }
        }
        .onDisappear {
            bellTask?.cancel()
            bellTask = nil
        }
    }

    // MARK: Portrait

    private var portraitBody: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    bellVisual(iconSize: 90, glowSize: 160, glowRadius: 80)

                    VStack(spacing: 12) {
                        Text("onboarding_notifications_title")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.onTimeOfDayText)

                        Text("onboarding_notifications_body")
                            .font(.body)
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(contentOpacity)

                    actionsContent
                        .opacity(contentOpacity)
                        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Landscape

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            bellVisual(iconSize: 80, glowSize: 130, glowRadius: 65)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding_notifications_title")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.onTimeOfDayText)

                    Text("onboarding_notifications_body")
                        .font(.body)
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }
                .opacity(contentOpacity)

                actionsContent
                    .opacity(contentOpacity)
                    .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Shared Components

    private func bellVisual(iconSize: CGFloat, glowSize: CGFloat, glowRadius: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(glowOpacity), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: glowRadius
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: 25)

            Image(systemName: "bell.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.orange.opacity(0.4), radius: 15, y: 8)
                .rotationEffect(.degrees(bellRotation), anchor: .top)
        }
        .scaleEffect(iconScale)
    }

    private var actionsContent: some View {
        VStack(spacing: 16) {
            Toggle(isOn: $viewModel.notificationsEnabled) {
                Text("settings_notifications_toggle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.onTimeOfDayText)
            }
            .tint(Color.cyan)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if viewModel.notificationsStatus == .denied {
                Text("permissions_notifications_denied")
                    .font(.footnote)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    .multilineTextAlignment(isLandscape ? .leading : .center)

                Button {
                    hapticTrigger += 1
                    onOpenSettings()
                } label: {
                    Text("permissions_open_settings")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.onTimeOfDayText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            OnboardingPrimaryButton(title: "onboarding_continue") {
                hapticTrigger += 1
                onContinue()
            }
        }
    }
}

// MARK: - Goal Setup Step

private struct GoalSetupStepView: View {
    let isLandscape: Bool
    @Bindable var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    @State private var selectedGoalMl: Int = AppConstants.defaultDailyGoalMl
    @State private var iconScale: CGFloat = 0.5
    @State private var contentOpacity: Double = 0
    @State private var glowPulse: Double = 0.4
    @State private var hapticTrigger = 0

    private let goalOptions = [1000, 1500, 2000, 2500, 3000, 3500, 4000, 5000]

    private var formattedGoal: String {
        VolumeFormatters.string(fromMl: selectedGoalMl, unitStyle: .medium)
    }

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .onAppear {
            withAnimation(.spring(.bouncy(duration: 0.6)).delay(0.1)) {
                iconScale = 1.0
            }
            withAnimation(.spring(.smooth).delay(0.3)) {
                contentOpacity = 1.0
            }
            withAnimation(.spring(.smooth(duration: 2.0)).repeatForever(autoreverses: true).delay(0.8)) {
                glowPulse = 0.55
            }
        }
    }

    // MARK: Portrait

    private var portraitBody: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    bottleVisual(iconSize: 80, glowSize: 160, glowRadius: 80)

                    VStack(spacing: 12) {
                        Text("onboarding_goal_title")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.onTimeOfDayText)

                        Text("onboarding_goal_body")
                            .font(.body)
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(contentOpacity)

                    goalDisplay(font: .system(.largeTitle, design: .rounded).weight(.bold))

                    goalGrid
                        .opacity(contentOpacity)

                    OnboardingPrimaryButton(title: "onboarding_continue") {
                        hapticTrigger += 1
                        viewModel.setDailyGoal(selectedGoalMl)
                        onContinue()
                    }
                    .opacity(contentOpacity)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Landscape

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            // LEFT: Bottle icon + goal display
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                bottleVisual(iconSize: 70, glowSize: 130, glowRadius: 65)

                goalDisplay(font: .system(.title, design: .rounded).weight(.bold))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // RIGHT: Title, body, grid, continue
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("onboarding_goal_title")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.onTimeOfDayText)

                        Text("onboarding_goal_body")
                            .font(.body)
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                    }
                    .opacity(contentOpacity)

                    goalGrid
                        .opacity(contentOpacity)

                    OnboardingPrimaryButton(title: "onboarding_continue") {
                        hapticTrigger += 1
                        viewModel.setDailyGoal(selectedGoalMl)
                        onContinue()
                    }
                    .opacity(contentOpacity)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Shared Components

    private func bottleVisual(iconSize: CGFloat, glowSize: CGFloat, glowRadius: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.cyan.opacity(glowPulse), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: glowRadius
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: 25)

            Image(systemName: "waterbottle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.waterGradientStart, Color.waterGradientEnd],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.cyan.opacity(0.4), radius: 15, y: 8)
        }
        .scaleEffect(iconScale)
    }

    private func goalDisplay(font: Font) -> some View {
        Text(formattedGoal)
            .font(font)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .foregroundStyle(Color.onTimeOfDayText)
            .contentTransition(.numericText())
            .animation(.spring(.bouncy), value: selectedGoalMl)
            .opacity(contentOpacity)
    }

    private var goalGrid: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(goalOptions.prefix(4), id: \.self) { goal in
                        GoalOptionButton(
                            goalMl: goal,
                            isSelected: selectedGoalMl == goal
                        ) {
                            hapticTrigger += 1
                            withAnimation(.spring(.bouncy)) {
                                selectedGoalMl = goal
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    ForEach(goalOptions.suffix(4), id: \.self) { goal in
                        GoalOptionButton(
                            goalMl: goal,
                            isSelected: selectedGoalMl == goal
                        ) {
                            hapticTrigger += 1
                            withAnimation(.spring(.bouncy)) {
                                selectedGoalMl = goal
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct GoalOptionButton: View {
    let goalMl: Int
    let isSelected: Bool
    let action: () -> Void

    private var formattedGoal: String {
        VolumeFormatters.string(fromMl: goalMl, unitStyle: .short)
    }

    var body: some View {
        Button(action: action) {
            Text(formattedGoal)
                .font(.subheadline.weight(isSelected ? .bold : .medium))
                .foregroundStyle(Color.onTimeOfDayText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .glassEffect(
            isSelected
                ? .regular.tint(Color.cyan.opacity(0.3)).interactive()
                : .regular.interactive(),
            in: .capsule
        )
    }
}

// MARK: - Widget Preview Step

private struct WidgetPreviewStepView: View {
    let isLandscape: Bool
    let goalMl: Int
    let onContinue: () -> Void

    @State private var previewScale: CGFloat = 0.8
    @State private var previewOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var hapticTrigger = 0

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .onAppear {
            withAnimation(.spring(.bouncy(duration: 0.6)).delay(0.1)) {
                previewScale = 1.0
                previewOpacity = 1.0
            }
            withAnimation(.spring(.smooth).delay(0.3)) {
                contentOpacity = 1.0
            }
        }
    }

    // MARK: Portrait

    private var portraitBody: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Text("onboarding_widget_title")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.onTimeOfDayText)

                        Text("onboarding_widget_body")
                            .font(.body)
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(contentOpacity)

                    WidgetPreviewCard(goalMl: goalMl, cardSize: 170)
                        .scaleEffect(previewScale)
                        .opacity(previewOpacity)

                    OnboardingPrimaryButton(title: "onboarding_continue") {
                        hapticTrigger += 1
                        onContinue()
                    }
                    .opacity(contentOpacity)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Landscape

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            WidgetPreviewCard(goalMl: goalMl, cardSize: 155)
                .scaleEffect(previewScale)
                .opacity(previewOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding_widget_title")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.onTimeOfDayText)

                    Text("onboarding_widget_body")
                        .font(.body)
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }
                .opacity(contentOpacity)

                OnboardingPrimaryButton(title: "onboarding_continue") {
                    hapticTrigger += 1
                    onContinue()
                }
                .opacity(contentOpacity)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WidgetPreviewCard: View {
    let goalMl: Int
    let cardSize: CGFloat

    private var currentFormatted: String {
        VolumeFormatters.string(fromMl: 0, unitStyle: .short)
    }

    private var goalFormatted: String {
        VolumeFormatters.string(fromMl: goalMl, unitStyle: .short)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(Color.waterGradientEnd)
                Text("GlassWater")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)
            }

            Text(Localized.string("home_progress_value %@ %@", currentFormatted, goalFormatted))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.onTimeOfDayText)

            Capsule()
                .fill(Color.onTimeOfDayCardBackground)
                .frame(height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("widget_remaining")
                    .font(.caption2)
                    .foregroundStyle(Color.onTimeOfDaySecondaryText)

                Text(goalFormatted)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.onTimeOfDayText)
            }
        }
        .padding(16)
        .frame(width: cardSize, height: cardSize)
        .background(Color.onTimeOfDayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(
            .clear.tint(Color.cyan.opacity(0.1)),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
    }
}

// MARK: - Completion Step

private struct CompletionStepView: View {
    let isLandscape: Bool
    @Binding var waterProgress: Double
    @Binding var waterRiseHaptic: Int
    let onComplete: () -> Void

    @State private var checkScale: CGFloat = 0.3
    @State private var checkOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var confettiVisible = false
    @State private var hapticTrigger = 0
    @State private var successTrigger = 0
    @State private var isTransitioning = false
    @State private var waterMidHaptic = 0
    @State private var waterCompleteHaptic = 0
    @State private var transitionTask: Task<Void, Never>?
    @State private var confettiTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .sensoryFeedback(.success, trigger: successTrigger)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: waterMidHaptic)
        .sensoryFeedback(.success, trigger: waterCompleteHaptic)
        .onAppear {
            withAnimation(.spring(.bouncy(duration: 0.5))) {
                checkScale = 1.0
                checkOpacity = 1.0
            }
            confettiTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                confettiVisible = true
                successTrigger += 1
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                ringOpacity = 0.6
                withAnimation(.spring(.smooth(duration: 0.8))) {
                    ringScale = 1.5
                    ringOpacity = 0
                }
            }
            withAnimation(.spring(.smooth).delay(0.4)) {
                textOpacity = 1.0
            }
            withAnimation(.spring(.smooth).delay(0.6)) {
                buttonOpacity = 1.0
            }
        }
        .onDisappear {
            transitionTask?.cancel()
            confettiTask?.cancel()
        }
    }

    // MARK: Portrait

    private var portraitBody: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    checkVisual(checkSize: 50, circleSize: 120, glowSize: 160, glowRadius: 80, pulseSize: 140)
                        .frame(height: 160)

                    VStack(spacing: 12) {
                        Text("onboarding_complete_title")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Color.onTimeOfDayText)

                        Text("onboarding_complete_subtitle")
                            .font(.body)
                            .foregroundStyle(Color.onTimeOfDaySecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(textOpacity)

                    getStartedButton
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Landscape

    private var landscapeBody: some View {
        HStack(spacing: 0) {
            checkVisual(checkSize: 44, circleSize: 100, glowSize: 130, glowRadius: 65, pulseSize: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("onboarding_complete_title")
                        .font(.title.weight(.bold))
                        .foregroundStyle(Color.onTimeOfDayText)

                    Text("onboarding_complete_subtitle")
                        .font(.body)
                        .foregroundStyle(Color.onTimeOfDaySecondaryText)
                }
                .opacity(textOpacity)

                getStartedButton

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Shared Components

    private func checkVisual(checkSize: CGFloat, circleSize: CGFloat, glowSize: CGFloat, glowRadius: CGFloat, pulseSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.statusSuccess.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: glowRadius
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: 25)
                .opacity(checkOpacity)

            Circle()
                .stroke(Color.statusSuccess.opacity(0.6), lineWidth: 3)
                .frame(width: pulseSize, height: pulseSize)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            Image(systemName: "checkmark")
                .font(.system(size: checkSize, weight: .bold))
                .foregroundStyle(Color.statusSuccess)
                .frame(width: circleSize, height: circleSize)
                .glassEffect(
                    .regular.tint(Color.statusSuccess.opacity(0.15)),
                    in: .circle
                )
                .scaleEffect(checkScale)
                .opacity(checkOpacity)

            if confettiVisible {
                OnboardingConfettiView()
            }
        }
    }

    private var getStartedButton: some View {
        OnboardingPrimaryButton(title: "onboarding_get_started") {
            startWaterTransition()
        }
        .opacity(buttonOpacity)
        .disabled(isTransitioning)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    private func startWaterTransition() {
        isTransitioning = true
        hapticTrigger += 1
        waterRiseHaptic += 1

        withAnimation(.spring(.smooth(duration: 1.8))) {
            waterProgress = 1.0
        }

        transitionTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            waterMidHaptic += 1
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            waterCompleteHaptic += 1
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            onComplete()
        }
    }
}

// MARK: - Confetti

private struct OnboardingConfettiView: View {
    @State private var drops: [ConfettiDrop] = []

    var body: some View {
        ZStack {
            ForEach(drops) { drop in
                Image(systemName: "drop.fill")
                    .font(.system(size: drop.size))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.waterGradientStart.opacity(0.8), Color.waterGradientEnd.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(x: drop.x, y: drop.y)
                    .opacity(drop.opacity)
            }
        }
        .onAppear {
            createDrops()
            animateDrops()
        }
    }

    private func createDrops() {
        drops = (0..<16).map { _ in
            ConfettiDrop(
                x: CGFloat.random(in: -80...80),
                y: 0,
                size: CGFloat.random(in: 10...20),
                opacity: 1.0,
                targetX: CGFloat.random(in: -120...120),
                targetY: CGFloat.random(in: -140 ... -60),
                duration: Double.random(in: 0.6...1.2)
            )
        }
    }

    private func animateDrops() {
        for i in drops.indices {
            let drop = drops[i]
            withAnimation(.spring(.smooth(duration: drop.duration))) {
                drops[i].x = drop.targetX
                drops[i].y = drop.targetY
                drops[i].opacity = 0
            }
        }
    }
}

private struct ConfettiDrop: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var targetX: CGFloat
    var targetY: CGFloat
    var duration: Double
}

// MARK: - Primary Button

private struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.onTimeOfDayText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .glassEffect(
            .regular.tint(Color.cyan.opacity(0.25)).interactive(),
            in: .capsule
        )
    }
}
