//
//  LiveActivityState.swift
//  GlassWater
//
//  Single source of truth for Live Activity goal/celebration lifecycle.
//  Persisted as JSON in AppGroup UserDefaults so all surfaces (app, widget,
//  LA intent, background refresh) share the same state.
//

import Foundation

struct LiveActivityState: Codable, Equatable {

    // MARK: - Phase

    enum Phase: String, Codable {
        /// No active LA (before first entry or after day rollover with no entries)
        case idle
        /// LA showing hydration progress (0% < progress < 100%)
        case inProgress
        /// Goal reached, celebration showing on LA
        case goalReached
        /// Celebration dismissed (30-min timer expired), LA ended for the day
        case dismissed
        /// Day rolled over, LA showing "new day" with yesterday's summary
        case newDay
    }

    // MARK: - Properties

    /// Current lifecycle phase
    var phase: Phase

    /// Timestamp when this phase was entered
    var date: Date

    /// Start of the current day (used for day-change detection)
    var dayStart: Date

    /// When the celebration should auto-dismiss (only set in .goalReached phase)
    var celebrationDismissAt: Date?

    // MARK: - Persistence

    private static let key = "glasswater.liveActivityState"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    }

    /// Load the current state from AppGroup. Returns nil if no state exists.
    static func load() -> LiveActivityState? {
        let ud = defaults
        ud?.synchronize()
        guard let data = ud?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LiveActivityState.self, from: data)
    }

    /// Save this state to AppGroup with synchronize for cross-process visibility.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let ud = Self.defaults
        ud?.set(data, forKey: Self.key)
        ud?.synchronize()
    }

    /// Remove all persisted state (e.g., for testing or full reset).
    static func clear() {
        let ud = defaults
        ud?.removeObject(forKey: key)
        ud?.synchronize()
    }

    // MARK: - Factory

    /// Create a fresh idle state for today.
    static func idle(calendar: Calendar = .autoupdatingCurrent) -> LiveActivityState {
        LiveActivityState(
            phase: .idle,
            date: .now,
            dayStart: calendar.startOfDay(for: .now)
        )
    }

    // MARK: - Transitions

    /// Transition to a new phase. Updates `date` to now.
    /// If a day change is detected, transitions to `.newDay` instead of the requested phase
    /// and returns `false` to signal that the requested transition was overridden.
    /// Returns `true` if the requested phase was applied, `false` if day change overrode it.
    @discardableResult
    mutating func transition(
        to newPhase: Phase,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        celebrationDismissAt: Date? = nil
    ) -> Bool {
        let today = calendar.startOfDay(for: now)

        // Day change always wins — reset to newDay regardless of current phase
        if today != dayStart {
            let oldDayStart = dayStart
            phase = .newDay
            date = now
            dayStart = today
            self.celebrationDismissAt = nil
            save()
            AppLog.info("[LA State] Transition → newDay (day changed from \(oldDayStart) to \(today)), requested \(newPhase.rawValue) was overridden", category: .liveActivity)
            return false
        }

        phase = newPhase
        date = now
        self.celebrationDismissAt = celebrationDismissAt ?? (newPhase == .goalReached ? self.celebrationDismissAt : nil)
        save()
        AppLog.info("[LA State] Transition → \(newPhase.rawValue) at \(now)", category: .liveActivity)
        return true
    }

    // MARK: - Queries

    /// Whether the celebration timer has expired.
    func isCelebrationExpired(now: Date = .now) -> Bool {
        guard phase == .goalReached, let dismissAt = celebrationDismissAt else { return false }
        return now >= dismissAt
    }

    /// Whether this state is from today.
    func isToday(calendar: Calendar = .autoupdatingCurrent) -> Bool {
        calendar.isDateInToday(dayStart)
    }

    /// Whether the goal was already celebrated today (phase is goalReached or dismissed).
    var goalCelebratedToday: Bool {
        phase == .goalReached || phase == .dismissed
    }
}
