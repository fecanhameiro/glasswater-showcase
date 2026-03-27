//
//  HealthKitService.swift
//  GlassWater
//
//  Created by Felipe Canhameiro on 18/01/26.
//

import Foundation
import HealthKit

protocol HealthKitServicing {
    func isHealthDataAvailable() -> Bool
    func authorizationStatus() async -> HealthAccessStatus
    func requestAuthorization() async throws -> HealthAccessStatus
    func fetchWaterSamples(from startDate: Date, to endDate: Date) async throws -> [HealthWaterSample]
    func fetchWaterIntake(from startDate: Date, to endDate: Date) async throws -> Int
    func fetchDailyIntake(from startDate: Date, to endDate: Date, calendar: Calendar) async throws -> [Date: Int]
    func saveWaterIntake(amountMl: Int, date: Date) async throws -> UUID
    func deleteWaterSample(id: UUID) async throws
    func startObservingWaterChanges(onUpdate: @escaping () -> Void) async
    func stopObservingWaterChanges() async
}

struct HealthWaterSample: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let amountMl: Int
}

final class HealthKitService: HealthKitServicing {
    private let healthStore = HKHealthStore()
    private let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater)
    private let unit = HKUnit.literUnit(with: .milli)
    private var observerQuery: HKObserverQuery?
    private let anchorStorage: UserDefaults
    private let anchorKey = "healthkit.water.anchor"
    private let observerLookbackDays = 14

    init(anchorStorage: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupIdentifier)) {
        if anchorStorage == nil {
            AppLog.warning("HealthKit anchor using standard UserDefaults — App Group unavailable, anchors may be lost on reinstall", category: .health)
        }
        self.anchorStorage = anchorStorage ?? .standard
    }

    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationStatus() async -> HealthAccessStatus {
        guard isHealthDataAvailable(), let waterType else { return .unknown }
        return mapAuthorizationStatus(healthStore.authorizationStatus(for: waterType))
    }

    func requestAuthorization() async throws -> HealthAccessStatus {
        guard isHealthDataAvailable(), let waterType else {
            AppLog.warning("HealthKit not available on this device", category: .health)
            return .unknown
        }
        let status: HealthAccessStatus = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HealthAccessStatus, Error>) in
            healthStore.requestAuthorization(toShare: [waterType], read: [waterType]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = self.mapAuthorizationStatus(self.healthStore.authorizationStatus(for: waterType))
                continuation.resume(returning: status)
            }
        }
        AppLog.info("HealthKit authorization result: \(String(describing: status))", category: .health)
        return status
    }

    func fetchWaterSamples(from startDate: Date, to endDate: Date) async throws -> [HealthWaterSample] {
        guard isHealthDataAvailable(), let waterType else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (samples as? [HKQuantitySample] ?? []).map { sample in
                    let value = sample.quantity.doubleValue(for: self.unit)
                    return HealthWaterSample(
                        id: sample.uuid,
                        date: sample.startDate,
                        amountMl: Int(value.rounded())
                    )
                }
                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }

    func fetchWaterIntake(from startDate: Date, to endDate: Date) async throws -> Int {
        guard isHealthDataAvailable(), let waterType else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let query = HKStatisticsQuery(
                quantityType: waterType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let quantity = result?.sumQuantity()
                let value = quantity?.doubleValue(for: self.unit) ?? 0
                continuation.resume(returning: Int(value.rounded()))
            }
            healthStore.execute(query)
        }
    }

    func fetchDailyIntake(from startDate: Date, to endDate: Date, calendar: Calendar) async throws -> [Date: Int] {
        guard isHealthDataAvailable(), let waterType else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let anchorDate = calendar.startOfDay(for: startDate)
        var interval = DateComponents()
        interval.day = 1

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Date: Int], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: waterType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var totals: [Date: Int] = [:]
                if let collection {
                    collection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                        let value = statistics.sumQuantity()?.doubleValue(for: self.unit) ?? 0
                        let day = calendar.startOfDay(for: statistics.startDate)
                        totals[day] = Int(value.rounded())
                    }
                }

                continuation.resume(returning: totals)
            }
            healthStore.execute(query)
        }
    }

    func saveWaterIntake(amountMl: Int, date: Date) async throws -> UUID {
        guard isHealthDataAvailable(), let waterType else { throw HealthKitError.unavailable }
        let quantity = HKQuantity(unit: unit, doubleValue: Double(amountMl))
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: date, end: date)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
        AppLog.info("Saved water intake: \(amountMl)ml to HealthKit (id: \(sample.uuid))", category: .health)
        return sample.uuid
    }

    func deleteWaterSample(id: UUID) async throws {
        guard isHealthDataAvailable(), let waterType else { return }
        AppLog.info("Deleting HealthKit water sample: \(id)", category: .health)
        let predicate = HKQuery.predicateForObjects(with: [id])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let query = HKSampleQuery(
                sampleType: waterType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: ())
                    return
                }
                self.healthStore.delete(sample) { _, deleteError in
                    if let deleteError {
                        continuation.resume(throwing: deleteError)
                        return
                    }
                    continuation.resume(returning: ())
                }
            }
            healthStore.execute(query)
        }
    }

    func startObservingWaterChanges(onUpdate: @escaping () -> Void) async {
        guard isHealthDataAvailable(), let waterType else { return }
        guard observerQuery == nil else {
            AppLog.info("Observer query already active, skipping", category: .health)
            return
        }
        AppLog.info("Starting HealthKit water observer query", category: .health)

        let query = HKObserverQuery(sampleType: waterType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self else {
                completionHandler()
                return
            }
            if let error {
                AppLog.error("HealthKit observer query error: \(error.localizedDescription)", category: .health)
                completionHandler()
                return
            }

            Task {
                await self.handleObserverUpdate(onUpdate: onUpdate)
                completionHandler()
            }
        }
        observerQuery = query
        healthStore.execute(query)

        await withCheckedContinuation { continuation in
            healthStore.enableBackgroundDelivery(for: waterType, frequency: .immediate) { success, error in
                if let error {
                    AppLog.error("Failed to enable HealthKit background delivery: \(error.localizedDescription)", category: .health)
                } else if !success {
                    AppLog.warning("HealthKit background delivery not enabled (success=false)", category: .health)
                }
                continuation.resume()
            }
        }
    }

    func stopObservingWaterChanges() async {
        guard isHealthDataAvailable(), let waterType else { return }
        AppLog.info("Stopping HealthKit water observer query", category: .health)
        if let observerQuery {
            healthStore.stop(observerQuery)
            self.observerQuery = nil
        }

        await withCheckedContinuation { continuation in
            healthStore.disableBackgroundDelivery(for: waterType) { _, _ in
                continuation.resume()
            }
        }
    }

    private func handleObserverUpdate(onUpdate: @escaping () -> Void) async {
        guard let waterType else { return }
        SyncLog.info("[Sync] HK observer fired — running anchored query")
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -observerLookbackDays, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil)
        do {
            let hasChanges = try await runAnchoredQuery(sampleType: waterType, predicate: predicate)
            if hasChanges {
                SyncLog.info("[Sync] HK observer — changes detected, calling onUpdate")
                onUpdate()
            } else {
                SyncLog.info("[Sync] HK observer — no changes (anchor up to date)")
            }
        } catch {
            SyncLog.error("[Sync] HK observer — anchored query failed: \(error.localizedDescription)")
            return
        }
    }

    private func runAnchoredQuery(sampleType: HKSampleType, predicate: NSPredicate?) async throws -> Bool {
        let anchor = loadAnchor()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let newAnchor {
                    self?.saveAnchor(newAnchor)
                }
                let addedCount = samples?.count ?? 0
                let deletedCount = deletedObjects?.count ?? 0
                let hasSamples = addedCount > 0
                let hasDeletions = deletedCount > 0
                if hasSamples || hasDeletions {
                    SyncLog.info("[Sync] HK anchoredQuery — added=\(addedCount), deleted=\(deletedCount)")
                }
                continuation.resume(returning: hasSamples || hasDeletions)
            }
            healthStore.execute(query)
        }
    }

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = anchorStorage.data(forKey: anchorKey) else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        } catch {
            AppLog.error("Failed to load HealthKit anchor: \(error.localizedDescription)", category: .health)
            return nil
        }
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
            anchorStorage.set(data, forKey: anchorKey)
        } catch {
            AppLog.error("Failed to save HealthKit anchor: \(error.localizedDescription)", category: .health)
        }
    }

    private func mapAuthorizationStatus(_ status: HKAuthorizationStatus) -> HealthAccessStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .denied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .unknown
        }
    }
}

private enum HealthKitError: Error {
    case unavailable
}
