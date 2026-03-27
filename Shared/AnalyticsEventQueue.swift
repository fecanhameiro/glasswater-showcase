//
//  AnalyticsEventQueue.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 08/02/26.
//

import Foundation

struct QueuedAnalyticsEvent: Codable {
    let name: String
    let parameters: [String: String]
    let timestamp: Date
}

final class AnalyticsEventQueue {
    private let defaults: UserDefaults?
    private let key = "glasswater.analytics.queue"

    init() {
        self.defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    }

    func enqueue(_ name: String, parameters: [String: String] = [:]) {
        guard let defaults else { return }
        var events = peek()
        events.append(QueuedAnalyticsEvent(name: name, parameters: parameters, timestamp: .now))
        if events.count > 50 { events = Array(events.suffix(50)) }
        defaults.set(try? JSONEncoder().encode(events), forKey: key)
    }

    func drainAll() -> [QueuedAnalyticsEvent] {
        let events = peek()
        defaults?.removeObject(forKey: key)
        return events
    }

    private func peek() -> [QueuedAnalyticsEvent] {
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([QueuedAnalyticsEvent].self, from: data)) ?? []
    }
}
