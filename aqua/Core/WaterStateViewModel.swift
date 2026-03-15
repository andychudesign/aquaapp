//
//  WaterStateViewModel.swift
//  aqua
//

import SwiftUI

@Observable
final class WaterStateViewModel {
    /// 0 = dehydrated, 1 = hydrated. Synced with SharedStorage for widget.
    private(set) var hydrationLevel: Double = 0

    private var refreshTimer: Timer?

    var isFullyDehydrated: Bool { hydrationLevel <= 0 }
    var isTransitioning: Bool { hydrationLevel > 0 && hydrationLevel < 1 }

    init() {
        hydrationLevel = SharedStorage.hydrationLevel()
        startRefreshTimerIfNeeded()
    }

    /// Re-read shared storage so the app stays in sync after a widget tap or returning from background.
    func refreshFromStorage() {
        let level = SharedStorage.hydrationLevel()
        hydrationLevel = level
        if level > 0 {
            startRefreshTimerIfNeeded()
        }
    }

    /// Call when the user taps "I drank water". Persists for widget and animates back over 5s.
    func logWater() {
        SharedStorage.logWater()
        hydrationLevel = 1.0
        startRefreshTimerIfNeeded()
    }

    /// Refresh UI from shared storage so we stay in sync with widget and persist across launches.
    private func startRefreshTimerIfNeeded() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
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
