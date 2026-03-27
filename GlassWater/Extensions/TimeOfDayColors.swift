//
//  TimeOfDayColors.swift
//  GlassWater
//
//  Adaptive color system based on time of day.
//  Light mode day: Dark text over light gradients.
//  Light mode night or Dark mode: White text over dark gradients.
//

import SwiftUI

// MARK: - Time of Day Period

enum TimeOfDayPeriod: CaseIterable {
    case morning    // 5-9h
    case day        // 9-17h
    case evening    // 17-20h
    case night      // 20-5h

    init(hour: Int) {
        switch hour {
        case 5..<9: self = .morning
        case 9..<17: self = .day
        case 17..<20: self = .evening
        default: self = .night
        }
    }

    static var current: TimeOfDayPeriod {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: Date())
        return TimeOfDayPeriod(hour: hour)
    }

    /// True if the period has a light/bright gradient background in light mode
    var hasLightBackground: Bool {
        switch self {
        case .morning, .day, .evening: return true
        case .night: return false
        }
    }
}

// MARK: - Environment Key for Lightened Night Background

/// When true, views should treat the background as light even during night period
/// (used by HomeView which uses a lighter night gradient in light mode).
private struct LightenedNightBackgroundKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var lightenedNightBackground: Bool {
        get { self[LightenedNightBackgroundKey.self] }
        set { self[LightenedNightBackgroundKey.self] = newValue }
    }
}

// MARK: - Adaptive TimeOfDay Colors

extension Color {
    /// Primary text - adapts to background luminosity based on time of day
    /// Dark text on light backgrounds (day), white on dark backgrounds (night/dark mode)
    static func adaptiveTimeOfDayText(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return .white
        }
        return TimeOfDayPeriod.current.hasLightBackground
            ? Color(red: 0.08, green: 0.08, blue: 0.12)  // Near black
            : .white
    }

    /// Secondary text - adapts to background luminosity
    static func adaptiveTimeOfDaySecondaryText(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return .white.opacity(0.85)
        }
        return TimeOfDayPeriod.current.hasLightBackground
            ? Color(red: 0.2, green: 0.2, blue: 0.25)   // Dark gray
            : .white.opacity(0.85)
    }

    /// Tertiary text - adapts to background luminosity
    static func adaptiveTimeOfDayTertiaryText(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return .white.opacity(0.6)
        }
        return TimeOfDayPeriod.current.hasLightBackground
            ? Color(red: 0.35, green: 0.35, blue: 0.4)  // Medium gray
            : .white.opacity(0.6)
    }

    /// Card background - adapts for visibility on TimeOfDay backgrounds
    static func adaptiveTimeOfDayCardBackground(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.1)
        }
        return TimeOfDayPeriod.current.hasLightBackground
            ? Color.black.opacity(0.06)                 // Dark overlay on light
            : Color.white.opacity(0.1)                  // Light overlay on dark
    }

    /// Card stroke - adapts for visibility on TimeOfDay backgrounds
    static func adaptiveTimeOfDayCardStroke(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.12)
        }
        return TimeOfDayPeriod.current.hasLightBackground
            ? Color.black.opacity(0.1)
            : Color.white.opacity(0.12)
    }

    /// Accent color - cyan that adapts brightness for contrast
    static func adaptiveTimeOfDayAccent(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return .cyan
        }
        return TimeOfDayPeriod.current.hasLightBackground
            ? Color(red: 0.0, green: 0.55, blue: 0.7)   // Darker cyan
            : .cyan
    }
}

// MARK: - Environment Key for Adaptive Colors

private struct AdaptiveTimeOfDayTextKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

private struct AdaptiveTimeOfDaySecondaryTextKey: EnvironmentKey {
    static let defaultValue: Color = .white.opacity(0.85)
}

private struct AdaptiveTimeOfDayTertiaryTextKey: EnvironmentKey {
    static let defaultValue: Color = .white.opacity(0.6)
}

private struct AdaptiveTimeOfDayCardBackgroundKey: EnvironmentKey {
    static let defaultValue: Color = .white.opacity(0.1)
}

private struct AdaptiveTimeOfDayCardStrokeKey: EnvironmentKey {
    static let defaultValue: Color = .white.opacity(0.12)
}

extension EnvironmentValues {
    var adaptiveTimeOfDayText: Color {
        get { self[AdaptiveTimeOfDayTextKey.self] }
        set { self[AdaptiveTimeOfDayTextKey.self] = newValue }
    }

    var adaptiveTimeOfDaySecondaryText: Color {
        get { self[AdaptiveTimeOfDaySecondaryTextKey.self] }
        set { self[AdaptiveTimeOfDaySecondaryTextKey.self] = newValue }
    }

    var adaptiveTimeOfDayTertiaryText: Color {
        get { self[AdaptiveTimeOfDayTertiaryTextKey.self] }
        set { self[AdaptiveTimeOfDayTertiaryTextKey.self] = newValue }
    }

    var adaptiveTimeOfDayCardBackground: Color {
        get { self[AdaptiveTimeOfDayCardBackgroundKey.self] }
        set { self[AdaptiveTimeOfDayCardBackgroundKey.self] = newValue }
    }

    var adaptiveTimeOfDayCardStroke: Color {
        get { self[AdaptiveTimeOfDayCardStrokeKey.self] }
        set { self[AdaptiveTimeOfDayCardStrokeKey.self] = newValue }
    }
}

// MARK: - View Modifier for Injecting Adaptive Colors

struct AdaptiveTimeOfDayColorsModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.adaptiveTimeOfDayText, Color.adaptiveTimeOfDayText(for: colorScheme))
            .environment(\.adaptiveTimeOfDaySecondaryText, Color.adaptiveTimeOfDaySecondaryText(for: colorScheme))
            .environment(\.adaptiveTimeOfDayTertiaryText, Color.adaptiveTimeOfDayTertiaryText(for: colorScheme))
            .environment(\.adaptiveTimeOfDayCardBackground, Color.adaptiveTimeOfDayCardBackground(for: colorScheme))
            .environment(\.adaptiveTimeOfDayCardStroke, Color.adaptiveTimeOfDayCardStroke(for: colorScheme))
    }
}

extension View {
    /// Applies adaptive time-of-day colors to the view hierarchy.
    /// Call this on the root view that uses TimeOfDayBackgroundView.
    func adaptiveTimeOfDayColors() -> some View {
        modifier(AdaptiveTimeOfDayColorsModifier())
    }
}
