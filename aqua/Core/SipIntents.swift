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
    private static let hydrationDuration: TimeInterval = 7200

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: Self.appGroupID)

        let previousLevel: Double
        if let logTime = suite?.object(forKey: "lastWaterLogTime") as? Date {
            let elapsed = Date().timeIntervalSince(logTime)
            previousLevel = max(0, min(1, 1 - elapsed / Self.hydrationDuration))
        } else {
            previousLevel = 0
        }
        suite?.set(previousLevel, forKey: "fillStartLevel")
        suite?.set(Date(), forKey: "lastWaterLogTime")

        await HealthKitManager.saveSip(requestAuth: true)
        suite?.set(true, forKey: "healthKitAuthResolved")

        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
        return .result()
    }
}
