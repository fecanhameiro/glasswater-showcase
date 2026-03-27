//
//  DayGoalStatus.swift
//  GlassWater
//
//  Single source of truth for the daily goal → celebration → duck award lifecycle.
//  Persisted as JSON in AppGroup UserDefaults for cross-process visibility.
//  Every decision about celebration/duck reads from here — no in-memory flags.
//

import Foundation

struct DayGoalStatus: Codable, Equatable {

    // MARK: - Status Enum (ordered steps)

    /// Each step in the daily goal flow. Numbered so the next step is always rawValue + 1.
    /// Transitions only go forward (except resetToIdle on delete).
    enum Status: Int, Codable, Comparable {
        case idle = 0              // Day started, goal not reached
        case goalReached = 1       // total >= goalMl (written by app or intent)
        case celebrating = 2       // Celebration animation playing (5s)
        case duckAwarded = 3       // Duck persisted + reward overlay showing
        case completed = 4         // Overlay dismissed, flow done for the day
        case dismissed = 5         // Live Activity ended (30-min timer expired)

        static func < (lhs: Status, rhs: Status) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Fields

    /// Start of the day this status belongs to (calendar.startOfDay).
    var date: Date

    /// Current step in the flow.
    var status: Status

    /// The duckCount at the moment of award (to know which duck image/name to show on resume).
    var duckCountAtAward: Int?

    // MARK: - Persistence

    private static let key = "glasswater.dayGoalStatus"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    }

    /// Load the raw persisted status (any day).
    static func load() -> DayGoalStatus? {
        let ud = defaults
        ud?.synchronize()
        guard let data = ud?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DayGoalStatus.self, from: data)
    }

    /// Load today's status. Returns nil if no status exists or it's from a different day.
    static func loadToday(calendar: Calendar = .autoupdatingCurrent) -> DayGoalStatus? {
        guard let stored = load() else { return nil }
        let today = calendar.startOfDay(for: .now)
        guard calendar.isDate(stored.date, inSameDayAs: today) else { return nil }
        return stored
    }

    /// Save this status to AppGroup with synchronize for cross-process visibility.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let ud = Self.defaults
        ud?.set(data, forKey: Self.key)
        ud?.synchronize()
    }

    // MARK: - Queries

    /// Returns today's status (or .idle if no record exists for today).
    static func currentStatus(calendar: Calendar = .autoupdatingCurrent) -> Status {
        loadToday(calendar: calendar)?.status ?? .idle
    }

    static func hasReachedGoalToday(calendar: Calendar = .autoupdatingCurrent) -> Bool {
        currentStatus(calendar: calendar) >= .goalReached
    }

    static func hasCelebratedToday(calendar: Calendar = .autoupdatingCurrent) -> Bool {
        currentStatus(calendar: calendar) >= .celebrating
    }

    static func hasDuckAwardedToday(calendar: Calendar = .autoupdatingCurrent) -> Bool {
        currentStatus(calendar: calendar) >= .duckAwarded
    }

    static func isCompletedToday(calendar: Calendar = .autoupdatingCurrent) -> Bool {
        currentStatus(calendar: calendar) >= .completed
    }

    // MARK: - Transitions

    /// Advance to a new status. Only moves forward (newStatus > current), never backward.
    /// Returns true if the transition happened.
    @discardableResult
    static func transitionTo(
        _ newStatus: Status,
        duckCount: Int? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let today = calendar.startOfDay(for: .now)
        var record = loadToday(calendar: calendar) ?? DayGoalStatus(date: today, status: .idle)

        // Only advance forward
        guard newStatus > record.status else {
            AppLog.info("[DayGoalStatus] Transition to \(newStatus) SKIPPED — current is \(record.status)", category: .userAction)
            return false
        }

        record.status = newStatus
        if let duckCount {
            record.duckCountAtAward = duckCount
        }
        record.save()
        AppLog.info("[DayGoalStatus] Transition → \(newStatus) (day=\(today))", category: .userAction)
        return true
    }

    /// Reset to idle for today. Called when goal is un-reached (user deletes an entry).
    static func resetToIdle(calendar: Calendar = .autoupdatingCurrent) {
        let today = calendar.startOfDay(for: .now)
        let record = DayGoalStatus(date: today, status: .idle, duckCountAtAward: nil)
        record.save()
        AppLog.info("[DayGoalStatus] Reset → idle (day=\(today))", category: .userAction)
    }
}
