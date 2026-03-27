//
//  AnalyticsService.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 08/02/26.
//

import FirebaseAnalytics
import Foundation

protocol AnalyticsTracking {
    func logEvent(_ name: String, parameters: [String: Any]?)
    func setUserProperty(_ value: String?, forName name: String)
    func logScreenView(screenName: String)
}

final class FirebaseAnalyticsService: AnalyticsTracking {
    func logEvent(_ name: String, parameters: [String: Any]?) {
        Analytics.logEvent(name, parameters: parameters)
    }

    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    func logScreenView(screenName: String) {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName
        ])
    }
}

final class NoopAnalyticsService: AnalyticsTracking {
    func logEvent(_ name: String, parameters: [String: Any]?) {}
    func setUserProperty(_ value: String?, forName name: String) {}
    func logScreenView(screenName: String) {}
}
