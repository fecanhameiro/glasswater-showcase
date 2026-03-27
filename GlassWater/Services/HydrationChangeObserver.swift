//
//  HydrationChangeObserver.swift
//  GlassWater
//

import Foundation

/// Observes Darwin notifications posted by widget extensions, Live Activity intents,
/// and other processes when hydration data changes. Triggers a callback so the main
/// app can refresh Live Activity, widgets, and in-app UI.
@MainActor
final class HydrationChangeObserver {
    private let onChanged: @MainActor () async -> Void
    private var isObserving = false

    init(onChanged: @escaping @MainActor () async -> Void) {
        self.onChanged = onChanged
    }

    deinit {
        guard isObserving else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, pointer, _, _, _ in
                guard let pointer else { return }
                let self_ = Unmanaged<HydrationChangeObserver>.fromOpaque(pointer)
                    .takeUnretainedValue()
                SyncLog.info("[Sync] Darwin notification RECEIVED — com.glasswater.hydrationChanged")
                Task { @MainActor in
                    await self_.onChanged()
                    SyncLog.info("[Sync] Darwin notification — onChanged handler completed")
                }
            },
            HydrationChangeNotifier.name.rawValue,
            nil,
            .deliverImmediately
        )
        SyncLog.info("[Sync] Started observing Darwin hydration change notifications")
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, observer, HydrationChangeNotifier.name, nil)
        AppLog.info("Stopped observing hydration change notifications", category: .sync)
    }
}
