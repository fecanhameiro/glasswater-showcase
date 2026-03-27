//
//  WidgetWaterWaveShape.swift
//  GlassWater
//

import SwiftUI

/// Static water wave shape for widgets and Live Activities.
/// Uses dual sine functions for an organic wave surface.
/// Adapted from `WatchWaterWaveShape` — no animation (widgets can't use TimelineView).
struct WidgetWaterWaveShape: Shape {
    /// Fill level from 0 (empty) to 1 (full)
    var fillLevel: Double

    /// Phase offset for visual variety between layers
    var phase: Double = 0

    /// Amplitude of the wave in points
    var amplitude: CGFloat = 3

    /// Frequency — number of complete waves across the width
    var frequency: Double = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width
        let height = rect.height

        // Water surface Y: fillLevel 0 → bottom, fillLevel 1 → top
        let minFillY = height * 0.98
        let maxFillY = height * 0.02
        let waterSurfaceY = minFillY - (minFillY - maxFillY) * CGFloat(fillLevel)

        let stepSize: CGFloat = 2

        // Start at bottom-left
        path.move(to: CGPoint(x: 0, y: height))

        // Up the left edge to wave start
        path.addLine(to: CGPoint(x: 0, y: waterSurfaceY + waveY(at: 0, width: width)))

        // Draw the wavy top edge
        var x: CGFloat = 0
        while x <= width {
            let y = waterSurfaceY + waveY(at: x, width: width)
            path.addLine(to: CGPoint(x: x, y: y))
            x += stepSize
        }

        // Complete the rectangle
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()

        return path
    }

    private func waveY(at x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let relativeX = x / width
        let angle = relativeX * .pi * 2 * frequency + phase

        // Primary wave
        let primary = sin(angle) * amplitude

        // Secondary harmonic for organic feel (30% amplitude, different phase)
        let secondary = sin(angle * 2.3 + phase * 0.7) * (amplitude * 0.3)

        return primary + secondary
    }
}

// MARK: - Water Wave Progress Bar

/// A capsule-shaped progress bar with a wavy water surface.
/// Replaces the standard ProgressView for a premium water-themed experience.
struct WidgetWaterProgressBar: View {
    let progress: Double
    var height: CGFloat = 8
    var accentColor: Color = .cyan

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background capsule
                Capsule()
                    .fill(accentColor.opacity(0.12))

                // Water fill with wave surface
                WidgetWaterWaveShape(
                    fillLevel: 1.0,       // Full height within the clipped area
                    phase: 1.2,           // Fixed phase for visual interest
                    amplitude: height * 0.25,
                    frequency: 3
                )
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.5), accentColor.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * min(max(progress, 0), 1.0))
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}
