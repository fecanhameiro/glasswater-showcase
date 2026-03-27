//
//  WatchCelebrationOverlayView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchCelebrationOverlayView: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Central emoji
    @State private var emojiScale: CGFloat = 0.3
    @State private var emojiOpacity: Double = 0.0
    @State private var emojiRotation: Double = -15

    // Ring pulse
    @State private var pulseScale: CGFloat = 0.8
    @State private var pulseOpacity: Double = 0.0

    // Second pulse (staggered)
    @State private var pulse2Scale: CGFloat = 0.8
    @State private var pulse2Opacity: Double = 0.0

    // Sparkles
    @State private var sparkles: [WatchSparkle] = []
    @State private var sparklesVisible = false

    // Confetti drops
    @State private var drops: [WatchConfettiDrop] = []

    // Glow
    @State private var glowOpacity: Double = 0.0

    var body: some View {
        if isActive {
            ZStack {
                // Background glow burst
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.green.opacity(0.3),
                                Color.cyan.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .opacity(glowOpacity)

                // First pulse ring
                Circle()
                    .stroke(Color.green.opacity(0.4), lineWidth: 3)
                    .frame(width: 70, height: 70)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)

                // Second pulse ring (staggered)
                Circle()
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .scaleEffect(pulse2Scale)
                    .opacity(pulse2Opacity)

                // Confetti drops bursting outward
                ForEach(drops) { drop in
                    Image(systemName: "drop.fill")
                        .font(.system(size: drop.size))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    drop.isGreen ? Color.green.opacity(0.8) : Color.cyan.opacity(0.8),
                                    drop.isGreen ? Color.mint.opacity(0.5) : Color.blue.opacity(0.5)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(drop.rotation))
                        .offset(x: drop.x, y: drop.y)
                        .opacity(drop.opacity)
                }

                // Sparkles around the ring
                ForEach(sparkles) { sparkle in
                    Image(systemName: "sparkle")
                        .font(.system(size: sparkle.size, weight: .semibold))
                        .foregroundStyle(sparkle.isGreen ? Color.green : Color.cyan)
                        .offset(x: sparkle.x, y: sparkle.y)
                        .opacity(sparkle.opacity)
                        .scaleEffect(sparkle.scale)
                }

                // Central celebration emoji
                Text("\u{1F389}")
                    .font(.system(size: 32))
                    .scaleEffect(emojiScale)
                    .opacity(emojiOpacity)
                    .rotationEffect(.degrees(emojiRotation))
            }
            .onAppear {
                performCelebration()
            }
            .allowsHitTesting(false)
        }
    }

    private func performCelebration() {
        if reduceMotion {
            // Simplified: just show emoji without confetti/sparkles/pulses
            emojiScale = 1.0
            emojiOpacity = 1.0
            emojiRotation = 0
            glowOpacity = 0.6
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                glowOpacity = 0.0
            }
            return
        }

        createDrops()
        createSparkles()

        // 1. Background glow fades in fast
        withAnimation(.spring(.smooth(duration: 0.3))) {
            glowOpacity = 1.0
        }

        // 2. First pulse ring expands
        withAnimation(.spring(.smooth(duration: 0.6))) {
            pulseScale = 1.8
            pulseOpacity = 0.0
        }

        // 3. Emoji bounces in with rotation
        withAnimation(.spring(.bouncy(duration: 0.35, extraBounce: 0.2))) {
            emojiScale = 1.0
            emojiOpacity = 1.0
            emojiRotation = 0
        }

        // 4. Second pulse ring (staggered)
        withAnimation(.spring(.smooth(duration: 0.7)).delay(0.15)) {
            pulse2Scale = 2.0
            pulse2Opacity = 0.0
        }

        // 5. Confetti drops burst outward
        animateDrops()

        // 6. Sparkles appear with stagger
        animateSparkles()

        // 7. Glow fades out slowly
        withAnimation(.spring(.smooth(duration: 1.5)).delay(0.8)) {
            glowOpacity = 0.0
        }

        // 8. Emoji settles with a gentle bounce after everything
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.spring(.bouncy(duration: 0.3))) {
                emojiScale = 1.1
            }
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation(.spring(.smooth(duration: 0.3))) {
                emojiScale = 1.0
            }
        }
    }

    private func createDrops() {
        drops = (0..<10).map { i in
            let angle = (Double(i) / 10.0) * 2 * .pi + Double.random(in: -0.3...0.3)
            let distance = CGFloat.random(in: 40...65)
            return WatchConfettiDrop(
                x: 0,
                y: 0,
                size: CGFloat.random(in: 6...11),
                opacity: 1.0,
                targetX: cos(angle) * distance,
                targetY: sin(angle) * distance,
                rotation: Double.random(in: -45...45),
                isGreen: i % 3 == 0
            )
        }
    }

    private func animateDrops() {
        for i in drops.indices {
            let drop = drops[i]
            let delay = Double(i) * 0.02
            withAnimation(.spring(.smooth(duration: 0.5)).delay(delay)) {
                drops[i].x = drop.targetX
                drops[i].y = drop.targetY
            }
            withAnimation(.spring(.smooth(duration: 0.4)).delay(delay + 0.25)) {
                drops[i].opacity = 0
            }
        }
    }

    private func createSparkles() {
        sparkles = (0..<8).map { i in
            let angle = (Double(i) / 8.0) * 2 * .pi
            let radius: CGFloat = CGFloat.random(in: 35...55)
            return WatchSparkle(
                x: cos(angle) * radius,
                y: sin(angle) * radius,
                size: CGFloat.random(in: 6...10),
                opacity: 0,
                scale: 0.3,
                isGreen: i % 2 == 0
            )
        }
    }

    private func animateSparkles() {
        for i in sparkles.indices {
            let delay = 0.1 + Double(i) * 0.04
            // Appear
            withAnimation(.spring(.bouncy(duration: 0.25)).delay(delay)) {
                sparkles[i].opacity = 0.8
                sparkles[i].scale = 1.0
            }
            // Disappear
            withAnimation(.spring(.smooth(duration: 0.4)).delay(delay + 0.5)) {
                sparkles[i].opacity = 0
                sparkles[i].scale = 0.5
            }
        }
    }
}

// MARK: - Models

struct WatchConfettiDrop: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var targetX: CGFloat
    var targetY: CGFloat
    var rotation: Double
    var isGreen: Bool
}

struct WatchSparkle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var scale: CGFloat
    var isGreen: Bool
}
