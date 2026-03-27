//
//  SyncLog.swift
//  GlassWater
//
//  Thin wrapper over AppLog for backward compatibility.
//  All 126+ existing call sites continue to work unchanged.
//

import Foundation

// MARK: - SyncLog (Backward Compat Wrapper)

enum SyncLog {
    static func info(_ message: String) { AppLog.info(message, category: .sync) }
    static func warning(_ message: String) { AppLog.warning(message, category: .sync) }
    static func error(_ message: String) { AppLog.error(message, category: .sync) }
}

// MARK: - SyncLogFile (Alias for backward compat)

/// Alias so existing references to `SyncLogFile.shared` continue to compile.
typealias SyncLogFile = AppLogFile
