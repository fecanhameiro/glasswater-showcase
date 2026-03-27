//
//  Date+Helpers.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

extension Date {
    func addingDays(_ days: Int, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(byAdding: .day, value: days, to: self) ?? self
    }
}
