//
//  WatchColors.swift
//  GlassWaterWatch Watch App
//

import SwiftUI

extension Color {
    // MARK: - Text (watchOS is always dark OLED)

    static let watchTextPrimary: Color = .white
    static let watchTextSecondary: Color = .white.opacity(0.7)
    static let watchTextTertiary: Color = .white.opacity(0.5)

    // MARK: - Water Theme

    static let watchWaterCyan: Color = .cyan
    static let watchWaterBlue: Color = .blue

    // MARK: - Button Backgrounds (Glass-Inspired)

    static let watchButtonFillTop: Color = Color.cyan.opacity(0.25)
    static let watchButtonFillBottom: Color = Color.cyan.opacity(0.12)
    static let watchButtonBorderTop: Color = Color.cyan.opacity(0.4)
    static let watchButtonBorderBottom: Color = Color.cyan.opacity(0.15)
    static let watchButtonHighlight: Color = Color.white.opacity(0.08)

    // MARK: - Card Backgrounds

    static let watchCardBackground: Color = Color.white.opacity(0.08)
    static let watchCardBorder: Color = Color.white.opacity(0.12)

    // MARK: - Status Colors

    static let watchStatusSuccess: Color = .green
    static let watchStatusWarning: Color = .orange
    static let watchStatusCyan: Color = .cyan

    // MARK: - Ring

    static let watchRingBackground: Color = Color.cyan.opacity(0.15)
    static let watchRingGlow: Color = Color.cyan.opacity(0.12)
}
