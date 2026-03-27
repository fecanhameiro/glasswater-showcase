//
//  FloatingActivityRingView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 21/01/26.
//

import SwiftUI
struct FloatingActivityRingView: View {
    let progress: Double
    let currentMl: Int
    let goalMl: Int
    let streakCount: Int
    let goalReached: Bool
    let greetingEmoji: String
    let greetingText: String
    let recentlyAdded: Bool
    let hydrationStatus: HydrationStatus
    let justReachedGoal: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animatedProgress: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0
    @State private var hasAppeared = false
    @State private var tapScale: CGFloat = 1.0
    @State private var rippleScale: CGFloat = 0.8
    @State private var rippleOpacity: Double = 0.0
    @State private var valueScale: CGFloat = 1.0
    @State private var celebrationScale: CGFloat = 0.5
    @State private var celebrationOpacity: Double = 0.0
    @State private var confettiVisible: Bool = false
    @State private var containerWidth: CGFloat = 300
    // Responsive ring size: 75% of container width, clamped between 240-320pt
    private var ringSize: CGFloat {
        let calculated = containerWidth * 0.75
        return min(max(calculated, 240), 320)
    }

    private var strokeWidth: CGFloat {
        ringSize * 0.067 // Proportional stroke (~16pt at 240)
    }

    private var fontSize: CGFloat {
        ringSize * 0.15 // Proportional font (~36pt at 240)
    }

    private var currentFormatted: String {
        VolumeFormatters.string(fromMl: currentMl, unitStyle: .medium)
    }

    private var goalFormatted: String {
        VolumeFormatters.string(fromMl: goalMl, unitStyle: .medium)
    }

    @Environment(\.lightenedNightBackground) private var lightenedNight

    private var hasLightBg: Bool {
        lightenedNight || TimeOfDayPeriod.current.hasLightBackground
    }

