//
//  HydrationAmbientBackgroundView.swift
//  GlassWater
//
//  Created by OpenAI on 20/02/26.
//

import SwiftUI

struct HydrationAmbientBackgroundView: View {
    struct Configuration: Sendable {
        var style: Style = .serene
    }

    enum Style: Sendable {
        case serene
    }

    let progress: Double
    let intakeTrigger: Int
    var configuration = Configuration()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var driftPhase = false
    @State private var morphPhase = false
    @State private var intakePulseOffset: CGFloat = 0
    @State private var intakePulseGlow: Double = 0
    @State private var intakeBrightness: Double = 0
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var shouldAnimate: Bool {
        scenePhase == .active && !reduceMotion && !isLowPowerModeEnabled
    }

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let baseOffset = baseVerticalOffset(in: proxy.size.height, progress: clampedProgress)
            let tones = gradientTones(for: clampedProgress, scheme: colorScheme)
            let glowOpacity = glowOpacity(for: clampedProgress, scheme: colorScheme)

            ZStack {
                LinearGradient(
                    colors: tones.primary,
                    startPoint: driftPhase ? .topLeading : .topTrailing,
                    endPoint: driftPhase ? .bottomTrailing : .bottomLeading
                )

                LinearGradient(
                    colors: tones.secondary,
                    startPoint: morphPhase ? .top : .leading,
                    endPoint: morphPhase ? .bottomTrailing : .bottom
                )
                .blendMode(.softLight)
                .opacity(0.65)

                RadialGradient(
                    colors: [Color.white.opacity(glowOpacity + intakePulseGlow), .clear],
                    center: morphPhase ? .topLeading : .top,
                    startRadius: 40,
                    endRadius: proxy.size.width * 0.9
                )
                .blendMode(.softLight)
                .opacity(0.75)
            }
            .frame(
                width: proxy.size.width * 1.25,
                height: proxy.size.height * 1.25
            )
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .scaleEffect(morphPhase ? 1.10 : 1.04)
            .offset(y: baseOffset + intakePulseOffset)
            .brightness(intakeBrightness)
            .animation(.spring(.smooth(duration: 1.6)), value: clampedProgress)
            .animation(.spring(.smooth(duration: 1.2)), value: intakePulseOffset)
            .animation(.spring(.smooth(duration: 1.2)), value: intakePulseGlow)
            .animation(.spring(.smooth(duration: 1.2)), value: intakeBrightness)
            .transaction { transaction in
                if !shouldAnimate {
                    transaction.animation = nil
                }
            }
            .onAppear {
                updateAnimationState(shouldAnimate: shouldAnimate)
            }
            .onChange(of: shouldAnimate) { _, newValue in
                updateAnimationState(shouldAnimate: newValue)
            }
            .onChange(of: intakeTrigger) { _, _ in
                triggerIntakePulse()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func updateAnimationState(shouldAnimate: Bool) {
        guard shouldAnimate else {
            withAnimation(.none) {
                driftPhase = false
                morphPhase = false
            }
            return
        }

        driftPhase = false
        morphPhase = false

        withAnimation(.spring(.smooth(duration: 22)).repeatForever(autoreverses: true)) {
            driftPhase.toggle()
        }

        withAnimation(.spring(.smooth(duration: 18)).repeatForever(autoreverses: true)) {
            morphPhase.toggle()
        }
    }

    private func triggerIntakePulse() {
        guard shouldAnimate else { return }

        intakePulseOffset = 0
        intakePulseGlow = 0
        intakeBrightness = 0

        withAnimation(.spring(.smooth(duration: 1.0))) {
            intakePulseOffset = -14
            intakePulseGlow = 0.18
            intakeBrightness = 0.03
        }

        Task {
            await Task.sleepIgnoringCancellation(seconds: 1)
            await MainActor.run {
                withAnimation(.spring(.smooth(duration: 1.6))) {
                    intakePulseOffset = 0
                    intakePulseGlow = 0
                    intakeBrightness = 0
                }
            }
        }
    }

    private func baseVerticalOffset(in height: CGFloat, progress: Double) -> CGFloat {
        let start = height * 0.08
        let end = -height * 0.04
        return lerp(start: start, end: end, progress: progress)
    }

    private func glowOpacity(for progress: Double, scheme: ColorScheme) -> Double {
        let base = scheme == .dark ? 0.14 : 0.16
        return base + (0.12 * progress)
    }

    private func gradientTones(for progress: Double, scheme: ColorScheme) -> (primary: [Color], secondary: [Color]) {
        let palette = paletteTones(for: scheme)
        let top = Tone.lerp(from: palette.coolTop, to: palette.warmTop, progress: progress)
        let bottom = Tone.lerp(from: palette.coolBottom, to: palette.warmBottom, progress: progress)
        let accent = Tone.lerp(from: palette.coolAccent, to: palette.warmAccent, progress: progress)

        return (
            primary: [top.color, bottom.color],
            secondary: [accent.color.opacity(0.9), top.color.opacity(0.8), bottom.color.opacity(0.75)]
        )
    }

    private func paletteTones(for scheme: ColorScheme) -> Palette {
        switch scheme {
        case .dark:
            return Palette(
                coolTop: Tone(0.05, 0.09, 0.20),
                coolBottom: Tone(0.07, 0.13, 0.26),
                warmTop: Tone(0.15, 0.19, 0.30),
                warmBottom: Tone(0.19, 0.24, 0.34),
                coolAccent: Tone(0.20, 0.30, 0.42),
                warmAccent: Tone(0.26, 0.32, 0.42)
            )
        default:
            return Palette(
                coolTop: Tone(0.72, 0.86, 0.95),
                coolBottom: Tone(0.72, 0.9, 0.88),
                warmTop: Tone(0.86, 0.9, 0.96),
                warmBottom: Tone(0.9, 0.92, 0.88),
                coolAccent: Tone(0.82, 0.9, 0.96),
                warmAccent: Tone(0.92, 0.9, 0.86)
            )
        }
    }

    private func lerp(start: CGFloat, end: CGFloat, progress: Double) -> CGFloat {
        start + (end - start) * CGFloat(progress)
    }
}

private struct Palette {
    let coolTop: Tone
    let coolBottom: Tone
    let warmTop: Tone
    let warmBottom: Tone
    let coolAccent: Tone
    let warmAccent: Tone
}

private struct Tone {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static func lerp(from start: Tone, to end: Tone, progress: Double) -> Tone {
        Tone(
            start.red + (end.red - start.red) * progress,
            start.green + (end.green - start.green) * progress,
            start.blue + (end.blue - start.blue) * progress
        )
    }
}
