//
//  WatchCommand.swift
//  GlassWater
//
//  Command sent from watch to phone for hydration actions.
//  The phone processes the command and replies with authoritative WatchState.
//

import Foundation

struct WatchCommand: Codable, Sendable {
    enum Action: String, Codable, Sendable {
        case add
        case delete
        case undoAdd
        case getState
        case setCustomAmount
    }

    let id: UUID
    let action: Action
    let amountMl: Int?
    let date: Date?
    let entryId: UUID?
    let sentAt: Date

    static func add(amountMl: Int, date: Date = .now) -> WatchCommand {
        WatchCommand(
            id: UUID(),
            action: .add,
            amountMl: amountMl,
            date: date,
            entryId: nil,
            sentAt: .now
        )
    }

    static func delete(entryId: UUID, amountMl: Int) -> WatchCommand {
        WatchCommand(
            id: UUID(),
            action: .delete,
            amountMl: amountMl,
            date: nil,
            entryId: entryId,
            sentAt: .now
        )
    }

    /// Undo a previously-sent add command.
    /// `originalCommandId` is the id of the WatchCommand.add that should be reversed.
    /// The phone finds the entry via `healthSampleId == originalCommandId`.
    static func undoAdd(originalCommandId: UUID, amountMl: Int) -> WatchCommand {
        WatchCommand(
            id: UUID(),
            action: .undoAdd,
            amountMl: amountMl,
            date: nil,
            entryId: originalCommandId,
            sentAt: .now
        )
    }

    static func getState() -> WatchCommand {
        WatchCommand(
            id: UUID(),
            action: .getState,
            amountMl: nil,
            date: nil,
            entryId: nil,
            sentAt: .now
        )
    }

    static func setCustomAmount(_ amountMl: Int) -> WatchCommand {
        WatchCommand(
            id: UUID(),
            action: .setCustomAmount,
            amountMl: amountMl,
            date: nil,
            entryId: nil,
            sentAt: .now
        )
    }
}
