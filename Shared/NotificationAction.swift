//
//  NotificationAction.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

enum NotificationAction {
    static let reminderCategory = "glasswater.reminder.category"
    static let customInputIdentifier = "glasswater.add.custom.input"
    static let customSavedIdentifier = "glasswater.add.custom.saved"
    static let snoozeIdentifier = "glasswater.snooze"
    static let snoozeReminderIdentifier = "glasswater.snooze.reminder"

    static func percentIdentifier(_ percent: Int) -> String {
        "glasswater.add.percent.\(percent)"
    }

    // Legacy identifier that encoded the amount at scheduling time.
    static func customAmountIdentifier(_ amountMl: Int) -> String {
        "glasswater.add.custom.\(amountMl)"
    }

    static func percent(from identifier: String) -> Int? {
        identifier.intValue(forPrefix: "glasswater.add.percent.")
    }

    static func customAmount(from identifier: String) -> Int? {
        guard identifier != customInputIdentifier,
              identifier != customSavedIdentifier
        else { return nil }
        return identifier.intValue(forPrefix: "glasswater.add.custom.")
    }
}

private extension String {
    func intValue(forPrefix prefix: String) -> Int? {
        guard hasPrefix(prefix) else { return nil }
        return Int(replacingOccurrences(of: prefix, with: ""))
    }
}
