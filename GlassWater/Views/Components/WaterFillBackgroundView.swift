//
//  WaterFillBackgroundView.swift
//  GlassWater
//

import SwiftUI

struct WaterFillBackgroundView: View {
    /// Hydration progress from 0.0 to 1.0
    let progress: Double
    var duckCount: Int = 0
    var attractionX: CGFloat?
    var attractionStartTime: Double?
    var previousAttractionX: CGFloat?
    var tappedDuckIndex: Int?
    var tappedDuckTime: Double?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Animation State

    @State private var animatedProgress: Double = 0
    @State private var hasAnimatedInitialFill = false
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    // MARK: - Configuration

    private enum WaveConfig {
        // Wave timing - calmer for premium feel
        static let wave1Duration: Double = 14
        static let wave2Duration: Double = 17
        static let wave3Duration: Double = 20

        // Wave geometry - refined for premium look
        static let wave1Amplitude: CGFloat = 10
        static let wave2Amplitude: CGFloat = 7
        static let wave3Amplitude: CGFloat = 5

        static let wave1Frequency: Double = 1.1
        static let wave2Frequency: Double = 1.4
        static let wave3Frequency: Double = 0.75

        // Layer offsets (back waves slightly lower)
        static let wave2Offset: CGFloat = 0.018
        static let wave3Offset: CGFloat = 0.028
    }

