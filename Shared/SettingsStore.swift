//
//  SettingsStore.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

@MainActor
protocol SettingsStore {
    func loadOrCreate() throws -> UserSettings
    func save() throws
    func invalidateCache()
}
