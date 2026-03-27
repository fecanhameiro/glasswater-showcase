//
//  WidgetReloadCoordinator.swift
//  GlassWater
//
//  Centralizes WidgetKit timeline reload calls to prevent budget exhaustion.
//  WidgetKit throttles apps that call reloadTimelines too frequently.
//  This coordinator ensures at most one reload per `minimumInterval` window,
//  with a guaranteed deferred reload if requests arrive during cooldown.
//

import Foundation
import WidgetKit

@MainActor
final class WidgetReloadCoordinator {
    static let shared = WidgetReloadCoordinator()

    private let minimumInterval: TimeInterval = 30
    private var lastReloadDate: Date?
    private var deferredTask: Task<Void, Never>?

    private init() {}

    /// Force an immediate widget reload, bypassing the cooldown.
    /// Use for critical state transitions (goal reached/un-reached).
    func forceReload(source: String = "") {
        SyncLog.info("[Sync][WidgetReload] FORCED — source=\(source)")
        performReload(source: "\(source)(forced)")
    }

    /// Request a widget timeline reload. If called too frequently,
    /// the reload is deferred to the end of the cooldown window.
    func requestReload(source: String = "") {
        let now = Date()

        if let lastReloadDate,
           now.timeIntervalSince(lastReloadDate) < minimumInterval
        {
            let remaining = minimumInterval - now.timeIntervalSince(lastReloadDate)
            SyncLog.info("[Sync][WidgetReload] Deferred — source=\(source), cooldown=\(String(format: "%.1f", remaining))s remaining")
            scheduleDeferredReload(after: remaining, source: source)
            return
        }

        performReload(source: source)
    }

    private func scheduleDeferredReload(after delay: TimeInterval, source: String) {
        // Only one deferred reload at a time — the latest snapshot is always
        // already saved to App Group, so the deferred reload will pick it up
        guard deferredTask == nil else { return }
        let delayNs = UInt64(max(delay, 0.1) * 1_000_000_000)
        deferredTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            performReload(source: "\(source)(deferred)")
        }
    }

    private func performReload(source: String) {
        deferredTask?.cancel()
        deferredTask = nil
        lastReloadDate = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: AppConstants.widgetKind)
        SyncLog.info("[Sync][WidgetReload] Reloaded — source=\(source), kind=\"\(AppConstants.widgetKind)\"")
    }
}
