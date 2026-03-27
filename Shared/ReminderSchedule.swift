//
//  ReminderSchedule.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

enum ReminderSchedule {
    static func scheduleDates(
        referenceDate: Date,
        startMinutes: Int,
        endMinutes: Int,
        intervalMinutes: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        let minutes = reminderMinutes(
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            intervalMinutes: intervalMinutes
        )
        let startOfDay = calendar.startOfDay(for: referenceDate)
        return minutes.compactMap { minute in
            guard let candidate = calendar.date(byAdding: .minute, value: minute, to: startOfDay) else {
                return nil
            }
            guard candidate >= referenceDate else {
                return calendar.date(byAdding: .day, value: 1, to: candidate)
            }
            return candidate
        }
        .sorted()
    }

    static func nextRefreshDate(
        referenceDate: Date,
        startMinutes: Int,
        endMinutes: Int,
        intervalMinutes: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        scheduleDates(
            referenceDate: referenceDate,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            intervalMinutes: intervalMinutes,
            calendar: calendar
        ).first
    }

    static func reminderWindowEndDate(
        referenceDate: Date,
        startMinutes: Int,
        endMinutes: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let clampedStart = max(0, min(24 * 60 - 1, startMinutes))
        let clampedEnd = max(0, min(24 * 60 - 1, endMinutes))
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let minutesNow = minutesFrom(date: referenceDate, calendar: calendar)

        if clampedStart <= clampedEnd {
            return calendar.date(byAdding: .minute, value: clampedEnd, to: startOfDay)
        }

        if minutesNow >= clampedStart {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return calendar.date(byAdding: .minute, value: clampedEnd, to: nextDay)
        }

        return calendar.date(byAdding: .minute, value: clampedEnd, to: startOfDay)
    }

    private static func reminderMinutes(
        startMinutes: Int,
        endMinutes: Int,
        intervalMinutes: Int
    ) -> [Int] {
        let clampedStart = max(0, min(24 * 60 - 1, startMinutes))
        let clampedEnd = max(0, min(24 * 60 - 1, endMinutes))
        let interval = max(30, intervalMinutes)
        var minutes: [Int] = []
        if clampedStart <= clampedEnd {
            minutes.append(contentsOf: stride(from: clampedStart, through: clampedEnd, by: interval))
        } else {
            minutes.append(contentsOf: stride(from: clampedStart, through: 24 * 60 - 1, by: interval))
            minutes.append(contentsOf: stride(from: 0, through: clampedEnd, by: interval))
        }
        if minutes.isEmpty {
            minutes.append(10 * 60 + 30)
        }
        return minutes
    }

    private static func minutesFrom(date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }
}
