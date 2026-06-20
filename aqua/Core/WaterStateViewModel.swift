//
//  WaterStateViewModel.swift
//  aqua
//

import SwiftUI
import UIKit
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

    /// System light/dark scheme the palette is currently resolved against.
    /// Captured from the *screen* trait (see `currentSystemScheme()`), which is
    /// unaffected by the key window's `overrideUserInterfaceStyle` that
    /// `ContentView` toggles for the status-bar trick.
    private(set) var colorScheme: ColorScheme = WaterStateViewModel.currentSystemScheme()

    /// Active visual theme, resolved for the selected theme + system scheme.
    private(set) var theme: AppTheme = AppTheme.forID(
        SharedStorage.selectedThemeID,
        scheme: WaterStateViewModel.currentSystemScheme()
    )

    /// Theme IDs the user has unlocked (always includes `.default`).
    private(set) var unlockedThemeIDs: Set<ThemeID> = SharedStorage.unlockedThemeIDs

    /// Per-sip volume in mL (user-adjustable).
    private(set) var sipVolumeML: Int = SharedStorage.sipVolumeML

    /// Accumulated mL consumed today (actual per-sip volumes, not retroactive).
    private(set) var todayVolumeML: Int = SharedStorage.todayTotalVolumeML

    /// Achievement progress rows for the stats overlay (v1.5+).
    private(set) var achievements: [AchievementProgress] = SharedStorage.allAchievementProgress()

    private var refreshTimer: Timer?

    var isFullyDehydrated: Bool { hydrationLevel <= 0 }
    var isTransitioning: Bool { hydrationLevel > 0 && hydrationLevel < 1 }

    init() {
        SharedStorage.runAchievementsV15MigrationIfNeeded()
        hydrationLevel = SharedStorage.hydrationLevel()
        syncSipStats()
        startRefreshTimerIfNeeded()
    }

    /// Re-read shared storage so the app stays in sync after a widget tap or returning from background.
    /// If the level rose meaningfully (a sip happened while we were backgrounded, typically via the
    /// home-screen widget's `LogWaterIntent`), animate the change so the water fill rises smoothly
    /// instead of snapping to full — mirrors the `withAnimation` wrap on the in-app sip button.
    func refreshFromStorage() {
        let level = SharedStorage.hydrationLevel()
        let previousLevel = hydrationLevel
        if level > previousLevel + 0.05 {
            withAnimation(.easeInOut(duration: 0.5)) {
                hydrationLevel = level
            }
        } else {
            hydrationLevel = level
        }
        syncSipStats()
        theme = AppTheme.forID(SharedStorage.selectedThemeID, scheme: colorScheme)
        unlockedThemeIDs = SharedStorage.unlockedThemeIDs
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
                // Re-reload so the widget button rebinds to the background
                // intent now that auth is resolved. Per-kind (not
                // `reloadAllTimelines()`) to avoid over-charging the
                // accessory widgets' reload budget — see `SharedStorage.logWater()`.
                WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
                WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
            }
        }
    }

    /// Apply a theme. Persists to shared storage, updates the in-memory theme,
    /// and asks `AppIconCoordinator` to swap the home-screen alternate icon.
    /// **Must be called from the gallery action pill's `Button` action before
    /// `dismiss()`** so iOS 26+ keeps the user-interaction context.
    func applyTheme(_ id: ThemeID) {
        let previousID = SharedStorage.selectedThemeID
        SharedStorage.writeSelectedThemeID(id)
        theme = AppTheme.forID(id, scheme: colorScheme)
        guard previousID != id else { return }
        AppIconCoordinator.applyUserThemeChange(to: id)
    }

    /// Mark a theme as unlocked. Future StoreKit purchase flow should call this
    /// from a verified `Transaction` listener.
    func unlockTheme(_ id: ThemeID) {
        SharedStorage.unlock(id)
        unlockedThemeIDs = SharedStorage.unlockedThemeIDs
        syncSipStats()
    }

    /// Re-resolve the active palette for a new system color scheme. Called by
    /// `ContentView` on appear and whenever the scene becomes active (matching
    /// the cadence `SipVolumeSheet` already uses), so the app follows the
    /// device's Light/Dark setting.
    func updateColorScheme(_ scheme: ColorScheme) {
        guard scheme != colorScheme else { return }
        colorScheme = scheme
        theme = AppTheme.forID(SharedStorage.selectedThemeID, scheme: scheme)
    }

    /// Reads the device's *system* light/dark preference from the scene's
    /// screen trait, which the key window's `overrideUserInterfaceStyle`
    /// (used by `ContentView` for the status-bar adaptation) does not affect —
    /// the override mutates only the window's trait, not the screen's.
    static func currentSystemScheme() -> ColorScheme {
        let style = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen.traitCollection.userInterfaceStyle ?? .light
        return style == .dark ? .dark : .light
    }

    private func syncSipStats() {
        todaySipCount = SharedStorage.todaySipCount
        last7Days = SharedStorage.last7DaysSipCounts
        recentAverage = SharedStorage.previous6DayAverage
        sipVolumeML = SharedStorage.sipVolumeML
        todayVolumeML = SharedStorage.todayTotalVolumeML
        achievements = SharedStorage.allAchievementProgress()
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
