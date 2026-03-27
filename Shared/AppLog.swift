//
//  AppLog.swift
//  GlassWater
//
//  Unified logging API that replaces both SyncLog and scattered os.Logger instances.
//  All log entries write to both os.Logger (Console.app) and AppLogFile (persistent file
//  in App Group for remote upload to Firestore).
//
//  Target membership: iOS app, widget extension, watchOS app.
//

import Foundation
import os.log

// MARK: - LogCategory

enum LogCategory: String, CaseIterable, Codable {
    case sync           // Cross-process sync, widget/LA/watch data flow
    case health         // HealthKit reads/writes/observer
    case notifications  // Notification scheduling, intelligent rules
    case liveActivity   // Live Activity create/update/end
    case watch          // WatchConnectivity, phone<->watch
    case widget         // Widget timeline provider, snapshot loading
    case lifecycle      // App lifecycle, scenePhase, background refresh
    case userAction     // User actions (add water, delete, edit, settings)
    case cloudKit       // CloudKit sync observer
    case onboarding     // Onboarding flow
    case persistence    // SwiftData, SettingsStore operations
    case error          // Catch-all for unexpected errors
}

// MARK: - LogLevel

enum LogLevel: String, Codable, Comparable {
    case info, warning, error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.info, .warning, .error]
        let lhsIndex = order.firstIndex(of: lhs) ?? 0
        let rhsIndex = order.firstIndex(of: rhs) ?? 0
        return lhsIndex < rhsIndex
    }
}

// MARK: - AppLog

enum AppLog {
    /// One os.Logger per category for Console.app filtering
    private static let loggers: [LogCategory: Logger] = {
        var map: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            map[category] = Logger(
                subsystem: "com.glasswater.app",
                category: category.rawValue
            )
        }
        return map
    }()

    static func info(_ message: String, category: LogCategory = .sync) {
        loggers[category]?.info("\(message, privacy: .public)")
        AppLogFile.shared.append(message, level: .info, category: category)
    }

    static func warning(_ message: String, category: LogCategory = .sync) {
        loggers[category]?.warning("\(message, privacy: .public)")
        AppLogFile.shared.append(message, level: .warning, category: category)
    }

    static func error(_ message: String, category: LogCategory = .sync) {
        loggers[category]?.error("\(message, privacy: .public)")
        AppLogFile.shared.append(message, level: .error, category: category)
    }
}
