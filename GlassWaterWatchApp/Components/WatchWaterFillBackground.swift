//
//  WatchWaterFillBackground.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

/// Full-screen animated water background for the custom amount sheet.
/// Features: 2 wave layers, bubbles, surface shimmer, color-by-level, slosh support.
struct WatchWaterFillBackground: View {
    /// Fill level from 0.0 to 1.0 (controlled by Digital Crown)
    let progress: Double

    /// Amplitude boost from crown momentum (0 = normal, 1 = max slosh)
    var amplitudeBoost: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Wave Configuration

    private enum WaveConfig {
        static let wave1Duration: Double = 10
        static let wave2Duration: Double = 13

        static let wave1Amplitude: CGFloat = 6
        static let wave2Amplitude: CGFloat = 4

        static let wave1Frequency: Double = 1.2
        static let wave2Frequency: Double = 0.8

        static let wave2Offset: CGFloat = 0.02
    }

    // MARK: - Color-by-Level Palette

    private func waterPalette(for t: Double) -> (deep: Color, mid: Color, surface: Color, highlight: Color) {
        if t < 0.35 {
            // Low: deep, dark blue — "needs hydration"
            return (
                deep: Color(red: 0.0, green: 0.10, blue: 0.26),
                mid: Color(red: 0.0, green: 0.18, blue: 0.38),
                surface: Color(red: 0.0, green: 0.26, blue: 0.50),
                highlight: Color(red: 0.04, green: 0.36, blue: 0.60)
            )
        } else if t < 0.65 {
            // Mid: vibrant cyan
            return (
                deep: Color(red: 0.0, green: 0.12, blue: 0.28),
                mid: Color(red: 0.0, green: 0.25, blue: 0.48),
                surface: Color(red: 0.0, green: 0.38, blue: 0.60),
                highlight: Color(red: 0.10, green: 0.52, blue: 0.72)
            )
        } else {
            // High: bright, luminous cyan — fully hydrated, energized
            return (
                deep: Color(red: 0.0, green: 0.16, blue: 0.32),
                mid: Color(red: 0.0, green: 0.30, blue: 0.52),
                surface: Color(red: 0.02, green: 0.45, blue: 0.68),
                highlight: Color(red: 0.14, green: 0.60, blue: 0.78)
            )
        }
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            // Wave phases
            let wavePhase1 = (time / WaveConfig.wave1Duration) * .pi * 2
            let wavePhase2 = -(time / WaveConfig.wave2Duration) * .pi * 2

            // Calm factor + slosh boost
            let calmFactor = 1.0 - (progress * 0.3)
            let amplitudeMultiplier = calmFactor * (1.0 + Double(amplitudeBoost) * 2.0)

            let palette = waterPalette(for: progress)

            GeometryReader { geo in
                ZStack {
                    // Layer 2: Back wave (more transparent, opposite direction)
                    WatchWaterWaveShape(
                        phase: wavePhase2,
                        amplitude: WaveConfig.wave2Amplitude * amplitudeMultiplier,
                        frequency: WaveConfig.wave2Frequency,
                        fillLevel: max(0, progress - Double(WaveConfig.wave2Offset))
                    )
                    .fill(
                        LinearGradient(
                            colors: [palette.deep, palette.mid],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .opacity(0.7)

                    // Layer 1: Front wave (most visible)
                    WatchWaterWaveShape(
                        phase: wavePhase1,
                        amplitude: WaveConfig.wave1Amplitude * amplitudeMultiplier,
                        frequency: WaveConfig.wave1Frequency,
                        fillLevel: progress
                    )
                    .fill(
                        LinearGradient(
                            colors: [palette.mid, palette.surface, palette.highlight],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .opacity(0.85)

                    // Surface shimmer: bright line following the front wave crest
                    WatchWaterSurfaceLine(
                        phase: wavePhase1,
                        amplitude: WaveConfig.wave1Amplitude * amplitudeMultiplier,
                        frequency: WaveConfig.wave1Frequency,
                        fillLevel: progress
                    )
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.5),
                                .cyan.opacity(0.4),
                                .white.opacity(0.5),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
                    .opacity(0.6)

                    // Bubbles floating up through the water
                    if progress > 0.15 {
                        bubblesOverlay(time: time, size: geo.size)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func bubblesOverlay(time: Double, size: CGSize) -> some View {
        ForEach(0..<6, id: \.self) { i in
            let seed = Double(i)
            let cycleDuration = 3.0 + seed * 0.7
            let cycleProgress = (time / cycleDuration).truncatingRemainder(dividingBy: 1.0)

            // X position: gentle horizontal drift using sine
            let bubbleX = sin(seed * 1.7 + cycleProgress * 0.5) * 0.3 + 0.5

            // Y position: rises from bottom of water to surface
            let minFillY: CGFloat = 0.95
            let maxFillY: CGFloat = 0.08
            let waterSurfaceRatio = minFillY - (minFillY - maxFillY) * progress
            let bubbleBottom: CGFloat = 0.98
            let bubbleY = bubbleBottom - cycleProgress * (bubbleBottom - waterSurfaceRatio)

            // Size: 3-5pt
            let bubbleSize: CGFloat = CGFloat(3.0 + seed.truncatingRemainder(dividingBy: 3.0))

            // Opacity: fade in at bottom, fade out at surface
            let fadeIn = min(cycleProgress / 0.1, 1.0)
            let fadeOut = min((1.0 - cycleProgress) / 0.15, 1.0)
            let bubbleOpacity = fadeIn * fadeOut

            Circle()
                .fill(.white.opacity(0.3 * bubbleOpacity))
                .frame(width: bubbleSize, height: bubbleSize)
                .position(
                    x: size.width * bubbleX,
                    y: size.height * bubbleY
                )
        }
    }
}
