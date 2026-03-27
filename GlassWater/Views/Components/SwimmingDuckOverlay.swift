//
//  SwimmingDuckOverlay.swift
//  GlassWater
//

import SwiftUI

struct DuckPosition {
    let index: Int
    let x: CGFloat
    let y: CGFloat
    let height: CGFloat
}

struct SwimmingDuckOverlay: View {
    let time: Double
    let wavePhase: Double
    let waveAmplitude: CGFloat
    let waveFrequency: Double
    let fillLevel: Double
    let size: CGSize
    let duckCount: Int
    var attractionX: CGFloat?
    var attractionStartTime: Double?
    var previousAttractionX: CGFloat?
    var tappedDuckIndex: Int?
    var tappedDuckTime: Double?

    // centerX ± (swingAmplitude + secondarySwingAmplitude) must stay within [0.10, 0.90]
    static let configurations: [DuckConfiguration] = [
        // 1. Glass — first duck, smallest, slightly behind
        DuckConfiguration(imageName: "duck_glass",   cycleDuration: 45, secondaryCycleDuration: 13, centerX: 0.50, swingAmplitude: 0.14, secondarySwingAmplitude: 0.04, duckHeight: 28, opacity: 0.75, depthOffset: -3),
        // 2. Yellow — second, slightly bigger
        DuckConfiguration(imageName: "duck_yellow",  cycleDuration: 38, secondaryCycleDuration: 11, centerX: 0.33, swingAmplitude: 0.16, secondarySwingAmplitude: 0.05, duckHeight: 33, opacity: 0.80, depthOffset: -1),
        // 3. Green — mid tier, growing presence
        DuckConfiguration(imageName: "duck_green",   cycleDuration: 52, secondaryCycleDuration: 17, centerX: 0.72, swingAmplitude: 0.16, secondarySwingAmplitude: 0.05, duckHeight: 38, opacity: 0.88, depthOffset: 1),
        // 4. Purple — rare, prominent, forward
        DuckConfiguration(imageName: "duck_purple",  cycleDuration: 58, secondaryCycleDuration: 19, centerX: 0.42, swingAmplitude: 0.20, secondarySwingAmplitude: 0.06, duckHeight: 43, opacity: 0.93, depthOffset: 2),
        // 5. Rainbow — ultimate reward, largest, frontmost
        DuckConfiguration(imageName: "duck_rainbow", cycleDuration: 42, secondaryCycleDuration: 14, centerX: 0.58, swingAmplitude: 0.22, secondarySwingAmplitude: 0.06, duckHeight: 50, opacity: 1.0, depthOffset: 3),
    ]

    /// Scale boost when fewer ducks: 1 duck → 1.6x, 2 → 1.35x, 3 → 1.15x, 4 → 1.05x, 5 → 1.0x
    private static let sizeBoost: [CGFloat] = [1.6, 1.35, 1.15, 1.05, 1.0]

    var body: some View {
        let visibleCount = min(duckCount, AppConstants.maxVisibleDucks)
        let boost: CGFloat = visibleCount > 0
            ? Self.sizeBoost[min(visibleCount - 1, Self.sizeBoost.count - 1)]
            : 1.0

        ZStack {
            ForEach(0..<visibleCount, id: \.self) { index in
                let config = Self.configurations[index]
                let adjustedHeight = config.duckHeight * boost
                let adjustedOpacity = min(1.0, config.opacity + (1.0 - config.opacity) * (boost - 1.0))
                SingleDuckView(
                    time: time,
                    wavePhase: wavePhase,
                    waveAmplitude: waveAmplitude,
                    waveFrequency: waveFrequency,
                    fillLevel: fillLevel,
                    size: size,
                    imageName: config.imageName,
                    cycleDuration: config.cycleDuration,
                    secondaryCycleDuration: config.secondaryCycleDuration,
                    centerX: config.centerX,
                    swingAmplitude: config.swingAmplitude,
                    secondarySwingAmplitude: config.secondarySwingAmplitude,
                    duckHeight: adjustedHeight,
                    duckOpacity: adjustedOpacity,
                    depthOffset: config.depthOffset,
                    attractionX: attractionX,
                    attractionStartTime: attractionStartTime,
                    previousAttractionX: previousAttractionX,
                    tappedTime: tappedDuckIndex == index ? tappedDuckTime : nil
                )
            }
        }
    }

