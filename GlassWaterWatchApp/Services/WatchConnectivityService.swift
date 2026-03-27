//
//  WatchConnectivityService.swift
//  GlassWaterWatchApp
//
//  WatchConnectivity service for watchOS side.
//  Sends commands to phone, receives authoritative WatchState back.
//

import Foundation
import WatchConnectivity

// MARK: - Protocol

@MainActor
protocol WatchConnectivityServicing {
    func sendCommand(_ command: WatchCommand, onReply: (@MainActor (WatchState) -> Void)?)
    func requestState()
    var onStateReceived: (@MainActor (WatchState) -> Void)? { get set }
}

// MARK: - Implementation

final class WatchConnectivityService: NSObject, WatchConnectivityServicing, @unchecked Sendable {
    @MainActor var onStateReceived: (@MainActor (WatchState) -> Void)?

    private let session: WCSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let pendingCommandsKey = "pendingWatchCommands"

    init(session: WCSession = .default) {
        self.session = session
        super.init()
        guard WCSession.isSupported() else {
            AppLog.info("WCSession not supported", category: .watch)
            return
        }
        session.delegate = self
        session.activate()
    }

    @MainActor
    func sendCommand(_ command: WatchCommand, onReply: (@MainActor (WatchState) -> Void)?) {
        guard session.activationState == .activated else {
            SyncLog.info("[Sync] sendCommand — session not activated, queuing for transferUserInfo")
            queueAndTransfer(command)
            return
        }

        if session.isReachable {
            SyncLog.info("[Sync] sendCommand — phone reachable, using sendMessage: action=\(command.action.rawValue), id=\(command.id)")
            do {
                let data = try encoder.encode(command)
                session.sendMessage(["watchCommand": data], replyHandler: { [weak self] reply in
                    self?.handleReply(reply, onReply: onReply)
                }, errorHandler: { [weak self] error in
                    SyncLog.warning("[Sync] sendCommand — sendMessage failed, falling back to transferUserInfo: \(error.localizedDescription)")
                    self?.queueAndTransfer(command)
                })
            } catch {
                SyncLog.error("[Sync] sendCommand — encode failed: \(error.localizedDescription)")
                queueAndTransfer(command)
            }
        } else {
            SyncLog.info("[Sync] sendCommand — phone NOT reachable, using transferUserInfo: action=\(command.action.rawValue), id=\(command.id)")
            queueAndTransfer(command)
        }
    }

    @MainActor
    func requestState() {
        let command = WatchCommand.getState()
        sendCommand(command, onReply: { [weak self] state in
            self?.onStateReceived?(state)
        })
    }

    // MARK: - Reply Handling

    private func handleReply(_ reply: [String: Any], onReply: (@MainActor (WatchState) -> Void)?) {
        guard let data = reply["watchState"] as? Data else {
            SyncLog.info("[Sync] Reply without watchState — keys: \(reply.keys.joined(separator: ", "))")
            return
        }

        do {
            let state = try decoder.decode(WatchState.self, from: data)
            SyncLog.info("[Sync] Received WatchState reply — totalMl=\(state.totalMl), goalMl=\(state.goalMl), entries=\(state.entries.count)")
            Task { @MainActor in
                onReply?(state)
                onStateReceived?(state)
            }
        } catch {
            SyncLog.error("[Sync] Failed to decode WatchState reply: \(error.localizedDescription)")
        }
    }

    // MARK: - Pending Command Queue (for offline/transferUserInfo fallback)

    private func queueAndTransfer(_ command: WatchCommand) {
        do {
            let data = try encoder.encode(command)
            session.transferUserInfo(["watchCommand": data])
            SyncLog.info("[Sync] Queued command via transferUserInfo — action=\(command.action.rawValue), id=\(command.id)")
        } catch {
            AppLog.error("Failed to encode command for transferUserInfo: \(error.localizedDescription)", category: .watch)
        }
    }

    // MARK: - Incoming State

    private func handleReceivedContext(_ context: [String: Any]) {
        guard let data = context["watchState"] as? Data else {
            SyncLog.info("[Sync] Received context without watchState — keys: \(context.keys.joined(separator: ", "))")
            return
        }

        do {
            let state = try decoder.decode(WatchState.self, from: data)
            SyncLog.info("[Sync] Decoded WatchState from phone — totalMl=\(state.totalMl), goalMl=\(state.goalMl), entries=\(state.entries.count), age=\(String(format: "%.1f", Date.now.timeIntervalSince(state.updatedAt)))s")
            Task { @MainActor in
                onStateReceived?(state)
            }
        } catch {
            SyncLog.error("[Sync] Failed to decode WatchState from phone: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
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

        // Apply any pending context from phone
        if activationState == .activated {
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                handleReceivedContext(context)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        SyncLog.info("[Sync] didReceiveApplicationContext from phone — keys=\(applicationContext.keys.joined(separator: ", "))")
        handleReceivedContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        SyncLog.info("[Sync] didReceiveMessage from phone — keys=\(message.keys.joined(separator: ", "))")
        handleReceivedContext(message)
    }
}
