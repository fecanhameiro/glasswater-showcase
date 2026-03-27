//
//  GlassWaterWidgetExtensionBundle.swift
//  GlassWaterWidgetExtension
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import WidgetKit
import SwiftUI

@main
struct GlassWaterWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        GlassWaterWidget()
        if #available(iOS 16.2, *) {
            GlassWaterLiveActivityWidget()
        }
    }
}