    /// Compute current duck positions on-demand (for hit detection)
    static func currentPositions(
        time: Double, wavePhase: Double, waveAmplitude: CGFloat, waveFrequency: Double,
        fillLevel: Double, size: CGSize, duckCount: Int,
        attractionX: CGFloat?, attractionStartTime: Double?,
        previousAttractionX: CGFloat? = nil
    ) -> [DuckPosition] {
        let visibleCount = min(duckCount, AppConstants.maxVisibleDucks)
        guard visibleCount > 0 else { return [] }
        let boost: CGFloat = sizeBoost[min(visibleCount - 1, sizeBoost.count - 1)]

        return (0..<visibleCount).map { index in
            let config = configurations[index]
            let adjustedHeight = config.duckHeight * boost
            let pos = SingleDuckView.computePosition(
                time: time, wavePhase: wavePhase, waveAmplitude: waveAmplitude,
                waveFrequency: waveFrequency, fillLevel: fillLevel, size: size,
                config: config, adjustedHeight: adjustedHeight,
                attractionX: attractionX, attractionStartTime: attractionStartTime,
                previousAttractionX: previousAttractionX
            )
            return DuckPosition(index: index, x: pos.x, y: pos.y, height: adjustedHeight)
        }
    }
}

// MARK: - Configuration

struct DuckConfiguration {
    let imageName: String
    let cycleDuration: Double
    let secondaryCycleDuration: Double
    let centerX: CGFloat
    let swingAmplitude: CGFloat
    let secondarySwingAmplitude: CGFloat
    let duckHeight: CGFloat
    let opacity: Double
    let depthOffset: CGFloat
}

// MARK: - Single Duck

struct SingleDuckView: View {
    let time: Double
    let wavePhase: Double
    let waveAmplitude: CGFloat
    let waveFrequency: Double
    let fillLevel: Double
    let size: CGSize
    let imageName: String
    let cycleDuration: Double
    let secondaryCycleDuration: Double
    let centerX: CGFloat
    let swingAmplitude: CGFloat
    let secondarySwingAmplitude: CGFloat
    let duckHeight: CGFloat
    let duckOpacity: Double
    let depthOffset: CGFloat
    var attractionX: CGFloat?
    var attractionStartTime: Double?
    var previousAttractionX: CGFloat?
    var tappedTime: Double?

    /// The effective origin for this swim — previous target if continuing, else original centerX
    private var swimOrigin: CGFloat {
        if let prev = previousAttractionX {
            let spread: CGFloat = 0.08
            let relativeOffset = (centerX - 0.5) * spread / 0.5
            return min(max(prev + relativeOffset, 0.10), 0.90)
        }
        return centerX
    }

