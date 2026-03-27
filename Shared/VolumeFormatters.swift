//
//  VolumeFormatters.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

// MARK: - Volume Unit

enum VolumeUnit: String, Codable, CaseIterable, Sendable {
    case auto
    case ml
    case oz

    var resolved: ResolvedVolumeUnit {
        switch self {
        case .auto:
            return Locale.autoupdatingCurrent.measurementSystem == .metric ? .ml : .oz
        case .ml:
            return .ml
        case .oz:
            return .oz
        }
    }
}

enum ResolvedVolumeUnit: Sendable {
    case ml
    case oz
}

// MARK: - Formatters

enum VolumeFormatters {
    private static let imperialDisplayStepOz = 0.5

    static var currentUnit: VolumeUnit {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier),
              let raw = defaults.string(forKey: AppConstants.appGroupVolumeUnitKey),
              let unit = VolumeUnit(rawValue: raw)
        else {
            return .auto
        }
        return unit
    }

    static func string(fromMl ml: Int, unitStyle: MeasurementFormatter.UnitStyle = .short) -> String {
        let resolved = currentUnit.resolved
        switch resolved {
        case .ml:
            return metricString(fromMl: ml, unitStyle: unitStyle)
        case .oz:
            return imperialString(fromMl: ml, unitStyle: unitStyle)
        }
    }

    private static func metricString(fromMl ml: Int, unitStyle: MeasurementFormatter.UnitStyle) -> String {
        let value = Double(ml)
        let measurement: Measurement<UnitVolume>
        if value >= 1000 {
            measurement = Measurement(value: value / 1000, unit: .liters)
        } else {
            measurement = Measurement(value: value, unit: .milliliters)
        }
        return formatter(for: unitStyle).string(from: measurement)
    }

    private static func imperialString(fromMl ml: Int, unitStyle: MeasurementFormatter.UnitStyle) -> String {
        let rawOz = Measurement(value: Double(ml), unit: UnitVolume.milliliters)
            .converted(to: .fluidOunces)
            .value
        let roundedOz = (rawOz / imperialDisplayStepOz).rounded(.down) * imperialDisplayStepOz
        let flOz = Measurement(value: roundedOz, unit: UnitVolume.fluidOunces)
        return formatter(for: unitStyle).string(from: flOz)
    }

    static func ml(fromFluidOunces fluidOunces: Double) -> Int {
        Int(
            Measurement(value: fluidOunces, unit: UnitVolume.fluidOunces)
                .converted(to: .milliliters)
                .value
                .rounded()
        )
    }

    private static let shortFormatter: MeasurementFormatter = makeFormatter(unitStyle: .short)
    private static let mediumFormatter: MeasurementFormatter = makeFormatter(unitStyle: .medium)

    private static func formatter(for unitStyle: MeasurementFormatter.UnitStyle) -> MeasurementFormatter {
        switch unitStyle {
        case .short:
            return shortFormatter
        case .medium:
            return mediumFormatter
        default:
            return makeFormatter(unitStyle: unitStyle)
        }
    }

    private static func makeFormatter(unitStyle: MeasurementFormatter.UnitStyle) -> MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = unitStyle
        formatter.numberFormatter.maximumFractionDigits = 1
        formatter.numberFormatter.minimumFractionDigits = 0
        formatter.numberFormatter.roundingMode = .down
        return formatter
    }
}
