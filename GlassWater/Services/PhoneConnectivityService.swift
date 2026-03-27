//
//  PhoneConnectivityService.swift
//  GlassWater
//
//  WatchConnectivity service for iOS side.
//  Receives commands from watch, replies with authoritative WatchState.
//  Pushes WatchState to watch via applicationContext after phone-side changes.
//

import Foundation
import WatchConnectivity

// MARK: - Protocol

@MainActor
protocol PhoneConnectivityServicing {
    func sendState(_ state: WatchState)
    func sendSettings(goalMl: Int, customAmountMl: Int)
    var onCommandReceived: (@MainActor (WatchCommand, @escaping (WatchState?) -> Void) -> Void)? { get set }
}

// MARK: - Implementation

final class PhoneConnectivityService: NSObject, PhoneConnectivityServicing, @unchecked Sendable {
    @MainActor var onCommandReceived: (@MainActor (WatchCommand, @escaping (WatchState?) -> Void) -> Void)?

    private let session: WCSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: WCSession = .default) {
        self.session = session
        super.init()
        guard WCSession.isSupported() else {
            AppLog.info("WCSession not supported on this device", category: .watch)
            return
        }
        session.delegate = self
        session.activate()
    }

    @MainActor
    func sendState(_ state: WatchState) {
        guard session.activationState == .activated, session.isPaired else {
            let activated = session.activationState == .activated
            let paired = session.isPaired
            SyncLog.info("[Sync] sendState SKIPPED — activated=\(activated), paired=\(paired), totalMl=\(state.totalMl)")
            return
        }

        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            SyncLog.error("[Sync] sendState — encode failed: \(error.localizedDescription)")
            return
        }

        let context: [String: Any] = ["watchState": data]

        do {
            try session.updateApplicationContext(context)
            SyncLog.info("[Sync] sendState — sent to watch via applicationContext: totalMl=\(state.totalMl), goalMl=\(state.goalMl), entries=\(state.entries.count)")
        } catch {
            SyncLog.error("[Sync] sendState — updateApplicationContext failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    func sendSettings(goalMl: Int, customAmountMl: Int) {
        // Settings are now included in WatchState pushes,
        // but we keep this for immediate settings-only updates
        guard session.activationState == .activated, session.isPaired else { return }
        let state = buildMinimalSettingsState(goalMl: goalMl, customAmountMl: customAmountMl)
        sendState(state)
    }

    private func buildMinimalSettingsState(goalMl: Int, customAmountMl: Int) -> WatchState {
        // When only settings changed, send a state with current values
        // The watch will merge settings but keep its cached total + entries
        WatchState(
            updatedAt: .now,
            dayStart: Calendar.autoupdatingCurrent.startOfDay(for: .now),
            totalMl: -1, // sentinel: watch ignores total when -1
            goalMl: goalMl,
            progress: -1,
            remainingMl: -1,
            goalReached: false,
            customAmountMl: customAmountMl,
            volumeUnit: VolumeFormatters.currentUnit.rawValue,
            entries: [],
            processedCommandIds: []
        )
    }

    // MARK: - Command Processing

    private func handleCommand(from messageOrUserInfo: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let data = messageOrUserInfo["watchCommand"] as? Data else {
            SyncLog.info("[Sync] Received message without watchCommand — keys: \(messageOrUserInfo.keys.joined(separator: ", "))")
            return
        }

        let command: WatchCommand
        do {
            command = try decoder.decode(WatchCommand.self, from: data)
        } catch {
            SyncLog.error("[Sync] Failed to decode WatchCommand: \(error.localizedDescription)")
            replyHandler?([:])
            return
        }

        let latency = Date.now.timeIntervalSince(command.sentAt)
        SyncLog.info("[Sync] Received WatchCommand — action=\(command.action.rawValue), id=\(command.id), latency=\(String(format: "%.1f", latency))s")

        Task { @MainActor in
            self.onCommandReceived?(command) { [weak self] state in
                guard let self, let state else {
                    replyHandler?([:])
                    return
                }

                if let replyHandler {
                    do {
                        let stateData = try self.encoder.encode(state)
                        replyHandler(["watchState": stateData])
                        SyncLog.info("[Sync] Replied to command \(command.id) with WatchState — totalMl=\(state.totalMl)")
                    } catch {
                        SyncLog.error("[Sync] Failed to encode reply WatchState: \(error.localizedDescription)")
                        replyHandler([:])
                    }
                } else {
                    // transferUserInfo path — push state via applicationContext
                    self.sendState(state)
                    SyncLog.info("[Sync] Pushed WatchState via applicationContext after command \(command.id)")
                }
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityService: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            AppLog.error("WCSession activation failed: \(error.localizedDescription)", category: .watch)
        } else {
            AppLog.info("WCSession activated: \(activationState.rawValue)", category: .watch)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        AppLog.info("WCSession became inactive", category: .watch)
    }

    func sessionDidDeactivate(_ session: WCSession) {
        AppLog.info("WCSession deactivated, reactivating", category: .watch)
        session.activate()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        SyncLog.info("[Sync] didReceiveApplicationContext — keys=\(applicationContext.keys.joined(separator: ", "))")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        SyncLog.info("[Sync] didReceiveMessage (no reply) — keys=\(message.keys.joined(separator: ", "))")
        handleCommand(from: message, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        SyncLog.info("[Sync] didReceiveMessage (with reply) — keys=\(message.keys.joined(separator: ", "))")
        handleCommand(from: message, replyHandler: replyHandler)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        SyncLog.info("[Sync] didReceiveUserInfo — keys=\(userInfo.keys.joined(separator: ", "))")
        handleCommand(from: userInfo, replyHandler: nil)
    }
}
