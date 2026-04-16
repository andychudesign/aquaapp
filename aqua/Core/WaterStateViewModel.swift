//
//  WaterStateViewModel.swift
//  aqua
//

import SwiftUI
import WidgetKit

@Observable
final class WaterStateViewModel {
    /// 0 = dehydrated, 1 = hydrated. Synced with SharedStorage for widget.
    private(set) var hydrationLevel: Double = 0

    /// Today's total sip count.
    private(set) var todaySipCount: Int = 0

    /// Last 7 days of sip counts (oldest first).
    private(set) var last7Days: [(date: String, count: Int)] = []

    /// Average sips/day over the previous 6 days (excludes today).
    private(set) var recentAverage: Double = 0

    /// Active visual theme, synced from SharedStorage.
    private(set) var theme: AppTheme = SharedStorage.currentTheme

    /// Per-sip volume in mL (user-adjustable).
    private(set) var sipVolumeML: Int = SharedStorage.sipVolumeML

    /// Accumulated mL consumed today (actual per-sip volumes, not retroactive).
    private(set) var todayVolumeML: Int = SharedStorage.todayTotalVolumeML

    private var refreshTimer: Timer?

    var isFullyDehydrated: Bool { hydrationLevel <= 0 }
    var isTransitioning: Bool { hydrationLevel > 0 && hydrationLevel < 1 }

    init() {
        hydrationLevel = SharedStorage.hydrationLevel()
        syncSipStats()
        startRefreshTimerIfNeeded()
    }

    /// Re-read shared storage so the app stays in sync after a widget tap or returning from background.
    func refreshFromStorage() {
        let level = SharedStorage.hydrationLevel()
        hydrationLevel = level
        syncSipStats()
        theme = SharedStorage.currentTheme
        if level > 0 {
            startRefreshTimerIfNeeded()
        }
    }

    /// Call when the user taps "I drank water". Persists for widget and animates back over 5s.
    func logWater() {
        SharedStorage.logWater()
        hydrationLevel = 1.0
        syncSipStats()
        startRefreshTimerIfNeeded()

        Task {
            let saved = await HealthKitManager.saveSip()
            if saved {
                let suite = UserDefaults(suiteName: SharedStorage.appGroupID)
                suite?.set(true, forKey: "healthKitAuthResolved")
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func syncSipStats() {
        todaySipCount = SharedStorage.todaySipCount
        last7Days = SharedStorage.last7DaysSipCounts
        recentAverage = SharedStorage.previous6DayAverage
        sipVolumeML = SharedStorage.sipVolumeML
        todayVolumeML = SharedStorage.todayTotalVolumeML
    }

    /// Refresh UI from shared storage so we stay in sync with widget and persist across launches.
    private func startRefreshTimerIfNeeded() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                let level = SharedStorage.hydrationLevel()
                self?.hydrationLevel = level
                if level <= 0 {
                    self?.refreshTimer?.invalidate()
                    self?.refreshTimer = nil
                }
            }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }
}
