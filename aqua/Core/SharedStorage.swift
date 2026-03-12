//
//  SharedStorage.swift
//  aqua
//

import Foundation

/// App Group identifier shared between the main app and the widget.
enum SharedStorage {
    static let appGroupID = "group.andychudesign.aqua"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static let lastWaterLogTimeKey = "lastWaterLogTime"
    private static let hydrationDuration: TimeInterval = 5.0

    /// When the user last tapped "I drank water". Used to compute hydration level in app and widget.
    static var lastWaterLogTime: Date? {
        get {
            suite?.object(forKey: lastWaterLogTimeKey) as? Date
        }
        set {
            suite?.set(newValue, forKey: lastWaterLogTimeKey)
        }
    }

    /// Hydration level 0...1 from shared storage. Same formula as widget.
    static func hydrationLevel(at date: Date = Date()) -> Double {
        guard let logTime = lastWaterLogTime else { return 0 }
        let elapsed = date.timeIntervalSince(logTime)
        if elapsed >= hydrationDuration { return 0 }
        return max(0, 1 - elapsed / hydrationDuration)
    }

    /// Record that the user just drank water.
    static func logWater() {
        lastWaterLogTime = Date()
    }
}
