//
//  HealthKitManager.swift
//  aqua
//

import HealthKit

@MainActor
enum HealthKitManager {
    private static let store = HKHealthStore()
    private static let waterType = HKQuantityType(.dietaryWater)
    private static let sipVolume = HKQuantity(unit: .literUnit(with: .milli), doubleValue: 100)

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Requests write-only authorization for dietary water.
    /// Safe to call multiple times — HealthKit no-ops if already determined.
    static func requestAuthorizationIfNeeded() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [waterType], read: [])
            return true
        } catch {
            return false
        }
    }

    /// Saves a single sip (100 mL) to HealthKit.
    /// Requests authorization on first call, then writes silently.
    static func saveSip() async {
        guard await requestAuthorizationIfNeeded() else { return }

        let sample = HKQuantitySample(
            type: waterType,
            quantity: sipVolume,
            start: Date(),
            end: Date()
        )

        do {
            try await store.save(sample)
        } catch {
            // Non-critical — don't block the UI for a HealthKit failure
        }
    }
}
