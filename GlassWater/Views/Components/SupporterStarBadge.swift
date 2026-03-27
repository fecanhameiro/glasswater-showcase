//
//  SupporterStarBadge.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 19/03/26.
//

import SwiftUI

struct SupporterStarBadge: View {
    @State private var glowPulse: Double = 0.4
    @State private var starScale: CGFloat = 0.0
    @State private var showLabel = false
    @State private var heartScale: CGFloat = 1.0
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                // Glow circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.yellow.opacity(glowPulse),
                                Color.orange.opacity(glowPulse * 0.5),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 20
                        )
                    )
                    .frame(width: 40, height: 40)

                // Star
                Image(systemName: "star.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .orange.opacity(0.5), radius: 6, y: 2)
                    .scaleEffect(starScale)
            }

            if showLabel {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.pink)
                        .scaleEffect(heartScale)

                    Text("settings_tip_jar_supporter")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.onTimeOfDayText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color.onTimeOfDayCardBackground,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(Color.onTimeOfDayCardStroke, lineWidth: 0.5)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.spring(.bouncy(duration: 0.5))) {
                starScale = 1.0
            }
            withAnimation(
                .spring(.smooth(duration: 2.0))
                .repeatForever(autoreverses: true)
                .delay(0.5)
            ) {
                glowPulse = 0.7
            }
        }
        .onDisappear {
            heartbeatTask?.cancel()
            dismissTask?.cancel()
        }
        .onTapGesture {
            if showLabel {
                hideLabel()
            } else {
                showLabelWithHeartbeat()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: showLabel)
    }

    private func showLabelWithHeartbeat() {
        dismissTask?.cancel()
        withAnimation(.spring(.bouncy)) {
            showLabel = true
        }

        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor in
            await Task.sleepIgnoringCancellation(milliseconds: 300)
            guard !Task.isCancelled else { return }
            await heartbeatLoop()
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            hideLabel()
        }
    }

    private func hideLabel() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        heartScale = 1.0
        withAnimation(.spring(.smooth)) {
            showLabel = false
        }
    }

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            withAnimation(.spring(.bouncy(duration: 0.15))) {
                heartScale = 1.3
            }
            await Task.sleepIgnoringCancellation(milliseconds: 150)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(.smooth(duration: 0.15))) {
                heartScale = 1.0
            }
            await Task.sleepIgnoringCancellation(milliseconds: 120)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(.bouncy(duration: 0.15))) {
                heartScale = 1.2
            }
            await Task.sleepIgnoringCancellation(milliseconds: 150)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(.smooth(duration: 0.2))) {
                heartScale = 1.0
            }
            await Task.sleepIgnoringCancellation(milliseconds: 600)
        }
    }
}
