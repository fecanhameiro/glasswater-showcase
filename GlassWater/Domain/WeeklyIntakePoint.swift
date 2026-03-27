//
//  WeeklyIntakePoint.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

struct WeeklyIntakePoint: Identifiable {
    let date: Date
    let amountMl: Int

    var id: Date { date }
}