    private var shouldAnimate: Bool {
        scenePhase == .active && !reduceMotion && !isLowPowerModeEnabled
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            // Calculate wave phases based on time - completely independent of state
            let wavePhase1 = (time / WaveConfig.wave1Duration) * .pi * 2
            let wavePhase2 = (time / WaveConfig.wave2Duration) * .pi * 2
            // Back wave moves in opposite direction for depth effect
            let wavePhase3 = -(time / WaveConfig.wave3Duration) * .pi * 2

            // Waves get calmer as water level increases (more full = more calm)
            let calmFactor = 1.0 - (animatedProgress * 0.3)

            GeometryReader { geometry in
                let palette = waterPalette(for: colorScheme)

                ZStack {
                    // Layer 3: Back wave (most transparent, slowest, opposite direction)
                    WaterWaveShape(
                        phase: wavePhase3,
                        amplitude: WaveConfig.wave3Amplitude * calmFactor,
                        frequency: WaveConfig.wave3Frequency,
                        fillLevel: adjustedFillLevel(animatedProgress, offset: WaveConfig.wave3Offset)
                    )
                    .fill(
                        LinearGradient(
                            colors: [palette.deep, palette.mid],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .opacity(0.4)

                    // Layer 2: Middle wave
                    WaterWaveShape(
                        phase: wavePhase2,
                        amplitude: WaveConfig.wave2Amplitude * calmFactor,
                        frequency: WaveConfig.wave2Frequency,
                        fillLevel: adjustedFillLevel(animatedProgress, offset: WaveConfig.wave2Offset)
                    )
                    .fill(
                        LinearGradient(
                            colors: [palette.mid, palette.surface],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .opacity(0.6)

                    // Layer 1: Front wave (most visible)
                    WaterWaveShape(
                        phase: wavePhase1,
                        amplitude: WaveConfig.wave1Amplitude * calmFactor,
                        frequency: WaveConfig.wave1Frequency,
                        fillLevel: animatedProgress
                    )
                    .fill(
                        LinearGradient(
                            colors: [palette.mid, palette.surface, palette.highlight],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .opacity(0.7)

                    // Surface shimmer: bright line following the front wave crest
                    if animatedProgress > 0.02 {
                        WaterSurfaceLine(
                            phase: wavePhase1,
                            amplitude: WaveConfig.wave1Amplitude * calmFactor,
                            frequency: WaveConfig.wave1Frequency,
                            fillLevel: animatedProgress
                        )
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.4),
                                    .cyan.opacity(0.3),
                                    .white.opacity(0.5),
                                    .cyan.opacity(0.3),
                                    .white.opacity(0.4),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                        .opacity(colorScheme == .dark ? 0.5 : 0.35)
                    }

                    // Bubbles floating up through the water
                    if animatedProgress > 0.10 {
                        bubblesOverlay(time: time, size: geometry.size)
                    }

                    // Sparkles near the surface
                    if animatedProgress > 0.10 {
                        sparklesOverlay(time: time, size: geometry.size)
                    }

                    // Swimming ducks
                    if duckCount > 0 {
                        SwimmingDuckOverlay(
                            time: time,
                            wavePhase: wavePhase1,
                            waveAmplitude: WaveConfig.wave1Amplitude * calmFactor,
                            waveFrequency: WaveConfig.wave1Frequency,
                            fillLevel: animatedProgress,
                            size: geometry.size,
                            duckCount: duckCount,
                            attractionX: attractionX,
                            attractionStartTime: attractionStartTime,
                            previousAttractionX: previousAttractionX,
                            tappedDuckIndex: tappedDuckIndex,
                            tappedDuckTime: tappedDuckTime
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            // Seed animated progress if data is already loaded at render time
            if !hasAnimatedInitialFill && progress > 0 {
                hasAnimatedInitialFill = true
                Task {
                    try? await Task.sleep(for: .seconds(0.1))
                    withAnimation(.spring(.smooth(duration: 1.8))) {
                        animatedProgress = min(max(progress, 0), 1)
                    }
                }
            }
        }
        .onChange(of: progress) { _, newValue in
            let clamped = min(max(newValue, 0), 1)

            // First time data loads: animate from 0 (fill effect)
            if !hasAnimatedInitialFill && clamped > 0 {
                hasAnimatedInitialFill = true
                animatedProgress = 0
                Task {
                    try? await Task.sleep(for: .seconds(0.1))
                    withAnimation(.spring(.smooth(duration: 1.8))) {
                        animatedProgress = clamped
                    }
                }
            } else {
                // Subsequent changes: smooth animation without overshoot
                withAnimation(.spring(.smooth(duration: 1.2))) {
                    animatedProgress = clamped
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func bubblesOverlay(time: Double, size: CGSize) -> some View {
        ForEach(0..<8, id: \.self) { i in
            let seed = Double(i)
            let cycleDuration = 4.0 + seed * 0.9
            let cycleProgress = (time / cycleDuration).truncatingRemainder(dividingBy: 1.0)

            // X position: gentle horizontal drift using sine
            let bubbleX = sin(seed * 1.7 + cycleProgress * 0.4) * 0.35 + 0.5

            // Y position: rises from bottom of water body to surface
            let minFillY: CGFloat = 0.95
            let maxFillY: CGFloat = 0.08
            let waterSurfaceRatio = minFillY - (minFillY - maxFillY) * animatedProgress
            let bubbleBottom = min(0.98, waterSurfaceRatio + 0.15)
            let bubbleY = bubbleBottom - cycleProgress * (bubbleBottom - waterSurfaceRatio)

            // Size: 4-8pt (larger than watch for bigger screen)
            let bubbleSize: CGFloat = CGFloat(4.0 + seed.truncatingRemainder(dividingBy: 4.0))

            // Opacity: fade in at bottom, fade out at surface
            let fadeIn = min(cycleProgress / 0.08, 1.0)
            let fadeOut = min((1.0 - cycleProgress) / 0.12, 1.0)
            let bubbleOpacity = fadeIn * fadeOut * 0.25

            Circle()
                .fill(.white.opacity(bubbleOpacity))
                .frame(width: bubbleSize, height: bubbleSize)
                .position(
                    x: size.width * bubbleX,
                    y: size.height * bubbleY
                )
        }
    }

    // MARK: - Sparkles

    @ViewBuilder
    private func sparklesOverlay(time: Double, size: CGSize) -> some View {
        ForEach(0..<5, id: \.self) { i in
            let seed = Double(i)

            // Sparkles sit near the surface, drifting slowly
            let minFillY: CGFloat = 0.95
            let maxFillY: CGFloat = 0.08
            let waterSurfaceRatio = minFillY - (minFillY - maxFillY) * animatedProgress

            // Position just below the surface with slight vertical drift (golden ratio distribution)
            let sparkleX = ((seed * 0.618033988749895) + 0.12).truncatingRemainder(dividingBy: 1.0)
            let sparkleY = waterSurfaceRatio + 0.02 + sin(time * 0.3 + seed * 2.0) * 0.015

            // Pulsing opacity: twinkle effect
            let twinklePhase = sin(time * (1.5 + seed * 0.4) + seed * 3.0)
            let sparkleOpacity = max(0, twinklePhase) * 0.4

            let sparkleSize: CGFloat = CGFloat(2.5 + seed.truncatingRemainder(dividingBy: 2.0))

            Circle()
                .fill(.white.opacity(sparkleOpacity))
                .frame(width: sparkleSize, height: sparkleSize)
                .position(
                    x: size.width * sparkleX,
                    y: size.height * sparkleY
                )
        }
    }

    // MARK: - Helpers

    private func adjustedFillLevel(_ base: Double, offset: CGFloat) -> Double {
        max(0, base - Double(offset))
    }

    private func waterPalette(for scheme: ColorScheme) -> WaterPalette {
        switch scheme {
        case .dark:
            return WaterPalette(
                deep: Color(red: 0.04, green: 0.08, blue: 0.18),
                mid: Color(red: 0.08, green: 0.14, blue: 0.28),
                surface: Color(red: 0.12, green: 0.22, blue: 0.38),
                highlight: Color(red: 0.18, green: 0.30, blue: 0.48)
            )
        default:
            return WaterPalette(
                deep: Color(red: 0.35, green: 0.60, blue: 0.80),
                mid: Color(red: 0.45, green: 0.70, blue: 0.88),
                surface: Color(red: 0.55, green: 0.78, blue: 0.92),
                highlight: Color(red: 0.70, green: 0.86, blue: 0.96)
            )
        }
    }
}

// MARK: - Color Palette

private struct WaterPalette {
    let deep: Color
    let mid: Color
    let surface: Color
    let highlight: Color
}
