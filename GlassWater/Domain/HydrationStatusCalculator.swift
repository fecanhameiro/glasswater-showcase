//
//  HydrationStatusCalculator.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 06/02/26.
//

import Foundation

enum HydrationStatus: Equatable {
    case onTrack
    case slightlyBehind
    case behind
    case goalReached
    case outsideWindow
}

enum HydrationStatusCalculator {
    static func status(
        progress: Double,
        goalReached: Bool,
        reminderStartMinutes: Int,
        reminderEndMinutes: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> HydrationStatus {
        if goalReached { return .goalReached }

        let currentMinutes = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)

        let isInWindow: Bool
        let elapsedMinutes: Double
        let windowDuration: Double

        if reminderStartMinutes <= reminderEndMinutes {
            // Normal window (e.g., 8:00 → 22:00)
            isInWindow = currentMinutes >= reminderStartMinutes && currentMinutes <= reminderEndMinutes
            windowDuration = Double(reminderEndMinutes - reminderStartMinutes)
            elapsedMinutes = Double(currentMinutes - reminderStartMinutes)
        } else {
            // Overnight window (e.g., 22:00 → 6:00)
            isInWindow = currentMinutes >= reminderStartMinutes || currentMinutes <= reminderEndMinutes
            windowDuration = Double((24 * 60 - reminderStartMinutes) + reminderEndMinutes)
            if currentMinutes >= reminderStartMinutes {
                elapsedMinutes = Double(currentMinutes - reminderStartMinutes)
            } else {
                elapsedMinutes = Double((24 * 60 - reminderStartMinutes) + currentMinutes)
            }
        }

        guard isInWindow else { return .outsideWindow }
        guard windowDuration > 0 else { return .outsideWindow }
        let expectedProgress = elapsedMinutes / windowDuration
        let difference = progress - expectedProgress

        if difference >= -0.05 {
            return .onTrack
        } else if difference >= -0.20 {
            return .slightlyBehind
        } else {
            return .behind
        }
    }
}