    private var ringPrimaryTextColor: Color {
        colorScheme == .dark ? .white
            : hasLightBg ? Color(red: 0.08, green: 0.08, blue: 0.12) : .white
    }
    private var ringSecondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.85)
            : hasLightBg ? Color(red: 0.2, green: 0.2, blue: 0.25) : .white.opacity(0.85)
    }
    private var ringTertiaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.6)
            : hasLightBg ? Color(red: 0.35, green: 0.35, blue: 0.4) : .white.opacity(0.6)
    }

    private var totalSize: CGFloat { ringSize + strokeWidth }

    private var ringBackgroundColor: Color {
        if colorScheme == .dark {
            return .white.opacity(0.18)
        }
        return hasLightBg
            ? .black.opacity(0.12)
            : .white.opacity(0.18)
    }

    private var goalTextOpacity: Double {
        colorScheme == .dark ? 0.75 : 0.65
    }

    private var statusText: String? {
        switch hydrationStatus {
        case .onTrack:
            return String(localized: "home_status_on_track")
        case .slightlyBehind:
            return String(localized: "home_status_slightly_behind")
        case .behind:
            return String(localized: "home_status_behind")
        case .goalReached, .outsideWindow:
            return nil
        }
    }

    private var statusColor: Color {
        switch hydrationStatus {
        case .onTrack:
            return Color.statusSuccess
        case .slightlyBehind:
            return Color.statusWarning
        case .behind:
            return Color.statusAlert
        case .goalReached, .outsideWindow:
            return Color.clear
        }
    }

    var body: some View {
        ZStack {
            // Invisible geometry reader to capture container width
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
            }
            .frame(width: 0, height: 0)

            // Background ring
            Circle()
                .stroke(ringBackgroundColor, lineWidth: strokeWidth)
                .frame(width: ringSize, height: ringSize)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [Color.waterGradientStart.opacity(0.8), Color.waterGradientEnd, Color.waterGradientStart.opacity(0.8)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: ringSize, height: ringSize)

            // Pulse overlay (goal reached)
            if goalReached {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 2)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .frame(width: ringSize, height: ringSize)
            }

            // Ripple overlay (water added)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.waterDrop.opacity(0.4), Color.waterDrop.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: ringSize * 0.5
                    )
                )
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
                .frame(width: ringSize, height: ringSize)

            // Confetti overlay (goal celebration)
            if confettiVisible {
                WaterDropConfettiView(ringSize: ringSize)
            }

            // Center content
            VStack(spacing: 4) {
                if justReachedGoal {
                    Text("🎉")
                        .font(.system(size: 44))
                        .scaleEffect(celebrationScale)
                        .opacity(celebrationOpacity)
                        .accessibilityHidden(true)

                    Text("home_goal_reached")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.statusSuccess)
                        .scaleEffect(celebrationScale)
                        .opacity(celebrationOpacity)
                } else {
                    Text(greetingEmoji)
                        .font(.title)
                        .accessibilityHidden(true)

                    Text(greetingText)
                        .font(.body.weight(.medium))
                        .foregroundStyle(ringSecondaryTextColor)
                }

                if let statusText, !justReachedGoal {
                    Text(statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(statusColor)
                        .padding(.top, 2)
                }

                Text(currentFormatted)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(ringPrimaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .scaleEffect(valueScale)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(.bouncy), value: currentMl)

                Text("/ \(goalFormatted)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ringSecondaryTextColor)

                if streakCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text(Localized.string("home_streak_value %d", streakCount))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ringTertiaryTextColor)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(width: totalSize, height: totalSize)
        .glassEffect(.regular.tint(Color.cyan.opacity(0.15)).interactive(), in: .circle)
        .scaleEffect(tapScale)
        .contentShape(Circle())
        .onTapGesture {
            // Visual feedback - scale down then bounce back
            withAnimation(.spring(.snappy)) {
                tapScale = 0.90
            }

            Task {
                try? await Task.sleep(for: .seconds(0.1))
                withAnimation(.spring(.bouncy)) {
                    tapScale = 1.0
                }
                onTap()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: tapScale) { _, newValue in
            newValue < 1.0
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Localized.string(
            "home_progress_accessibility %@ %@",
            currentFormatted,
            goalFormatted
        )))
        .accessibilityValue(Text("\(Int(progress * 100))%"))
        .accessibilityHint(Text("home_ring_accessibility_hint"))
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(.spring(.smooth(duration: 1.2))) {
                animatedProgress = min(progress, 1.0)
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(.smooth(duration: 0.8))) {
                animatedProgress = min(newValue, 1.0)
            }
        }
        .onChange(of: goalReached) { _, newValue in
            guard newValue else { return }
            triggerPulse()
        }
        .onChange(of: recentlyAdded) { _, newValue in
            guard newValue else { return }
            triggerRipple()
            triggerValueBounce()
        }
        .onChange(of: justReachedGoal) { _, newValue in
            guard newValue else {
                confettiVisible = false
                return
            }
            triggerCelebration()
        }
    }

    private func triggerPulse() {
        guard !reduceMotion else { return }
        pulseScale = 1.0
        pulseOpacity = 0.4
        withAnimation(.spring(.smooth(duration: 0.9))) {
            pulseScale = 1.4
            pulseOpacity = 0.0
        }
    }

    private func triggerRipple() {
        guard !reduceMotion else { return }
        rippleScale = 0.3
        rippleOpacity = 0.6
        withAnimation(.spring(.smooth(duration: 0.5))) {
            rippleScale = 1.2
            rippleOpacity = 0.0
        }
    }

    private func triggerValueBounce() {
        guard !reduceMotion else { return }
        withAnimation(.spring(.bouncy(duration: 0.2))) {
            valueScale = 1.15
        }
        Task {
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.spring(.smooth(duration: 0.25))) {
                valueScale = 1.0
            }
        }
    }

    private func triggerCelebration() {
        if reduceMotion {
            celebrationScale = 1.0
            celebrationOpacity = 1.0
            return
        }
        confettiVisible = true
        celebrationScale = 0.5
        celebrationOpacity = 0.0

        withAnimation(.spring(.bouncy(duration: 0.4))) {
            celebrationScale = 1.0
            celebrationOpacity = 1.0
        }
    }
}

// MARK: - Water Drop Confetti

private struct WaterDropConfettiView: View {
    let ringSize: CGFloat

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
        drops = (0..<12).map { i in
            let angle = Double(i) / 12.0 * .pi * 2 + Double.random(in: -0.3...0.3)
            let distance = CGFloat.random(in: ringSize * 0.3...ringSize * 0.6)
            return ConfettiDrop(
                x: 0,
                y: 0,
                size: CGFloat.random(in: 8...16),
                opacity: 1.0,
                targetX: cos(angle) * distance,
                targetY: sin(angle) * distance,
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