    var body: some View {
        // Compute attraction state once per frame (cached)
        let attraction = computeAttraction()
        let duckX = horizontalPosition(attraction: attraction)
        let duckY = verticalPosition(at: duckX) + microBobbing + depthOffset
        let tilt = waveTilt(at: duckX)
        let direction = facingDirection(attraction: attraction, duckX: duckX)
        let turnDip = turnDipScale
        let breathing = (1.0 + sin(time * 2.1 + cycleDuration) * 0.02) * turnDip

        let ripple1Scale = 1.0 + sin(time * 1.7 + cycleDuration) * 0.2
        let ripple2Scale = 1.0 + sin(time * 1.1 + cycleDuration * 0.7) * 0.25

        ZStack {
            Ellipse()
                .fill(.black.opacity(0.12))
                .frame(width: duckHeight * 0.7, height: duckHeight * 0.15)
                .blur(radius: 3)
                .position(x: size.width * duckX, y: duckY + duckHeight * 0.32)

            Ellipse()
                .fill(.white.opacity(rippleOpacity(frequency: 1.3)))
                .frame(width: duckHeight * 0.8 * ripple1Scale, height: 8)
                .position(x: size.width * duckX, y: duckY + duckHeight * 0.36)

            Ellipse()
                .fill(.white.opacity(rippleOpacity(frequency: 0.9)))
                .frame(width: duckHeight * 1.04 * ripple2Scale, height: 6)
                .position(x: size.width * duckX, y: duckY + duckHeight * 0.44)

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: duckHeight)
                .scaleEffect(x: direction, y: 1.0)
                .scaleEffect(breathing)
                .scaleEffect(tapBounce)
                .rotationEffect(.degrees(tilt))
                .position(x: size.width * duckX, y: duckY)
        }
        .opacity(duckOpacity)
    }

    // MARK: - Static position computation (for hit detection)

    static func computePosition(
        time: Double, wavePhase: Double, waveAmplitude: CGFloat, waveFrequency: Double,
        fillLevel: Double, size: CGSize, config: DuckConfiguration, adjustedHeight: CGFloat,
        attractionX: CGFloat?, attractionStartTime: Double?,
        previousAttractionX: CGFloat? = nil
    ) -> (x: CGFloat, y: CGFloat) {
        // Compute effective centerX with steering attraction
        let spread: CGFloat = 0.08
        let relativeOffset = (config.centerX - 0.5) * spread / 0.5

        // Swim origin: previous target if continuing, else original centerX
        let origin: CGFloat
        if let prev = previousAttractionX {
            origin = min(max(prev + relativeOffset, 0.10), 0.90)
        } else {
            origin = config.centerX
        }

        var effectiveCenter = origin
        if let attr = attractionX, let startTime = attractionStartTime {
            let elapsed = time - startTime
            let target = min(max(attr + relativeOffset, 0.10), 0.90)
            let distance = Double(abs(target - origin))

            let duration = max(7.0, distance * 25.0)

            var blend: CGFloat = 0
            if elapsed > 0 {
                let t = min(elapsed / duration, 1.0)
                let t3 = t * t * t; let t4 = t3 * t; let t5 = t4 * t
                blend = CGFloat(6.0 * t5 - 15.0 * t4 + 10.0 * t3)
            }
            effectiveCenter = origin + (target - origin) * blend
        }

        let primary = sin(time / config.cycleDuration * .pi * 2) * config.swingAmplitude
        let secondary = sin(time / config.secondaryCycleDuration * .pi * 2) * config.secondarySwingAmplitude
        let raw = primary + secondary + effectiveCenter
        let duckX = min(max(raw, 0.08), 0.92)

        let minFillY = size.height * 0.95
        let maxFillY = size.height * 0.08
        let waterSurfaceY = minFillY - (minFillY - maxFillY) * fillLevel
        let normalizedPhase = wavePhase.truncatingRemainder(dividingBy: .pi * 2)
        let angle = duckX * .pi * 2 * waveFrequency + normalizedPhase
        let wavePrimary = sin(angle) * waveAmplitude
        let waveSecondary = sin(angle * 2.3 + normalizedPhase * 0.7) * (waveAmplitude * 0.3)
        let microBob = sin(time * 3.7 + config.cycleDuration * 2.3) * 1.5
        let duckY = waterSurfaceY + wavePrimary + waveSecondary + microBob + config.depthOffset

        return (x: size.width * duckX, y: duckY)
    }

    // MARK: - Horizontal Drift (dual harmonic + steering attraction)

    // Disney principles applied:
    // 1. Anticipation — tiny pause before swimming (first 0.3s)
    // 2. Slow-in / Slow-out — quintic ease curve
    // 3. Follow-through — overshoot ~3% past target, then settle
    // 4. Secondary action — swing amplitude reduces during active swim

    /// Each duck goes near the tap but offset by its relative position — ducks don't stack
    private var attractionTarget: CGFloat {
        guard let attr = attractionX else { return centerX }
        let spread: CGFloat = 0.08
        let relativeOffset = (centerX - 0.5) * spread / 0.5
        return min(max(attr + relativeOffset, 0.10), 0.90)
    }

    // MARK: - Attraction state (computed once per frame, cached in body)

    private struct AttractionState {
        let blend: CGFloat
        let swimIntensity: CGFloat
        let target: CGFloat
        let phase: String
        let totalDuration: Double
    }

    private func computeAttraction() -> AttractionState {
        guard let startTime = attractionStartTime, attractionX != nil else {
            return AttractionState(blend: 0, swimIntensity: 0, target: centerX, phase: "idle", totalDuration: 0)
        }

        let target = attractionTarget
        let elapsed = time - startTime
        let origin = swimOrigin
        let distance = Double(abs(target - origin))

        // Quintic ease-in-out: starts at zero velocity, accelerates in middle, arrives gently
        // Single continuous curve — no phases, no discontinuities, no initial jump
        let duration = max(7.0, distance * 25.0)

        guard elapsed > 0 else {
            return AttractionState(blend: 0, swimIntensity: 0, target: target, phase: "notice", totalDuration: duration)
        }

        let t = min(elapsed / duration, 1.0)

        // Quintic: 6t⁵ - 15t⁴ + 10t³ — derivative is zero at t=0 and t=1
        let t3 = t * t * t
        let t4 = t3 * t
        let t5 = t4 * t
        let blend = CGFloat(6.0 * t5 - 15.0 * t4 + 10.0 * t3)

        // Swim intensity: derivative of quintic, peaks at t=0.5 (middle of swim)
        // Derivative: 30t⁴ - 60t³ + 30t² = 30t²(1-t)² — peak at t=0.5 is 1.875
        let intensity: CGFloat
        if t < 1.0 {
            let tSq = t * t
            let oneMinusT = 1.0 - t
            intensity = CGFloat(30.0 * tSq * oneMinusT * oneMinusT) / 1.875
        } else {
            intensity = 0
        }

        let phase: String
        if t < 0.05 { phase = "notice" }
        else if t < 1.0 { phase = "swimming" }
        else { phase = "arrived" }

        // Log every ~2s
        let logInterval = elapsed.truncatingRemainder(dividingBy: 2.0)
        #if DEBUG
        if logInterval < 0.02 {
            let effX = origin + (target - origin) * blend
            AppLog.info("[DuckAttract] duck=\(imageName) phase=\(phase) t=\(String(format: "%.2f", t)) blend=\(String(format: "%.4f", blend)) origin=\(String(format: "%.3f", origin)) effCenterX=\(String(format: "%.3f", effX))", category: .userAction)
        }
        #endif

        return AttractionState(blend: blend, swimIntensity: min(intensity, 1.0), target: target, phase: phase, totalDuration: duration)
    }

    private func horizontalPosition(attraction: AttractionState) -> CGFloat {
        let primary = sin(time / cycleDuration * .pi * 2) * swingAmplitude
        let secondary = sin(time / secondaryCycleDuration * .pi * 2) * secondarySwingAmplitude

        // Dampen oscillation:
        // - Approaching target: ramp 0%→70% as blend goes 0.5→1.0
        // - Continuing from previous: start at 70%, release as duck picks up speed, then re-dampen
        let hasPrevious = previousAttractionX != nil
        let approachDamp: CGFloat
        if hasPrevious {
            // Start dampened (was arrived), release in middle of swim, re-dampen at arrival
            // Uses a V-shape: high at start, low in middle, high at end
            let releaseBlend = min(attraction.blend / 0.3, 1.0)  // release over first 30%
            let reapplyBlend = attraction.blend > 0.5 ? (attraction.blend - 0.5) / 0.5 : 0.0
            approachDamp = max(0.7 * (1.0 - releaseBlend), reapplyBlend * 0.7)
        } else {
            approachDamp = attraction.blend > 0.5
                ? (attraction.blend - 0.5) / 0.5 * 0.7
                : 0.0
        }
        let swimDamp = attraction.swimIntensity * 0.6
        let dampening = 1.0 - max(swimDamp, approachDamp)
        let origin = swimOrigin
        let effCenter = origin + (attraction.target - origin) * attraction.blend
        let raw = (primary + secondary) * dampening + effCenter

        return min(max(raw, 0.08), 0.92)
    }

    private func facingDirection(attraction: AttractionState, duckX: CGFloat) -> CGFloat {
        // During active swim, face toward the target
        if attraction.swimIntensity > 0.1 {
            let origin = swimOrigin
            let effCenter = origin + (attraction.target - origin) * attraction.blend
            if abs(attraction.target - effCenter) > 0.02 {
                return attraction.target > effCenter ? 1.0 : -1.0
            }
        }
        // Normal or arrived: use velocity-based direction
        let velocity = cos(time / cycleDuration * .pi * 2) * swingAmplitude
            + cos(time / secondaryCycleDuration * .pi * 2) * secondarySwingAmplitude
        return velocity >= 0 ? 1.0 : -1.0
    }

    private var turnDipScale: CGFloat {
        let velocity = cos(time / cycleDuration * .pi * 2) * swingAmplitude
            + cos(time / secondaryCycleDuration * .pi * 2) * secondarySwingAmplitude
        let normalizedSpeed = min(abs(velocity) / 0.05, 1.0)
        return 0.92 + normalizedSpeed * 0.08
    }

    private func verticalPosition(at relativeX: CGFloat) -> CGFloat {
        let minFillY = size.height * 0.95
        let maxFillY = size.height * 0.08
        let waterSurfaceY = minFillY - (minFillY - maxFillY) * fillLevel

        let normalizedPhase = wavePhase.truncatingRemainder(dividingBy: .pi * 2)
        let angle = relativeX * .pi * 2 * waveFrequency + normalizedPhase
        let primary = sin(angle) * waveAmplitude
        let secondary = sin(angle * 2.3 + normalizedPhase * 0.7) * (waveAmplitude * 0.3)

        return waterSurfaceY + primary + secondary
    }

    private var microBobbing: CGFloat {
        sin(time * 3.7 + cycleDuration * 2.3) * 1.5
    }

    /// Quick bounce on tap — single sine bump over 0.35s, peak 1.2x scale
    private var tapBounce: CGFloat {
        guard let tappedTime else { return 1.0 }
        let elapsed = time - tappedTime
        guard elapsed >= 0 && elapsed < 0.35 else { return 1.0 }
        return 1.0 + 0.2 * sin(.pi * elapsed / 0.35)
    }

    private func waveTilt(at relativeX: CGFloat) -> Double {
        let normalizedPhase = wavePhase.truncatingRemainder(dividingBy: .pi * 2)
        let angle = relativeX * .pi * 2 * waveFrequency + normalizedPhase
        return cos(angle) * waveAmplitude * 0.45
    }

    private func rippleOpacity(frequency: Double) -> Double {
        let pulse = sin(time * frequency + cycleDuration)
        return max(0, pulse) * 0.25
    }
}
