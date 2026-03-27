//
//  WatchProgressRingView.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchProgressRingView: View {
    let progress: Double
    let currentMl: Int
    let goalMl: Int
    let goalReached: Bool
    let recentlyAdded: Bool
    let metrics: WatchLayoutMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animatedProgress: Double = 0
    @State private var rippleScale: CGFloat = 0.8
    @State private var rippleOpacity: Double = 0.0
    @State private var valueScale: CGFloat = 1.0
    @State private var hasAppeared = false

    private var ringAccentColor: Color { goalReached ? .green : .cyan }

    private var currentFormatted: String {
        VolumeFormatters.string(fromMl: currentMl, unitStyle: .short)
    }

    private var goalFormatted: String {
        VolumeFormatters.string(fromMl: goalMl, unitStyle: .short)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Outer glow (overflows visually but doesn't consume layout space)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ringAccentColor.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: metrics.ringGlowStartRadius,
                            endRadius: metrics.ringGlowEndRadius
                        )
                    )
                    .frame(width: metrics.ringGlowSize, height: metrics.ringGlowSize)

                // Background track
                Circle()
                    .stroke(ringAccentColor.opacity(0.15), lineWidth: metrics.ringStroke)
                    .frame(width: metrics.ringDiameter, height: metrics.ringDiameter)

                // Progress arc
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        AngularGradient(
                            colors: goalReached
                                ? [Color.green.opacity(0.6), Color.green, Color.mint, Color.green.opacity(0.6)]
                                : [Color.cyan.opacity(0.6), Color.cyan, Color.blue, Color.cyan.opacity(0.6)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: metrics.ringStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: metrics.ringDiameter, height: metrics.ringDiameter)

                // Ripple overlay
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ringAccentColor.opacity(0.3), ringAccentColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: metrics.ringDiameter * 0.5
                        )
                    )
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)
                    .frame(width: metrics.ringDiameter, height: metrics.ringDiameter)

                // Center content
                VStack(spacing: 1) {
                    Image(systemName: goalReached ? "checkmark.circle.fill" : "drop.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: goalReached
                                    ? [Color.green, Color.mint]
                                    : [Color.cyan, Color.blue],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.watchTextPrimary)
                        .scaleEffect(valueScale)
                }

                // Sparkle decorations when goal reached
                if goalReached {
                    ForEach(0..<4, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 6, weight: .semibold))
                            .foregroundStyle(Color.green.opacity(0.6))
                            .offset(
                                x: CGFloat(cos(Double(i) * .pi / 2)) * (metrics.ringDiameter * 0.55),
                                y: CGFloat(sin(Double(i) * .pi / 2)) * (metrics.ringDiameter * 0.55)
                            )
                    }
                }
            }
            .frame(height: metrics.ringDiameter + metrics.ringStroke)

            // Values below ring
            HStack(spacing: 3) {
                Text(currentFormatted)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.watchTextPrimary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(.bouncy), value: currentMl)

                Text("/")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.watchTextSecondary)

                Text(goalFormatted)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.watchTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Int(progress * 100))%, \(currentFormatted) / \(goalFormatted)"))
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            withAnimation(.spring(.smooth(duration: 0.8))) {
                animatedProgress = min(progress, 1.0)
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(.smooth(duration: 0.25))) {
                animatedProgress = min(newValue, 1.0)
            }
        }
        .onChange(of: recentlyAdded) { _, newValue in
            guard newValue else { return }
            if !reduceMotion {
                triggerRipple()
                triggerValueBounce()
            }
        }
    }

    private func triggerRipple() {
        rippleScale = 0.3
        rippleOpacity = 0.5
        withAnimation(.spring(.smooth(duration: 0.28))) {
            rippleScale = 1.1
            rippleOpacity = 0.0
        }
    }

    private func triggerValueBounce() {
        withAnimation(.spring(.bouncy(duration: 0.15))) {
            valueScale = 1.12
        }
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            withAnimation(.spring(.smooth(duration: 0.15))) {
                valueScale = 1.0
            }
        }
    }
}
