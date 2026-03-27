//
//  WatchWaterWaveShape.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

/// A shape representing water with a wavy surface at the top.
/// Uses dual sine functions for organic wave movement.
struct WatchWaterWaveShape: Shape {
    /// Phase offset of the wave (animated via TimelineView)
    var phase: Double

    /// Amplitude of the wave in points
    var amplitude: CGFloat

    /// Frequency of the wave (complete waves across the width)
    var frequency: Double

    /// Fill level from 0 (empty) to 1 (full)
    var fillLevel: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, fillLevel) }
        set {
            phase = newValue.first
            fillLevel = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Water surface Y position
        // At fillLevel 0: water at 95% down (5% from bottom visible)
        // At fillLevel 1: water at 8% down (92% filled)
        let minFillY = rect.height * 0.95
        let maxFillY = rect.height * 0.08
        let waterSurfaceY = minFillY - (minFillY - maxFillY) * CGFloat(fillLevel)

        let width = rect.width
        let stepSize: CGFloat = 2

        // Start at bottom-left
        path.move(to: CGPoint(x: 0, y: rect.height))

        // Line up the left edge to the wave start
        path.addLine(to: CGPoint(x: 0, y: waterSurfaceY + waveY(at: 0, width: width)))

        // Draw the wavy top edge
        var x: CGFloat = 0
        while x <= width {
            let y = waterSurfaceY + waveY(at: x, width: width)
            path.addLine(to: CGPoint(x: x, y: y))
            x += stepSize
        }

        // Complete the rectangle
        path.addLine(to: CGPoint(x: width, y: rect.height))
        path.closeSubpath()

        return path
    }

    /// Calculates the Y offset for the wave at a given X position
    fileprivate func waveY(at x: CGFloat, width: CGFloat) -> CGFloat {
        let relativeX = x / width
        let normalizedPhase = phase.truncatingRemainder(dividingBy: .pi * 2)
        let angle = relativeX * .pi * 2 * frequency + normalizedPhase

        // Primary wave
        let primary = sin(angle) * amplitude

        // Secondary harmonic for organic feel (smaller, faster)
        let secondary = sin(angle * 2.3 + normalizedPhase * 0.7) * (amplitude * 0.3)

        return primary + secondary
    }
}

// MARK: - Surface Line (open path for shimmer stroke)

/// Draws only the wave surface line — no filled rectangle.
/// Used for the shimmer/highlight stroke effect on the water surface.
struct WatchWaterSurfaceLine: Shape {
    var phase: Double
    var amplitude: CGFloat
    var frequency: Double
    var fillLevel: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, fillLevel) }
        set {
            phase = newValue.first
            fillLevel = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let minFillY = rect.height * 0.95
        let maxFillY = rect.height * 0.08
        let waterSurfaceY = minFillY - (minFillY - maxFillY) * CGFloat(fillLevel)

        let width = rect.width
        var path = Path()

        path.move(to: CGPoint(x: 0, y: waterSurfaceY + waveY(at: 0, width: width)))

        var x: CGFloat = 0
        while x <= width {
            let y = waterSurfaceY + waveY(at: x, width: width)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }

        // Open path — not closed, so stroke only traces the wave line
        return path
    }

    private func waveY(at x: CGFloat, width: CGFloat) -> CGFloat {
        let relativeX = x / width
        let normalizedPhase = phase.truncatingRemainder(dividingBy: .pi * 2)
        let angle = relativeX * .pi * 2 * frequency + normalizedPhase

        let primary = sin(angle) * amplitude
        let secondary = sin(angle * 2.3 + normalizedPhase * 0.7) * (amplitude * 0.3)

        return primary + secondary
    }
}
