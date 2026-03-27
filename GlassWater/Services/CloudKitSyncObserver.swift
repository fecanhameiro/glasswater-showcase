//
//  CloudKitSyncObserver.swift
//  GlassWater
//
//  Observes NSPersistentStoreRemoteChange notifications from CloudKit sync.
//  When remote data arrives, triggers a snapshot broadcast to update widgets/LA.
//

import CoreData
import Foundation

// MARK: - Protocol

@MainActor
protocol CloudKitSyncObserving {
    func startObserving()
}

// MARK: - Implementation

@MainActor
final class CloudKitSyncObserver: CloudKitSyncObserving {
    private let onRemoteChange: @MainActor () async -> Void
    private var observationTask: Any?
    private var debounceTask: Task<Void, Never>?

    init(onRemoteChange: @escaping @MainActor () async -> Void) {
        self.onRemoteChange = onRemoteChange
    }

    func startObserving() {
        observationTask = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleDebounce()
            }
        }
    }

    /// Coalesces rapid CloudKit notifications (e.g., full re-sync after token expiry).
    /// Uses trailing-edge debounce: waits for notifications to stop arriving, then fires once.
    private func scheduleDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            // Wait 3 seconds of silence — CloudKit batch imports fire every ~1s,
            // so this ensures we process AFTER the batch is done, not during.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            AppLog.info("Remote CloudKit change detected (debounced)", category: .cloudKit)
            await onRemoteChange()
        }
    }
}

// MARK: - Preview

@MainActor
final class PreviewCloudKitSyncObserver: CloudKitSyncObserving {
    func startObserving() {}
}
