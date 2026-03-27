//
//  DuckRewardOverlay.swift
//  GlassWater
//

import SwiftUI

struct DuckRewardOverlay: View {
    let duckCount: Int
    let isFirstTime: Bool
    let duckImageName: String
    let duckName: String
    let onDismiss: () -> Void
    let onRename: (String) -> Void

    @State private var isDismissing = false
    @State private var showBackground = false
    @State private var showDuck = false
    @State private var showText = false
    @State private var showBadge = false
    @State private var floatPhase = false
    @State private var glowPulse = false
    @State private var rippleScale: CGFloat = 0.3
    @State private var rippleOpacity: Double = 0.8
    @State private var ripple2Scale: CGFloat = 0.3
    @State private var ripple2Opacity: Double = 0.6
    @State private var duckOffset: CGFloat = 120
    @State private var duckRotation: Double = 0
    @State private var splashParticles: [SplashParticle] = []
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var floatBobTask: Task<Void, Never>?
    @State private var isRenaming = false
    @State private var editableName: String = ""
    @FocusState private var nameFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var glassTextPrimary: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var glassTextSecondary: Color {
        colorScheme == .dark ? .white.opacity(0.7) : .secondary
    }

    private var glassTextTertiary: Color {
        colorScheme == .dark ? .white.opacity(0.4) : .secondary.opacity(0.6)
    }

