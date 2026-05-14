//
//  SharedStorage.swift
//  aqua
//

import Foundation
import WidgetKit

/// App Group identifier shared between the main app and the widget.
enum SharedStorage {
    static let appGroupID = "group.andychudesign.Aqua"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static let lastWaterLogTimeKey = "lastWaterLogTime"
    private static let hydrationDuration: TimeInterval = 7200

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

    // MARK: - Daily sip count

    private static let sipCountKey = "todaySipCount"
    private static let sipCountDateKey = "todaySipCountDate"

    /// Today's sip count. Resets automatically when the calendar day changes.
    static var todaySipCount: Int {
        guard let storedDate = suite?.string(forKey: sipCountDateKey),
              storedDate == Self.todayDateString else {
            return 0
        }
        return suite?.integer(forKey: sipCountKey) ?? 0
    }

    /// Increment the daily sip count and accumulate actual volume.
    /// Resets if the stored date isn't today.
    /// Also records the count in the 7-day history dictionary.
    static func incrementSipCount() {
        let today = todayDateString
        let stored = suite?.string(forKey: sipCountDateKey)
        let isNewDay = stored != today
        let current = isNewDay ? 0 : (suite?.integer(forKey: sipCountKey) ?? 0)
        let newCount = current + 1
        suite?.set(newCount, forKey: sipCountKey)
        suite?.set(today, forKey: sipCountDateKey)

        let previousVolume: Int
        if isNewDay {
            previousVolume = 0
        } else if let vol = suite?.object(forKey: totalVolumeKey) as? Int {
            previousVolume = vol
        } else {
            previousVolume = current * defaultSipVolume
        }
        suite?.set(previousVolume + sipVolumeML, forKey: totalVolumeKey)

        var history = sipHistory
        history[today] = newCount
        let validKeys = Set((0..<7).map { dateString(daysAgo: $0) })
        history = history.filter { validKeys.contains($0.key) }
        suite?.set(history, forKey: sipHistoryKey)
    }

    // MARK: - 7-day sip history

    private static let sipHistoryKey = "sipHistory"

    /// Sip counts for the last 7 days (today + 6 prior), oldest first.
    /// Each element is `(dateString, sipCount)`.
    static var last7DaysSipCounts: [(date: String, count: Int)] {
        let history = sipHistory
        return (0..<7).reversed().map { daysAgo in
            let key = dateString(daysAgo: daysAgo)
            return (key, history[key] ?? 0)
        }
    }

    /// Average daily sips over the last 7 days (excluding today).
    static var previous6DayAverage: Double {
        let history = sipHistory
        let counts = (1...6).map { history[dateString(daysAgo: $0)] ?? 0 }
        let total = counts.reduce(0, +)
        let daysWithData = counts.filter { $0 > 0 }.count
        guard daysWithData > 0 else { return 0 }
        return Double(total) / Double(daysWithData)
    }

    private static let totalVolumeKey = "todayTotalVolumeML"
    private static let sipVolumeKey = "sipVolumeML"
    private static let defaultSipVolume = 70

    /// Accumulated mL consumed today. Falls back to count * 70 for pre-tracking sips.
    static var todayTotalVolumeML: Int {
        guard let storedDate = suite?.string(forKey: sipCountDateKey),
              storedDate == todayDateString else {
            return 0
        }
        if let vol = suite?.object(forKey: totalVolumeKey) as? Int {
            return vol
        }
        return todaySipCount * defaultSipVolume
    }

    static var sipVolumeML: Int {
        get {
            let stored = suite?.integer(forKey: sipVolumeKey) ?? 0
            return stored > 0 ? stored : defaultSipVolume
        }
        set {
            suite?.set(newValue, forKey: sipVolumeKey)
        }
    }

    private static var sipHistory: [String: Int] {
        suite?.dictionary(forKey: sipHistoryKey) as? [String: Int] ?? [:]
    }

    private static var todayDateString: String {
        dateString(daysAgo: 0)
    }

    private static func dateString(daysAgo: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return f.string(from: date)
    }

    // MARK: - Theme

    private static let selectedThemeKey = "selectedTheme"

    static var selectedThemeID: ThemeID {
        get {
            guard let raw = suite?.string(forKey: selectedThemeKey),
                  let id = ThemeID(rawValue: raw) else { return .default }
            return id
        }
        set {
            suite?.set(newValue.rawValue, forKey: selectedThemeKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static var currentTheme: AppTheme {
        .forID(selectedThemeID)
    }

    // MARK: - Theme unlocks
    // Currently grants Kurosawa for free (no IAP gate yet). Once StoreKit 2
    // ships, only `.default` will be unlocked by install; paid themes will
    // be added to this set on successful purchase / restore.

    private static let unlockedThemesKey = "unlockedThemes"

    static var unlockedThemeIDs: Set<ThemeID> {
        get {
            let stored = suite?.array(forKey: unlockedThemesKey) as? [String] ?? []
            var set = Set(stored.compactMap(ThemeID.init(rawValue:)))
            set.insert(.default)
            return set
        }
        set {
            suite?.set(newValue.map(\.rawValue), forKey: unlockedThemesKey)
        }
    }

    static func isUnlocked(_ id: ThemeID) -> Bool {
        unlockedThemeIDs.contains(id)
    }

    static func unlock(_ id: ThemeID) {
        var current = unlockedThemeIDs
        current.insert(id)
        unlockedThemeIDs = current
    }

    // MARK: - Log water

    /// Record that the user just drank water.
    static func logWater() {
        suite?.set(hydrationLevel(), forKey: "fillStartLevel")
        lastWaterLogTime = Date()
        incrementSipCount()
        // Reload all widget kinds, then re-issue per-kind reloads —
        // `reloadAllTimelines()` is sometimes coalesced away for the
        // accessory (lock-screen) widget on iOS 26, leaving it stuck on
        // the pre-sip timeline while the home widget updates instantly.
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
    }
}
