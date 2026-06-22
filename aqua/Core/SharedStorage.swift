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

    private static let healthKitAuthResolvedKey = "healthKitAuthResolved"

    /// Whether the HealthKit permission UX has been handled (onboarding Step 3
    /// or a legacy first-sip prompt for pre-v1.5 users).
    static var isHealthKitAuthResolved: Bool {
        suite?.bool(forKey: healthKitAuthResolvedKey) ?? false
    }

    static func markHealthKitAuthResolved() {
        suite?.set(true, forKey: healthKitAuthResolvedKey)
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
    /// Also records the count in the 7-day history dictionary and updates
    /// lifetime achievement counters (v1.5+).
    static func incrementSipCount() {
        let today = todayDateString
        let stored = suite?.string(forKey: sipCountDateKey)
        let isNewDay = stored != today

        if isNewDay, let previousDay = stored, !previousDay.isEmpty {
            finalizeSevenSipStreak(forCompletedDay: previousDay)
        }

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

        recordLoggedDay(today)
        incrementLifetimeSipCount()
        if newCount == 7 {
            registerSevenSipQualifiedDay(today)
        }
        evaluateSipAchievements()
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

    // MARK: - Per-day lookups (Siri day queries)

    /// `yyyy-MM-dd` key for an arbitrary date (matches the history format).
    static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Sip count for a specific day. Today uses the live counter; earlier days
    /// come from the 7-day history (returns 0 outside that window).
    static func sipCount(on dateString: String) -> Int {
        if dateString == todayDateString { return todaySipCount }
        return sipHistory[dateString] ?? 0
    }

    /// Volume in mL for a specific day. Today is the accumulated actual total;
    /// earlier days are *estimated* as count × the current per-sip volume — no
    /// per-day volume history is persisted, matching the same estimation
    /// convention the app already uses as a migration fallback.
    static func estimatedVolumeML(on dateString: String) -> Int {
        if dateString == todayDateString { return todayTotalVolumeML }
        return sipCount(on: dateString) * sipVolumeML
    }

    // MARK: - Calendar-week lookups (Siri week queries)

    /// Which calendar week to aggregate — locale-aware via `Calendar.current`.
    enum WeekScope {
        case thisWeek
        case lastWeek

        /// A date inside the target week (today, or one week ago).
        var referenceDate: Date {
            let cal = Calendar.current
            switch self {
            case .thisWeek:
                return Date()
            case .lastWeek:
                return cal.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            }
        }
    }

    /// All `yyyy-MM-dd` keys for the seven days in a calendar week.
    static func dateKeysInWeek(scope: WeekScope) -> [String] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: scope.referenceDate) else {
            return []
        }
        var keys: [String] = []
        var day = interval.start
        while day < interval.end {
            keys.append(dateKey(for: day))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return keys
    }

    /// Date keys inside the target week that still fall within the persisted
    /// 7-day history window (today + 6 prior).
    static func availableDateKeysInWeek(scope: WeekScope) -> Set<String> {
        let weekKeys = Set(dateKeysInWeek(scope: scope))
        let available = Set((0..<7).map { dateString(daysAgo: $0) })
        return weekKeys.intersection(available)
    }

    /// Total sips logged on days in the target week that we still have data for.
    static func sipCount(forWeek scope: WeekScope) -> Int {
        availableDateKeysInWeek(scope: scope)
            .reduce(0) { $0 + sipCount(on: $1) }
    }

    /// Total mL for the target week (today uses actual volume; earlier days
    /// estimated — same convention as per-day lookups).
    static func estimatedVolumeML(forWeek scope: WeekScope) -> Int {
        availableDateKeysInWeek(scope: scope)
            .reduce(0) { $0 + estimatedVolumeML(on: $1) }
    }

    /// Average daily sips among days in the target week that have at least one
    /// sip. Returns 0 when no days in the week have data.
    static func dailyAverage(forWeek scope: WeekScope) -> Double {
        let keys = availableDateKeysInWeek(scope: scope)
        let counts = keys.map { sipCount(on: $0) }
        let daysWithData = counts.filter { $0 > 0 }.count
        guard daysWithData > 0 else { return 0 }
        return Double(counts.reduce(0, +)) / Double(daysWithData)
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
            writeSelectedThemeID(newValue)
            reloadWidgetsForThemeChange()
        }
    }

    /// Persist the theme id without reloading widgets — used when an icon
    /// swap is still in flight so WidgetKit work doesn't race SpringBoard.
    static func writeSelectedThemeID(_ id: ThemeID) {
        suite?.set(id.rawValue, forKey: selectedThemeKey)
    }

    /// Last theme whose alternate icon SpringBoard acknowledged. Do not use
    /// `UIApplication.alternateIconName` as the source of truth — on iOS 26/27
    /// it can disagree with the home screen, Spotlight, and App Library.
    private static let iconSyncedThemeKey = "iconSyncedThemeID"

    static var iconSyncedThemeID: ThemeID? {
        get {
            guard let raw = suite?.string(forKey: iconSyncedThemeKey),
                  let id = ThemeID(rawValue: raw) else { return nil }
            return id
        }
        set {
            if let newValue {
                suite?.set(newValue.rawValue, forKey: iconSyncedThemeKey)
            } else {
                suite?.removeObject(forKey: iconSyncedThemeKey)
            }
        }
    }

    /// Per-kind widget reload after a theme change (matches sip-logging sites).
    static func reloadWidgetsForThemeChange() {
        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
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
        if id == .kurosawa {
            evaluateKurosawaAchievement()
        }
    }

    // MARK: - Achievements (v1.5+)

    private static let achievementsV15MigratedKey = "achievementsV15Migrated"
    private static let lifetimeSipCountKey = "lifetimeSipCount"
    private static let loggedDayKeysKey = "loggedDayKeys"
    private static let sevenSipConsecutiveDaysKey = "sevenSipConsecutiveDays"
    private static let sevenSipLastQualifiedDayKey = "sevenSipLastQualifiedDay"
    private static let achievementUnlockDatesKey = "achievementUnlockDates"
    private static let achievementLegacyUnlocksKey = "achievementLegacyUnlocks"
    private static let unseenAchievementIDsKey = "unseenAchievementIDs"
    private static let achievementDetailViewedIDsKey = "achievementDetailViewedIDs"
    private static let achievementNotificationsMigratedKey = "achievementNotificationsMigrated"
    private static let kurosawaDatedUnlockBackfillKey = "kurosawaDatedUnlockBackfillV1"

    /// Achievements unlocked since the user last dismissed the stats overlay.
    static var unseenAchievementIDs: Set<AchievementID> {
        get {
            let stored = suite?.array(forKey: unseenAchievementIDsKey) as? [String] ?? []
            return Set(stored.compactMap(AchievementID.init(rawValue:)))
        }
        set {
            suite?.set(newValue.map(\.rawValue).sorted(), forKey: unseenAchievementIDsKey)
        }
    }

    /// Achievements whose detail zoom has been opened at least once.
    static var achievementDetailViewedIDs: Set<AchievementID> {
        get {
            let stored = suite?.array(forKey: achievementDetailViewedIDsKey) as? [String] ?? []
            return Set(stored.compactMap(AchievementID.init(rawValue:)))
        }
        set {
            suite?.set(newValue.map(\.rawValue).sorted(), forKey: achievementDetailViewedIDsKey)
        }
    }

    /// One-time backfill so pre-existing unlocks do not show badges.
    /// Achievements left in `unseenAchievementIDs` (e.g. v1.4 Kurosawa on first v1.5
    /// launch) are excluded so the red dot stays until the user opens stats/detail.
    static func runAchievementNotificationsMigrationIfNeeded() {
        guard suite?.bool(forKey: achievementNotificationsMigratedKey) != true else { return }
        suite?.set(true, forKey: achievementNotificationsMigratedKey)
        let unseen = unseenAchievementIDs
        let alreadyComplete = AchievementID.allCases.filter { progress(for: $0).isComplete }
        var viewed = achievementDetailViewedIDs
        viewed.formUnion(alreadyComplete.filter { !unseen.contains($0) })
        achievementDetailViewedIDs = viewed
    }

    static func markAchievementUnseen(_ id: AchievementID) {
        var unseen = unseenAchievementIDs
        unseen.insert(id)
        unseenAchievementIDs = unseen
    }

    static func clearUnseenAchievements() {
        unseenAchievementIDs = []
    }

    static func markAchievementSeen(_ id: AchievementID) {
        var unseen = unseenAchievementIDs
        unseen.remove(id)
        unseenAchievementIDs = unseen
    }

    /// Returns `true` when this is the first time the detail view is opened.
    @discardableResult
    static func markAchievementDetailViewed(_ id: AchievementID) -> Bool {
        var viewed = achievementDetailViewedIDs
        guard !viewed.contains(id) else { return false }
        viewed.insert(id)
        achievementDetailViewedIDs = viewed
        return true
    }

    /// Total sips logged since v1.5 achievement tracking began.
    static var lifetimeSipCount: Int {
        suite?.integer(forKey: lifetimeSipCountKey) ?? 0
    }

    /// Distinct calendar days with at least one sip since v1.5 tracking began.
    static var loggedDayCount: Int {
        loggedDayKeys.count
    }

    /// Current consecutive-day streak where each day had at least 7 sips.
    static var sevenSipConsecutiveDays: Int {
        suite?.integer(forKey: sevenSipConsecutiveDaysKey) ?? 0
    }

    /// Run once on first launch after updating to v1.5. Backfills the Kurosawa
    /// achievement for users who unlocked in v1.4 — first v1.5 launch day becomes
    /// the recorded date and triggers the unseen badge.
    static func runAchievementsV15MigrationIfNeeded() {
        guard suite?.bool(forKey: achievementsV15MigratedKey) != true else { return }
        suite?.set(true, forKey: achievementsV15MigratedKey)
        if isUnlocked(.kurosawa) {
            recordAchievementUnlock(.unlockKurosawa, date: Date())
        }
    }

    /// Upgrades users who already received the old legacy Kurosawa backfill
    /// (no date, no red dot) to a dated unlock on first launch after this ships.
    static func runKurosawaDatedUnlockBackfillIfNeeded() {
        guard suite?.bool(forKey: kurosawaDatedUnlockBackfillKey) != true else { return }
        suite?.set(true, forKey: kurosawaDatedUnlockBackfillKey)
        guard isUnlocked(.kurosawa) else { return }
        guard achievementUnlockDate(for: .unlockKurosawa) == nil else { return }

        removeAchievementLegacyUnlock(.unlockKurosawa)
        recordAchievementUnlock(.unlockKurosawa, date: Date())

        var viewed = achievementDetailViewedIDs
        viewed.remove(.unlockKurosawa)
        achievementDetailViewedIDs = viewed
    }

    /// Progress for every achievement, ordered for display.
    static func allAchievementProgress() -> [AchievementProgress] {
        AchievementID.allCases.map { progress(for: $0) }
    }

    static func progress(for id: AchievementID) -> AchievementProgress {
        let unlockDisplay = unlockDisplay(for: id)
        let current: Int
        if unlockDisplay != .inProgress {
            current = id.target
        } else {
            switch id {
            case .unlockKurosawa:
                current = isUnlocked(.kurosawa) ? 1 : 0
            case .total100Sips:
                current = min(lifetimeSipCount, id.target)
            case .sevenConsecutiveSevenSipDays:
                current = min(sevenSipConsecutiveDays, id.target)
            case .fiftyLoggedDays, .hundredLoggedDays:
                current = min(loggedDayCount, id.target)
            }
        }
        return AchievementProgress(
            id: id,
            current: current,
            target: id.target,
            unlockDisplay: unlockDisplay
        )
    }

    // MARK: - Log water

    /// Persists a sip (hydration + counters + achievements). Does not reload widgets.
    static func recordSip() {
        suite?.set(hydrationLevel(), forKey: "fillStartLevel")
        lastWaterLogTime = Date()
        incrementSipCount()
    }

    /// Record that the user just drank water.
    static func logWater() {
        recordSip()
        // Reload each kind exactly once. See `LogWaterIntent.perform()` for
        // why the redundant `reloadAllTimelines()` + duplicate per-kind calls
        // were removed: they over-charged WidgetKit's per-widget reload
        // budget and starved the lock-screen (accessory) widgets, leaving
        // them frozen after multiple sips / with multiple widgets installed.
        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
    }

    // MARK: - Achievement internals

    private static var loggedDayKeys: Set<String> {
        let stored = suite?.array(forKey: loggedDayKeysKey) as? [String] ?? []
        return Set(stored)
    }

    private static func setLoggedDayKeys(_ keys: Set<String>) {
        suite?.set(Array(keys).sorted(), forKey: loggedDayKeysKey)
    }

    private static func recordLoggedDay(_ dayKey: String) {
        var keys = loggedDayKeys
        keys.insert(dayKey)
        setLoggedDayKeys(keys)
    }

    private static func incrementLifetimeSipCount() {
        suite?.set(lifetimeSipCount + 1, forKey: lifetimeSipCountKey)
    }

    private static func registerSevenSipQualifiedDay(_ dayKey: String) {
        let lastQualified = suite?.string(forKey: sevenSipLastQualifiedDayKey)
        guard lastQualified != dayKey else { return }

        let yesterday = dateString(daysAgo: 1)
        let streak: Int
        if lastQualified == yesterday {
            streak = sevenSipConsecutiveDays + 1
        } else {
            streak = 1
        }
        suite?.set(streak, forKey: sevenSipConsecutiveDaysKey)
        suite?.set(dayKey, forKey: sevenSipLastQualifiedDayKey)
    }

    /// Called when the calendar day rolls over — resets the streak if the day
    /// that just ended did not reach 7 sips.
    private static func finalizeSevenSipStreak(forCompletedDay dayKey: String) {
        let count = sipCount(on: dayKey)
        if count < 7 {
            suite?.set(0, forKey: sevenSipConsecutiveDaysKey)
            if suite?.string(forKey: sevenSipLastQualifiedDayKey) == dayKey {
                suite?.removeObject(forKey: sevenSipLastQualifiedDayKey)
            }
        }
    }

    private static func evaluateSipAchievements() {
        if lifetimeSipCount >= AchievementID.total100Sips.target {
            recordAchievementUnlock(.total100Sips)
        }
        if loggedDayCount >= AchievementID.fiftyLoggedDays.target {
            recordAchievementUnlock(.fiftyLoggedDays)
        }
        if loggedDayCount >= AchievementID.hundredLoggedDays.target {
            recordAchievementUnlock(.hundredLoggedDays)
        }
        if sevenSipConsecutiveDays >= AchievementID.sevenConsecutiveSevenSipDays.target {
            recordAchievementUnlock(.sevenConsecutiveSevenSipDays)
        }
        evaluateKurosawaAchievement()
    }

    private static func evaluateKurosawaAchievement() {
        guard isUnlocked(.kurosawa) else { return }
        if isAchievementLegacyUnlocked(.unlockKurosawa) {
            return
        }
        recordAchievementUnlock(.unlockKurosawa)
    }

    private static func unlockDisplay(for id: AchievementID) -> AchievementUnlockDisplay {
        if let date = achievementUnlockDate(for: id) {
            return .achieved(on: date)
        }
        if isAchievementLegacyUnlocked(id) {
            return .achievedLegacy
        }
        return .inProgress
    }

    private static func achievementUnlockDate(for id: AchievementID) -> Date? {
        let map = suite?.dictionary(forKey: achievementUnlockDatesKey) as? [String: Double] ?? [:]
        guard let interval = map[id.rawValue] else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private static func isAchievementLegacyUnlocked(_ id: AchievementID) -> Bool {
        let stored = suite?.array(forKey: achievementLegacyUnlocksKey) as? [String] ?? []
        return stored.contains(id.rawValue)
    }

    private static func markAchievementLegacyUnlocked(_ id: AchievementID) {
        var stored = suite?.array(forKey: achievementLegacyUnlocksKey) as? [String] ?? []
        guard !stored.contains(id.rawValue) else { return }
        stored.append(id.rawValue)
        suite?.set(stored, forKey: achievementLegacyUnlocksKey)
    }

    private static func removeAchievementLegacyUnlock(_ id: AchievementID) {
        var stored = suite?.array(forKey: achievementLegacyUnlocksKey) as? [String] ?? []
        stored.removeAll { $0 == id.rawValue }
        suite?.set(stored, forKey: achievementLegacyUnlocksKey)
    }

    private static func recordAchievementUnlock(_ id: AchievementID, date: Date = Date()) {
        var map = suite?.dictionary(forKey: achievementUnlockDatesKey) as? [String: Double] ?? [:]
        guard map[id.rawValue] == nil else { return }
        map[id.rawValue] = date.timeIntervalSince1970
        suite?.set(map, forKey: achievementUnlockDatesKey)
        markAchievementUnseen(id)
    }
}
