//
//  AppColors.swift
//  GlassWater
//
//  Premium color palette for the GlassWater app
//  Theme: Water/Hydration with Apple Design System integration
//

import SwiftUI

// MARK: - App Colors

extension Color {

    // MARK: - Semantic Colors

    /// Color for water drop icons and highlights
    static var waterDrop: Color {
        Color(light: .init(red: 0.0, green: 0.68, blue: 0.94),   // Vibrant cyan
              dark: .init(red: 0.4, green: 0.85, blue: 1.0))     // Bright cyan
    }

    /// Gradient start for water-related UI
    static var waterGradientStart: Color {
        Color(light: .init(red: 0.0, green: 0.75, blue: 0.95),   // Cyan
              dark: .init(red: 0.3, green: 0.78, blue: 1.0))     // Light cyan
    }

    /// Gradient end for water-related UI
    static var waterGradientEnd: Color {
        Color(light: .init(red: 0.0, green: 0.48, blue: 1.0),    // Blue
              dark: .init(red: 0.2, green: 0.55, blue: 1.0))     // Soft blue
    }

    // MARK: - Text Colors (High Contrast)

    /// Primary text - maximum contrast
    static var textPrimary: Color {
        Color(light: .init(red: 0.1, green: 0.1, blue: 0.12),    // Near black
              dark: .init(red: 1.0, green: 1.0, blue: 1.0))      // White
    }

    /// Secondary text - good contrast for subtitles
    static var textSecondary: Color {
        Color(light: .init(red: 0.35, green: 0.35, blue: 0.4),   // Dark gray
              dark: .init(red: 0.85, green: 0.85, blue: 0.88))   // Light gray
    }

    /// Tertiary text - for less important info
    static var textTertiary: Color {
        Color(light: .init(red: 0.5, green: 0.5, blue: 0.55),    // Medium gray
              dark: .init(red: 0.7, green: 0.7, blue: 0.75))     // Soft gray
    }

    // MARK: - Surface Colors

    /// Card background for light elevated surfaces
    static var surfaceElevated: Color {
        Color(light: .init(red: 1.0, green: 1.0, blue: 1.0),     // White
              dark: .init(red: 0.15, green: 0.15, blue: 0.18))   // Dark gray
    }

    /// Subtle background for grouped content
    static var surfaceGrouped: Color {
        Color(light: .init(red: 0.95, green: 0.95, blue: 0.97),  // Light gray
              dark: .init(red: 0.11, green: 0.11, blue: 0.13))   // Very dark
    }

    // MARK: - Glass/Material Overlay Colors

    /// Border color for glass materials
    static var glassBorder: Color {
        Color(light: .init(white: 0.0, opacity: 0.08),
              dark: .init(white: 1.0, opacity: 0.2))
    }

    /// Inner highlight for glass materials
    static var glassHighlight: Color {
        Color(light: .init(white: 1.0, opacity: 0.6),
              dark: .init(white: 1.0, opacity: 0.08))
    }

    /// Shadow color for elevated elements
    static var glassShadow: Color {
        Color(light: .init(red: 0.0, green: 0.2, blue: 0.4, opacity: 0.12),
              dark: .init(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.4))
    }

    // MARK: - Status Colors

    /// Success/On track color
    static var statusSuccess: Color {
        Color(light: .init(red: 0.188, green: 0.82, blue: 0.345),
              dark: .init(red: 0.25, green: 0.88, blue: 0.42))
    }

    /// Warning/Slightly behind color
    static var statusWarning: Color {
        Color(light: .init(red: 0.95, green: 0.6, blue: 0.1),
              dark: .init(red: 1.0, green: 0.75, blue: 0.3))
    }

    /// Alert/Behind color
    static var statusAlert: Color {
        Color(light: .init(red: 1.0, green: 0.45, blue: 0.2),
              dark: .init(red: 1.0, green: 0.6, blue: 0.35))
    }

    // MARK: - Interactive Colors

    /// Button background (filled)
    static var buttonFilled: Color {
        Color(light: .init(red: 0.0, green: 0.68, blue: 0.94),
              dark: .init(red: 0.3, green: 0.75, blue: 1.0))
    }

    /// Button background (secondary/muted)
    static var buttonMuted: Color {
        Color(light: .init(white: 0.0, opacity: 0.06),
              dark: .init(white: 1.0, opacity: 0.12))
    }

    // MARK: - TimeOfDay Background Colors (Adaptive)
    // These colors adapt based on time of day AND color scheme:
    // - Light mode day (5-20h): Dark text over light gradients
    // - Light mode night (20-5h) or Dark mode: White text over dark gradients

