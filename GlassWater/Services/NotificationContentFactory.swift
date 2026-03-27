//
//  NotificationContentFactory.swift
//  GlassWater
//

import Foundation

enum NotificationContentFactory {
    struct Context {
        let currentTotalMl: Int
        let dailyGoalMl: Int
        let date: Date
        let streakCount: Int
    }

    static func makeContent(context: Context) -> (title: String, body: String) {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: context.date)
        let progress = context.dailyGoalMl > 0
            ? Double(context.currentTotalMl) / Double(context.dailyGoalMl)
            : 0

        // Deterministic rotation: same day+hour always picks the same variant
        let dayOrdinal = Calendar.autoupdatingCurrent.ordinality(of: .day, in: .era, for: context.date) ?? 0
        let seed = dayOrdinal &+ hour

        let title = resolveTitle(hour: hour, seed: seed)
        let body = resolveBody(hour: hour, progress: progress, streakCount: context.streakCount, seed: seed)
        return (title, body)
    }

    // MARK: - Title

    private static func resolveTitle(hour: Int, seed: Int) -> String {
        let keys: [String]
        switch hour {
        case 5..<12:
            keys = [
                "notification_title_morning_1",
                "notification_title_morning_2",
                "notification_title_morning_3"
            ]
        case 12..<17:
            keys = [
                "notification_title_afternoon_1",
                "notification_title_afternoon_2",
                "notification_title_afternoon_3"
            ]
        default:
            keys = [
                "notification_title_evening_1",
                "notification_title_evening_2",
                "notification_title_evening_3"
            ]
        }
        let index = abs(seed) % keys.count
        return String(localized: String.LocalizationValue(keys[index]))
    }

    // MARK: - Body

    private static func resolveBody(hour: Int, progress: Double, streakCount: Int, seed: Int) -> String {
        // Streak-based messages take priority occasionally (every 3rd notification if streak >= 3)
        if streakCount >= 3, seed % 3 == 0 {
            return streakBody(streakCount: streakCount)
        }

        // Progress-based messages
        let keys: [String]
        switch progress {
        case ..<0.25:
            keys = [
                "notification_body_low_1",
                "notification_body_low_2",
                "notification_body_low_3"
            ]
        case 0.25..<0.50:
            keys = [
                "notification_body_quarter_1",
                "notification_body_quarter_2",
                "notification_body_quarter_3"
            ]
        case 0.50..<0.75:
            keys = [
                "notification_body_half_1",
                "notification_body_half_2",
                "notification_body_half_3"
            ]
        default:
            keys = [
                "notification_body_high_1",
                "notification_body_high_2",
                "notification_body_high_3"
            ]
        }
        let index = abs(seed) % keys.count
        return String(localized: String.LocalizationValue(keys[index]))
    }

    private static func streakBody(streakCount: Int) -> String {
        if streakCount >= 30 {
            return String(localized: "notification_body_streak_30")
        } else if streakCount >= 7 {
            return String(localized: "notification_body_streak_7")
        } else {
            return String(localized: "notification_body_streak_3")
        }
    }
}
