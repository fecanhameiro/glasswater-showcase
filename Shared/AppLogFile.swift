//
//  AppLogFile.swift
//  GlassWater
//
//  Persistent log file writer. Evolves from SyncLogFile with structured format.
//  Same file location (sync_log.txt), same 256KB limit, same rotation strategy.
//
//  New format: "HH:mm:ss.SSS [LEVEL|category] message"
//
//  Target membership: iOS app, widget extension, watchOS app.
//

import Foundation

// MARK: - LogEntry

struct LogEntry {
    let timestamp: String
    let level: LogLevel
    let category: LogCategory
    let message: String
}

// MARK: - AppLogFile

final class AppLogFile: @unchecked Sendable {
    static let shared = AppLogFile()

    private let fileURL: URL?
    private let maxFileSize = 256_000 // 256KB — keeps ~2000 log lines
    private let queue = DispatchQueue(label: "com.glasswater.applog", qos: .utility)
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) {
            fileURL = containerURL.appendingPathComponent("sync_log.txt")
        } else {
            fileURL = nil
        }
    }

    func append(_ message: String, level: LogLevel, category: LogCategory) {
        guard let fileURL else { return }
        queue.async { [dateFormatter] in
            let timestamp = dateFormatter.string(from: Date())
            let levelTag = level.rawValue.uppercased()
            let line = "\(timestamp) [\(levelTag)|\(category.rawValue)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: fileURL)
            }

            self.rotateIfNeeded()
        }
    }

    /// Returns all log contents. Call from any thread.
    func readAll() -> String {
        guard let fileURL else { return "" }
        return queue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
    }

    /// Returns the last N lines.
    func readTail(lines lineCount: Int = 200) -> String {
        let content = readAll()
        guard !content.isEmpty else { return "" }
        let allLines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let tail = allLines.suffix(lineCount)
        return tail.joined(separator: "\n")
    }

    /// Parses log entries from the file with structured level/category info.
    func readStructuredEntries(maxLines: Int = 500) -> [LogEntry] {
        let content = readTail(lines: maxLines)
        guard !content.isEmpty else { return [] }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        return lines.compactMap { line in
            // Format: "HH:mm:ss.SSS [LEVEL|category] message"
            // Also supports legacy format without brackets
            guard line.count > 13 else { return nil }
            let timestamp = String(line.prefix(12))

            // Try to parse structured format
            let afterTimestamp = String(line.dropFirst(13)) // skip "HH:mm:ss.SSS "
            if afterTimestamp.hasPrefix("["),
               let closeBracket = afterTimestamp.firstIndex(of: "]")
            {
                let bracketContent = afterTimestamp[
                    afterTimestamp.index(after: afterTimestamp.startIndex)..<closeBracket
                ]
                let parts = bracketContent.split(separator: "|", maxSplits: 1)
                if parts.count == 2 {
                    let levelStr = String(parts[0]).lowercased()
                    let categoryStr = String(parts[1])
                    let level = LogLevel(rawValue: levelStr) ?? .info
                    let category = LogCategory(rawValue: categoryStr) ?? .sync
                    let messageStart = afterTimestamp.index(after: closeBracket)
                    let message = String(afterTimestamp[messageStart...]).trimmingCharacters(in: .whitespaces)
                    return LogEntry(timestamp: timestamp, level: level, category: category, message: message)
                }
            }

            // Legacy format fallback — treat as sync/info (or sync/warning/error based on prefix)
            var level: LogLevel = .info
            var message = afterTimestamp
            if message.hasPrefix("[ERROR] ") {
                level = .error
                message = String(message.dropFirst(8))
            } else if message.hasPrefix("[WARN] ") {
                level = .warning
                message = String(message.dropFirst(7))
            }
            return LogEntry(timestamp: timestamp, level: level, category: .sync, message: message)
        }
    }

    /// Clears all log content.
    func clear() {
        guard let fileURL else { return }
        queue.async {
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Writes a marker line (e.g., after upload) so the file isn't completely empty.
    func writeMarker(_ message: String) {
        append(message, level: .info, category: .sync)
    }

    private func rotateIfNeeded() {
        guard let fileURL else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > maxFileSize
        else { return }

        // Keep only the last half
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n")
            let halfIndex = lines.count / 2
            let trimmed = lines.suffix(from: halfIndex).joined(separator: "\n")
            try? trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