    /// Primary text color for views over TimeOfDayBackgroundView - ADAPTS to time of day
    static var onTimeOfDayText: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return .white
            }
            // Light mode: check time of day
            return TimeOfDayPeriod.current.hasLightBackground
                ? UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
                : .white
        })
    }

    /// Secondary text color for views over TimeOfDayBackgroundView - ADAPTS
    static var onTimeOfDaySecondaryText: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.85)
            }
            return TimeOfDayPeriod.current.hasLightBackground
                ? UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0)
                : UIColor.white.withAlphaComponent(0.85)
        })
    }

    /// Tertiary text color for views over TimeOfDayBackgroundView - ADAPTS
    static var onTimeOfDayTertiaryText: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.6)
            }
            return TimeOfDayPeriod.current.hasLightBackground
                ? UIColor(red: 0.35, green: 0.35, blue: 0.4, alpha: 1.0)
                : UIColor.white.withAlphaComponent(0.6)
        })
    }

    /// Card background for views over TimeOfDayBackgroundView - ADAPTS
    static var onTimeOfDayCardBackground: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.1)
            }
            return TimeOfDayPeriod.current.hasLightBackground
                ? UIColor.black.withAlphaComponent(0.06)
                : UIColor.white.withAlphaComponent(0.1)
        })
    }

    // MARK: - System Background Card Colors
    // For views over system backgrounds (sheets, modals, grouped backgrounds)

    /// Card background over system backgrounds (subtle)
    static var systemCardBackground: Color {
        Color(light: .init(white: 0.0, opacity: 0.04),
              dark: .init(white: 1.0, opacity: 0.08))
    }

    /// Card stroke over system backgrounds (subtle)
    static var systemCardStroke: Color {
        Color(light: .init(white: 0.0, opacity: 0.06),
              dark: .init(white: 1.0, opacity: 0.1))
    }

    /// Prominent card background over system backgrounds (higher contrast)
    static var systemCardBackgroundProminent: Color {
        Color(light: .init(white: 0.0, opacity: 0.05),
              dark: .init(white: 1.0, opacity: 0.1))
    }

    /// Prominent card stroke over system backgrounds (higher contrast)
    static var systemCardStrokeProminent: Color {
        Color(light: .init(white: 0.0, opacity: 0.08),
              dark: .init(white: 1.0, opacity: 0.12))
    }

    /// Card stroke for views over TimeOfDayBackgroundView - ADAPTS
    static var onTimeOfDayCardStroke: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.12)
            }
            return TimeOfDayPeriod.current.hasLightBackground
                ? UIColor.black.withAlphaComponent(0.1)
                : UIColor.white.withAlphaComponent(0.12)
        })
    }
}

// MARK: - Color Initialization Helper

extension Color {
    /// Creates a color that adapts to light and dark mode
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }

    /// Creates a color from RGB values (0-1 range)
    init(light lightColor: UIColor, dark darkColor: UIColor) {
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
}

// MARK: - Gradient Presets

extension LinearGradient {
    /// Primary water gradient for buttons and highlights
    static var waterGradient: LinearGradient {
        LinearGradient(
            colors: [.waterGradientStart, .waterGradientEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Vertical water gradient for backgrounds
    static var waterVerticalGradient: LinearGradient {
        LinearGradient(
            colors: [.waterGradientStart, .waterGradientEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Glass inner highlight gradient
    static func glassHighlight(opacity: Double = 1.0) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.glassHighlight.opacity(opacity),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
    }
}

// MARK: - View Modifiers for Consistent Styling (iOS 26 Liquid Glass)

extension View {
    /// Applies iOS 26 Liquid Glass card styling
    /// Use for navigation layer elements that float over content
    func premiumGlassCard(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        self.glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    /// Applies iOS 26 Liquid Glass capsule styling
    /// Use for navigation layer elements that float over content
    func premiumGlassCapsule(interactive: Bool = false) -> some View {
        self.glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: .capsule
        )
    }

    /// Applies iOS 26 Liquid Glass circle styling
    /// Use for navigation layer elements that float over content
    func premiumGlassCircle(interactive: Bool = false) -> some View {
        self.glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: .circle
        )
    }

    /// Applies iOS 26 Liquid Glass with tint color
    /// Use for interactive buttons with semantic color
    func premiumGlassTinted(_ color: Color, interactive: Bool = true) -> some View {
        self.glassEffect(
            interactive ? .regular.tint(color).interactive() : .regular.tint(color),
            in: .capsule
        )
    }
}
