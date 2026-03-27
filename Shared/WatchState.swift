//
//  WatchState.swift
//  GlassWater
//
//  Authoritative state sent from phone to watch.
//  The phone (SwiftData) is the single source of truth.
//

import Foundation

struct WatchState: Codable, Sendable {
    let updatedAt: Date
    let dayStart: Date
    let totalMl: Int
    let goalMl: Int
    let progress: Double
    let remainingMl: Int
    let goalReached: Bool
    let customAmountMl: Int
    let volumeUnit: String?
    let entries: [WatchStateEntry]
    let processedCommandIds: [UUID]
}

struct WatchStateEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let amountMl: Int
    let date: Date
}
