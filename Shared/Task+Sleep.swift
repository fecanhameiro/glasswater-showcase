//
//  Task+Sleep.swift
//  GlassWater
//
//  Created by Claude on 02/02/26.
//

import Foundation

extension Task where Success == Never, Failure == Never {
    /// Sleeps for the specified duration, silently handling cancellation.
    /// Use this when the sleep is for animation/UI timing and cancellation should be ignored.
    static func sleepIgnoringCancellation(nanoseconds duration: UInt64) async {
        do {
            try await Task.sleep(nanoseconds: duration)
        } catch {
            // Task was cancelled - this is expected behavior, not an error
        }
    }

    /// Sleeps for the specified duration, silently handling cancellation.
    /// Use this when the sleep is for animation/UI timing and cancellation should be ignored.
    static func sleepIgnoringCancellation(for duration: Duration) async {
        do {
            try await Task.sleep(for: duration)
        } catch {
            // Task was cancelled - this is expected behavior, not an error
        }
    }

    /// Sleeps for the specified number of seconds, silently handling cancellation.
    static func sleepIgnoringCancellation(seconds: Double) async {
        await sleepIgnoringCancellation(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Sleeps for the specified number of milliseconds, silently handling cancellation.
    static func sleepIgnoringCancellation(milliseconds: Int) async {
        await sleepIgnoringCancellation(for: .milliseconds(milliseconds))
    }
}
