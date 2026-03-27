//
//  CrashReportingService.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import FirebaseCrashlytics
import Foundation

protocol CrashReporting {
    func record(error: Error)
    func log(_ message: String)
    func setCustomValue(_ value: Any, forKey key: String)
}

final class NoopCrashReportingService: CrashReporting {
    func record(error: Error) {
    }

    func log(_ message: String) {
    }

    func setCustomValue(_ value: Any, forKey key: String) {
    }
}

final class FirebaseCrashReportingService: CrashReporting {
    private let crashlytics = Crashlytics.crashlytics()

    func record(error: Error) {
        crashlytics.record(error: error)
    }

    func log(_ message: String) {
        crashlytics.log(message)
    }

    func setCustomValue(_ value: Any, forKey key: String) {
        crashlytics.setCustomValue(value, forKey: key)
    }
}
