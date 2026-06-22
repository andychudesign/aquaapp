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

    /// Presents the HealthKit authorization sheet during onboarding Step 3 and
    /// marks the permission UX as handled so sip paths no longer request auth.
    static func completeOnboardingAuthorization() async {
        guard isAvailable else {
            SharedStorage.markHealthKitAuthResolved()
            return
        }
        _ = await requestAuthorizationIfNeeded()
        SharedStorage.markHealthKitAuthResolved()
    }

    /// Saves a single sip to HealthKit using the current per-sip volume.
    /// - Parameter requestAuth: Pass `true` only for the legacy first-sip path
    ///   (pre-v1.5 upgraders). New users grant access in onboarding Step 3;
    ///   all routine sip paths pass `false`.
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
