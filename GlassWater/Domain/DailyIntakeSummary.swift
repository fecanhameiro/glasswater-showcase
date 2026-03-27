//
//  DailyIntakeSummary.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

struct DailyIntakeSummary: Identifiable {
    let date: Date
    let amountMl: Int
    let goalMl: Int
    let entryCount: Int
    let entries: [WaterEntry]

    var id: Date { date }

    var progress: Double {
        guard goalMl > 0 else { return 0 }
        return Double(amountMl) / Double(goalMl)
    }

    var isGoalMet: Bool {
        amountMl >= goalMl
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(date)
    }
}

// MARK: - Weekly Insight

enum WeeklyInsight: Equatable {
    case morningPerson
    case afternoonPerson
    case eveningPerson
    case consistentHydration
    case improvingTrend
    case needsMoreWater
    case greatWeek
    case none

    var text: String? {
        switch self {
        case .morningPerson:
            return String(localized: "history_insight_morning_person")
        case .afternoonPerson:
            return String(localized: "history_insight_afternoon_person")
        case .eveningPerson:
            return String(localized: "history_insight_evening_person")
        case .consistentHydration:
            return String(localized: "history_insight_consistent")
        case .improvingTrend:
            return String(localized: "history_insight_improving")
        case .needsMoreWater:
            return String(localized: "history_insight_needs_more")
        case .greatWeek:
            return String(localized: "history_insight_great_week")
        case .none:
            return nil
        }
    }

    var emoji: String {
        switch self {
        case .morningPerson: return "☀️"
        case .afternoonPerson: return "🌤️"
        case .eveningPerson: return "🌙"
        case .consistentHydration: return "⚖️"
        case .improvingTrend: return "📈"
        case .needsMoreWater: return "💪"
        case .greatWeek: return "🏆"
        case .none: return ""
        }
    }
}
