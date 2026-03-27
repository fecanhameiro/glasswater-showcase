//
//  GlassWaterWidgetConfigurationIntent.swift
//  GlassWaterWidgetExtension
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import AppIntents
import Foundation

struct GlassWaterWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget_configuration_title"
    static var description = IntentDescription(LocalizedStringResource("widget_configuration_description"))
}
