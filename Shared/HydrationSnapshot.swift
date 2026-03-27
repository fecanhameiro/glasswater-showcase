//
//  HydrationSnapshot.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

enum HydrationSnapshotSource: String, Codable, CaseIterable, Sendable {
    case app
    case widget
    case liveActivity
    case watch
    case notification
    case background
    case health
    case siri
    case unknown
}

struct HydrationSnapshot: Codable, Equatable, Sendable {
    let updatedAt: Date
    let dayStart: Date
    let totalMl: Int
    let goalMl: Int
    let progress: Double
    let remainingMl: Int
    let goalReached: Bool
    let lastIntakeMl: Int?
    let lastIntakeDate: Date?
    let customAmountMl: Int
    let source: HydrationSnapshotSource
}
