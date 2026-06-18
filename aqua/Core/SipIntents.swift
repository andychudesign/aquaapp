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

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let storedDate = suite?.string(forKey: "todaySipCountDate")
        let isNewDay = storedDate != today
        let currentCount = isNewDay ? 0 : (suite?.integer(forKey: "todaySipCount") ?? 0)
        suite?.set(currentCount + 1, forKey: "todaySipCount")
        suite?.set(today, forKey: "todaySipCountDate")

        let storedVol = suite?.integer(forKey: "sipVolumeML") ?? 0
        let sipML = storedVol > 0 ? storedVol : 70
        let previousVolume: Int
        if isNewDay {
            previousVolume = 0
        } else if let vol = suite?.object(forKey: "todayTotalVolumeML") as? Int {
            previousVolume = vol
        } else {
            previousVolume = currentCount * 70
        }
        suite?.set(previousVolume + sipML, forKey: "todayTotalVolumeML")

        await HealthKitManager.saveSip(requestAuth: true)
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
