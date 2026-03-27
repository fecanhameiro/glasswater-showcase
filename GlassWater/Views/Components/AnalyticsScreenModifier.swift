//
//  AnalyticsScreenModifier.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 08/02/26.
//

import SwiftUI

struct AnalyticsScreenModifier: ViewModifier {
    let screenName: String
    let analytics: any AnalyticsTracking

    func body(content: Content) -> some View {
        content
            .onAppear {
                analytics.logScreenView(screenName: screenName)
            }
    }
}

extension View {
    func trackScreen(_ screenName: String, analytics: any AnalyticsTracking) -> some View {
        modifier(AnalyticsScreenModifier(screenName: screenName, analytics: analytics))
    }
}
