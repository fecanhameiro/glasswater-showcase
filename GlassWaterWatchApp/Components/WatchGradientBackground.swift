//
//  WatchGradientBackground.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

struct WatchGradientBackground: View {
    private func gradientColors(for hour: Int) -> [Color] {
        switch hour {
        case 5..<9:
            // Dawn - subtle warm tones
            return [
                Color(red: 0.12, green: 0.14, blue: 0.20),
                Color(red: 0.15, green: 0.20, blue: 0.28),
            ]
        case 9..<17:
            // Day - cool blue tones
            return [
                Color(red: 0.06, green: 0.12, blue: 0.20),
                Color(red: 0.08, green: 0.16, blue: 0.24),
            ]
        case 17..<20:
            // Sunset - warm purple tones
            return [
                Color(red: 0.14, green: 0.10, blue: 0.16),
                Color(red: 0.10, green: 0.14, blue: 0.22),
            ]
        default:
            // Night - deep dark
            return [
                Color(red: 0.04, green: 0.06, blue: 0.10),
                Color(red: 0.06, green: 0.10, blue: 0.14),
            ]
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3600)) { timeline in
            let hour = Calendar.autoupdatingCurrent.component(.hour, from: timeline.date)
            LinearGradient(
                colors: gradientColors(for: hour),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}
