//
//  AppServices+HealthBackfill.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation

@MainActor
extension AppServices {
    func backfillPendingHealthEntries() async {
        let status = await healthService.authorizationStatus()
        guard status == .authorized else { return }

        do {
            let pending = try waterStore.entriesMissingHealthSample()
            guard !pending.isEmpty else { return }
            for entry in pending {
                do {
                    let sampleId = try await healthService.saveWaterIntake(
                        amountMl: entry.amountMl,
                        date: entry.date
                    )
                    try waterStore.updateEntry(
                        entry,
                        amountMl: entry.amountMl,
                        date: entry.date,
                        isFromHealth: true,
                        healthSampleId: sampleId
                    )
                } catch {
                    crashReporter.record(error: error)
                }
            }
        } catch {
            crashReporter.record(error: error)
        }
    }
}
