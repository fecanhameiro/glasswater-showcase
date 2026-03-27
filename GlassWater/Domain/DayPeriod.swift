//
//  DayPeriod.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

enum DayPeriod: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case night

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .morning: return "☀️"
        case .afternoon: return "🌤️"
        case .night: return "🌙"
        }
    }

    var localizedName: String {
        switch self {
        case .morning: return String(localized: "entries_period_morning")
        case .afternoon: return String(localized: "entries_period_afternoon")
        case .night: return String(localized: "entries_period_night")
        }
    }

    static func from(hour: Int) -> DayPeriod {
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        default: return .night
        }
    }
}
