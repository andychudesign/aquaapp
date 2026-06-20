//
//  SipIntents.swift
//  aqua
//
//  Shared between the main app and widget extension targets.
//

import AppIntents
import WidgetKit

/// Foreground intent used by the widget when HealthKit authorization hasn't been
/// resolved yet. Opens the app so the system can present the authorization sheet,
/// logs the sip, and marks auth as resolved for future background saves.
struct LogWaterAuthIntent: AppIntent {
    static let title: LocalizedStringResource = "I drank water"
    static let openAppWhenRun: Bool = true

    private static let appGroupID = "group.andychudesign.Aqua"

    func perform() async throws -> some IntentResult {
        SharedStorage.recordSip()

        await HealthKitManager.saveSip(requestAuth: true)
        let suite = UserDefaults(suiteName: Self.appGroupID)
        suite?.set(true, forKey: "healthKitAuthResolved")

        // Reload each kind exactly once. See `LogWaterIntent.perform()` for
        // why the redundant `reloadAllTimelines()` + duplicate per-kind calls
        // were removed: they over-charged WidgetKit's per-widget reload
        // budget and starved the lock-screen (accessory) widgets, leaving
        // them frozen after multiple sips / with multiple widgets installed.
        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
        return .result()
    }
}
