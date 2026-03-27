//
//  HydrationSnapshotSourceIntent.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

#if canImport(AppIntents)
import AppIntents
import Foundation

enum HydrationSnapshotSourceIntent: String, AppEnum {
    case app
    case widget
    case liveActivity
    case watch
    case notification
    case background
    case health
    case siri
    case unknown

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("intent_add_water_source_title"))
    }

    static var caseDisplayRepresentations: [HydrationSnapshotSourceIntent: DisplayRepresentation] {
        [
            .app: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_app")),
            .widget: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_widget")),
            .liveActivity: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_live_activity")),
            .watch: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_watch")),
            .notification: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_notification")),
            .background: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_background")),
            .health: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_health")),
            .siri: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_siri")),
            .unknown: DisplayRepresentation(title: LocalizedStringResource("intent_add_water_source_unknown"))
        ]
    }

    var snapshotSource: HydrationSnapshotSource {
        HydrationSnapshotSource(rawValue: rawValue) ?? .unknown
    }
}
#endif
