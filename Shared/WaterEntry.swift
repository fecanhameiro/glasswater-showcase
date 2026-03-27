//
//  WaterEntry.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import SwiftData

@Model
final class WaterEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var amountMl: Int = 0
    var isFromHealth: Bool = false
    var healthSampleId: UUID?

    init(
        date: Date = Date.now,
        amountMl: Int,
        isFromHealth: Bool = false,
        healthSampleId: UUID? = nil
    ) {
        self.date = date
        self.amountMl = amountMl
        self.isFromHealth = isFromHealth
        self.healthSampleId = healthSampleId
    }
}
