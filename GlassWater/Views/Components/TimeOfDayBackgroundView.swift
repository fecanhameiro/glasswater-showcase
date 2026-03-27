//
//  TimeOfDayBackgroundView.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import SwiftUI

struct TimeOfDayBackgroundView: View {
    private let calendar = Calendar.autoupdatingCurrent
    /// When true, uses a lighter night gradient in light mode (suitable for Home screen).
    var lightenNight: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 900)) { context in
            let hour = calendar.component(.hour, from: context.date)
            let hasLightBackground = colorScheme == .light && (lightenNight || TimeOfDayPeriod(hour: hour).hasLightBackground)
            ZStack {
                LinearGradient(
                    colors: gradientColors(for: hour),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Color.white.opacity(hasLightBackground ? 0.18 : 0.08), Color.clear],
                    center: .top,
                    startRadius: 40,
                    endRadius: 280
                )
                .blendMode(.softLight)
            }
            .ignoresSafeArea()
            .animation(.spring(.smooth(duration: 0.8)), value: hour)
        }
    }

    private func gradientColors(for hour: Int) -> [Color] {
        if colorScheme == .dark {
            return darkModeGradientColors(for: hour)
        } else {
            return lightModeGradientColors(for: hour)
        }
    }

    private func lightModeGradientColors(for hour: Int) -> [Color] {
        // Light, airy gradients for day periods - text adapts via TimeOfDayColors
        switch hour {
        case 5..<9:
            // Morning - warm pastel sunrise tones
            return [
                Color(red: 0.96, green: 0.85, blue: 0.78),
                Color(red: 0.78, green: 0.88, blue: 0.95)
            ]
        case 9..<17:
            // Day - bright sky blue with teal
            return [
                Color(red: 0.75, green: 0.88, blue: 0.96),
                Color(red: 0.70, green: 0.90, blue: 0.88)
            ]
        case 17..<20:
            // Evening - warm sunset pastels
            return [
                Color(red: 0.95, green: 0.82, blue: 0.70),
                Color(red: 0.78, green: 0.82, blue: 0.92)
            ]
        default:
            if lightenNight {
                // Night (Home only) - medium blue tones for dark text
                return [
                    Color(red: 0.45, green: 0.55, blue: 0.70),
                    Color(red: 0.38, green: 0.50, blue: 0.62)
                ]
            }
            // Night - deep dark tones (text will be white)
            return [
                Color(red: 0.12, green: 0.17, blue: 0.25),
                Color(red: 0.18, green: 0.27, blue: 0.32)
            ]
        }
    }

    private func darkModeGradientColors(for hour: Int) -> [Color] {
        switch hour {
        case 5..<9:
            // Morning - warm dark tones
            return [
                Color(red: 0.18, green: 0.14, blue: 0.12),
                Color(red: 0.12, green: 0.18, blue: 0.22)
            ]
        case 9..<17:
            // Day - cool dark tones with subtle cyan
            return [
                Color(red: 0.08, green: 0.14, blue: 0.20),
                Color(red: 0.10, green: 0.18, blue: 0.22)
            ]
        case 17..<20:
            // Evening - warm dark tones
            return [
                Color(red: 0.16, green: 0.12, blue: 0.10),
                Color(red: 0.10, green: 0.14, blue: 0.20)
            ]
        default:
            // Night - deep dark tones
            return [
                Color(red: 0.06, green: 0.08, blue: 0.12),
                Color(red: 0.08, green: 0.12, blue: 0.16)
            ]
        }
    }
}
