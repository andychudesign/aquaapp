//
//  HealthKitManager.swift
//  aqua
//

import HealthKit

enum HealthKitManager {
    private static let store = HKHealthStore()
    private static let waterType = HKQuantityType(.dietaryWater)
    private static var sipVolume: HKQuantity {
        let suite = UserDefaults(suiteName: "group.andychudesign.Aqua")
        let stored = suite?.integer(forKey: "sipVolumeML") ?? 0
        let ml = stored > 0 ? stored : 70
        return HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(ml))
    }

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

    /// Saves a single sip (70 mL) to HealthKit.
    /// - Parameter requestAuth: `true` (default) triggers the system authorization
    ///   sheet on first call — use from the main app. Pass `false` from widget
    ///   extensions that cannot present UI; relies on authorization already granted
    ///   in the main app.
    @discardableResult
    static func saveSip(requestAuth: Bool = true) async -> Bool {
        guard isAvailable else { return false }
        if requestAuth {
            _ = await requestAuthorizationIfNeeded()
        }

        let now = Date()
        let sample = HKQuantitySample(
            type: waterType,
            quantity: sipVolume,
            start: now,
            end: now
        )

        do {
            try await store.save(sample)
            return true
        } catch {
            return false
        }
    }
}
