//
//  LogUploadService.swift
//  GlassWater
//
//  Uploads structured app logs to Firestore on app open.
//  Extracts inline upload logic from GlassWaterApp.swift.
//
//  Target membership: iOS app only (imports Firebase).
//

import FirebaseFirestore
import Foundation
import UIKit

// MARK: - Protocol

protocol LogUploading {
    func uploadIfNeeded() async
}

// MARK: - Firestore Implementation

final class FirestoreLogUploadService: LogUploading {
    private let collectionName = "app_logs"

    func uploadIfNeeded() async {
        let entries = AppLogFile.shared.readStructuredEntries(maxLines: 500)
        guard !entries.isEmpty else { return }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVersion = UIDevice.current.systemVersion

        let errorCount = entries.filter { $0.level == .error }.count
        let warningCount = entries.filter { $0.level == .warning }.count
        let categories = Array(Set(entries.map(\.category.rawValue))).sorted()

        let firstTimestamp = entries.first?.timestamp ?? ""
        let lastTimestamp = entries.last?.timestamp ?? ""

        let serializedEntries: [[String: String]] = entries.map { entry in
            [
                "t": entry.timestamp,
                "l": entry.level.rawValue,
                "c": entry.category.rawValue,
                "m": entry.message,
            ]
        }

        let document: [String: Any] = [
            "deviceId": deviceId,
            "timestamp": FieldValue.serverTimestamp(),
            "sessionStart": firstTimestamp,
            "sessionEnd": lastTimestamp,
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "osVersion": osVersion,
            "lineCount": entries.count,
            "errorCount": errorCount,
            "warningCount": warningCount,
            "categories": categories,
            "entries": serializedEntries,
        ]

        do {
            try await Firestore.firestore().collection(collectionName).addDocument(data: document)
            let lineCount = entries.count
            AppLogFile.shared.clear()
            AppLogFile.shared.writeMarker("--- Uploaded \(lineCount) lines ---")
        } catch {
            AppLog.error("[Upload] Firestore upload failed: \(error.localizedDescription)", category: .sync)
        }
    }
}

// MARK: - Noop (Previews)

final class NoopLogUploadService: LogUploading {
    func uploadIfNeeded() async {}
}