    private var autoDismissDelay: Double {
        isFirstTime
            ? AppConstants.duckRewardFirstDismissSeconds
            : AppConstants.duckRewardDismissSeconds
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black
                .opacity(showBackground ? 0.6 : 0)
                .ignoresSafeArea()

            // Card with content
            VStack(spacing: 16) {
                // Glow + Ripples + Duck
                ZStack {
                    // Glow behind duck
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.cyan.opacity(0.35), .cyan.opacity(0.1), .clear],
                                center: .center,
                                startRadius: 15,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .blur(radius: 25)
                        .opacity(showDuck ? (glowPulse ? 0.6 : 0.4) : 0)

                    // Ripple 1
                    Ellipse()
                        .stroke(Color.white.opacity(rippleOpacity * 0.3), lineWidth: 1.5)
                        .frame(width: 180 * rippleScale, height: 38 * rippleScale)

                    // Ripple 2
                    Ellipse()
                        .stroke(Color.cyan.opacity(ripple2Opacity * 0.25), lineWidth: 1)
                        .frame(width: 220 * ripple2Scale, height: 44 * ripple2Scale)

                    // Splash particles (first time only)
                    ForEach(splashParticles) { particle in
                        Circle()
                            .fill(Color.cyan.opacity(particle.opacity))
                            .frame(width: particle.size, height: particle.size)
                            .offset(x: particle.x, y: particle.y)
                    }

                    // Duck image — prominent, with float bob
                    Image(duckImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: isFirstTime ? 120 : 100)
                        .offset(y: floatPhase ? -4 : 4)
                        .offset(y: showDuck ? 0 : duckOffset)
                        .rotationEffect(.degrees(showDuck ? 0 : duckRotation))
                        .scaleEffect(showDuck ? 1.0 : 0.6)
                        .opacity(showDuck ? 1 : 0)
                }
                .frame(height: isFirstTime ? 140 : 120)

                // Text content
                VStack(spacing: 6) {
                    Text(Localized.string("duck_reward_meet %@", duckName))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(glassTextPrimary)

                    Text(isFirstTime
                        ? String(localized: "duck_reward_subtitle_first")
                        : String(localized: "duck_reward_subtitle"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(glassTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 12)

                // Name badge with rename
                nameBadge
                    .opacity(showBadge ? 1 : 0)
                    .scaleEffect(showBadge ? 1.0 : 0.8)

                // Settings hint
                if isFirstTime {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.caption2)
                        Text("duck_reward_settings_hint")
                            .font(.caption2)
                    }
                    .foregroundStyle(glassTextTertiary)
                    .opacity(showBadge ? 1 : 0)
                    .padding(.top, 2)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 28)
            .padding(.horizontal, 32)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            .padding(.horizontal, 40)
            .opacity(showBackground ? 1 : 0)
            .scaleEffect(showBackground ? 1.0 : 0.9)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isRenaming {
                commitRename()
            } else {
                dismissWithAnimation()
            }
        }
        .sensoryFeedback(.success, trigger: showDuck) { _, newValue in
            newValue == true
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text(Localized.string("duck_reward_meet %@", duckName)))
        .onAppear {
            editableName = duckName

            if reduceMotion {
                showBackground = true
                showDuck = true
                showText = true
                showBadge = true
            } else {
                animateEntrance()
            }

            // Auto-dismiss after delay
            autoDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(autoDismissDelay))
                guard !Task.isCancelled else { return }
                dismissWithAnimation()
            }
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
            floatBobTask?.cancel()
            floatBobTask = nil
        }
    }

    // MARK: - Name Badge

    @ViewBuilder
    private var nameBadge: some View {
        if isRenaming {
            HStack(spacing: 6) {
                TextField("", text: $editableName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(glassTextPrimary)
                    .multilineTextAlignment(.center)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { commitRename() }
                    .frame(maxWidth: 120)
                    .onChange(of: editableName) { _, newValue in
                        if newValue.count > 10 {
                            editableName = String(newValue.prefix(10))
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule().fill(glassTextPrimary.opacity(0.1))
                    Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 1)
                }
            )
        } else {
            Button {
                startRenaming()
            } label: {
                HStack(spacing: 6) {
                    Text(duckName)
                        .font(.callout.weight(.semibold))

                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(glassTextTertiary)

                    Text("·")
                        .foregroundStyle(glassTextTertiary)

                    Text(Localized.string("duck_reward_count %d", duckCount))
                        .font(.caption)
                        .foregroundStyle(glassTextSecondary)
                }
                .foregroundStyle(glassTextPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        Capsule().fill(glassTextPrimary.opacity(0.08))
                        Capsule().stroke(glassTextPrimary.opacity(0.15), lineWidth: 0.5)
                    }
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Rename

    private func startRenaming() {
        editableName = duckName
        isRenaming = true
        nameFieldFocused = true
        // Pause auto-dismiss while renaming
        autoDismissTask?.cancel()
    }

    private func commitRename() {
        nameFieldFocused = false
        isRenaming = false

        let trimmed = editableName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? duckName : String(trimmed.prefix(10))
        if finalName != duckName {
            onRename(finalName)
        }

        // Resume auto-dismiss
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            dismissWithAnimation()
        }
    }

    // MARK: - Entrance Animation

    private func animateEntrance() {
        withAnimation(.spring(.smooth(duration: 0.4))) {
            showBackground = true
        }

        if isFirstTime {
            duckOffset = 120
            duckRotation = -8

            withAnimation(.spring(.bouncy(duration: 0.7, extraBounce: 0.15)).delay(0.2)) {
                showDuck = true
                duckOffset = 0
                duckRotation = 0
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                triggerSplashParticles()
            }
        } else {
            duckOffset = 60
            withAnimation(.spring(.bouncy(duration: 0.5)).delay(0.15)) {
                showDuck = true
                duckOffset = 0
            }
        }

        // Ripple expansion
        withAnimation(.spring(.smooth(duration: 1.0)).delay(0.3)) {
            rippleScale = 1.0
            rippleOpacity = 0
        }
        withAnimation(.spring(.smooth(duration: 1.2)).delay(0.45)) {
            ripple2Scale = 1.0
            ripple2Opacity = 0
        }

        // Text appears
        withAnimation(.spring(.smooth(duration: 0.4)).delay(0.5)) {
            showText = true
        }

        // Badge appears
        withAnimation(.spring(.bouncy(duration: 0.35)).delay(0.7)) {
            showBadge = true
        }

        // Start float bob + glow pulse after entrance spring settles
        floatBobTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(.smooth(duration: 1.5)).repeatForever(autoreverses: true)) {
                floatPhase = true
            }
            withAnimation(.spring(.smooth(duration: 2.0)).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }

    // MARK: - Splash Particles

    private func triggerSplashParticles() {
        let particleCount = 8
        for i in 0..<particleCount {
            let angle = Double(i) / Double(particleCount) * .pi * 2
            let distance: CGFloat = CGFloat.random(in: 30...60)
            let particle = SplashParticle(
                id: i,
                x: 0, y: 0,
                targetX: cos(angle) * distance,
                targetY: sin(angle) * distance * 0.4 - 10,
                size: CGFloat.random(in: 3...6),
                opacity: Double.random(in: 0.4...0.8)
            )
            splashParticles.append(particle)
        }

        withAnimation(.spring(.smooth(duration: 0.5))) {
            for i in splashParticles.indices {
                splashParticles[i].x = splashParticles[i].targetX
                splashParticles[i].y = splashParticles[i].targetY
            }
        }

        withAnimation(.spring(.smooth(duration: 0.3)).delay(0.3)) {
            for i in splashParticles.indices {
                splashParticles[i].opacity = 0
            }
        }

        // Clean up after fade completes
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            splashParticles.removeAll()
        }
    }

    // MARK: - Dismiss

    private func dismissWithAnimation() {
        guard !isDismissing else { return }
        isDismissing = true
        if isRenaming { commitRename() }
        autoDismissTask?.cancel()
        autoDismissTask = nil
        floatBobTask?.cancel()
        floatBobTask = nil

        // Staggered reverse: badge → text → duck → background
        withAnimation(.spring(.smooth(duration: 0.25))) {
            showBadge = false
        }
        withAnimation(.spring(.smooth(duration: 0.25)).delay(0.08)) {
            showText = false
        }
        withAnimation(.spring(.smooth(duration: 0.3)).delay(0.15)) {
            showDuck = false
        }
        withAnimation(.spring(.smooth(duration: 0.35)).delay(0.2)) {
            showBackground = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.55))
            onDismiss()
        }
    }
}

// MARK: - Splash Particle Model

private struct SplashParticle: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var targetX: CGFloat
    var targetY: CGFloat
    var size: CGFloat
    var opacity: Double
}
