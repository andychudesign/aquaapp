//
//  AppIconCoordinator.swift
//  aqua
//

import UIKit

/// Serializes `setAlternateIconName` and keeps SpringBoard's fragmented caches
/// (home screen, App Library, Spotlight, Control Center) aligned with the
/// persisted theme. iOS 26/27 can update some surfaces but not others when
/// widget reloads race the icon API or when the app still shows the primary
/// `Sip` icon instead of the `Sip-Aqua` named alternate.
@MainActor
enum AppIconCoordinator {
    private static let maxAttempts = 3
    private static let retryDelay: Duration = .milliseconds(450)

    private static var inFlight = false
    private static var pendingThemeID: ThemeID?
    private static var reinforceTask: Task<Void, Never>?
    private static var didBootstrapThisSession = false

    // MARK: - Public

    /// Cold launch / return to foreground: align the icon with persisted theme.
    /// Also migrates a fresh install from the primary `Sip` icon to `Sip-Aqua`
    /// so every theme change is an alternate-to-alternate swap.
    static func bootstrapIfNeeded() {
        guard !didBootstrapThisSession else { return }
        didBootstrapThisSession = true
        guard supportsAlternateIcons else { return }
        let persisted = SharedStorage.selectedThemeID
        if needsIconSwap(for: persisted) {
            performSwap(to: persisted, attempt: 1, reason: "bootstrap")
        }
    }

    /// User tapped "Set theme" — must be called synchronously from the gallery
    /// pill's `Button` action before `dismiss()`.
    static func applyUserThemeChange(to themeID: ThemeID) {
        cancelReinforces()
        performSwap(to: themeID, attempt: 1, reason: "userApply")
    }

    /// Silent repair when foregrounding or heading home.
    static func reconcileIfNeeded() {
        guard supportsAlternateIcons else { return }
        let persisted = SharedStorage.selectedThemeID
        guard needsIconSwap(for: persisted) else { return }
        guard !inFlight else { return }
        performSwap(to: persisted, attempt: 1, reason: "reconcile")
    }

    /// Nudge every SpringBoard surface after the gallery dismisses and widgets
    /// have reloaded — Spotlight in particular can lag a primary swap.
    static func schedulePostDismissReinforces(for themeID: ThemeID) {
        cancelReinforces()
        reinforceTask = Task {
            for seconds in [0.35, 0.9, 1.8] {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                guard SharedStorage.selectedThemeID == themeID else { return }
                silentReinforce(to: themeID)
            }
        }
    }

    // MARK: - Internals

    private static var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    private static func cancelReinforces() {
        reinforceTask?.cancel()
        reinforceTask = nil
    }

    /// Bookkeeping mismatch, or UIKit's reported alternate name still differs
    /// from what the persisted theme requires. Used to *detect* drift — never
    /// to skip a user-initiated swap.
    private static func needsIconSwap(for themeID: ThemeID) -> Bool {
        let desired = themeID.alternateIconName
        let reported = UIApplication.shared.alternateIconName
        if SharedStorage.iconSyncedThemeID != themeID { return true }
        if reported != desired { return true }
        // Fresh install: primary `Sip` icon with no named alternate yet.
        if themeID == .default, reported == nil { return true }
        return false
    }

    private static func performSwap(to themeID: ThemeID, attempt: Int, reason: String) {
        guard supportsAlternateIcons else { return }
        if inFlight {
            pendingThemeID = themeID
            return
        }
        inFlight = true
        let desired = themeID.alternateIconName
        print("[Aqua] setAlternateIconName(\(desired)) [\(reason)] attempt \(attempt)")
        UIApplication.shared.setAlternateIconName(desired) { error in
            Task { @MainActor in
                if let error {
                    let ns = error as NSError
                    print("[Aqua] setAlternateIconName(\(desired)) failed: \(error)")
                    if ns.domain == NSPOSIXErrorDomain, ns.code == 35, attempt < maxAttempts {
                        inFlight = false
                        try? await Task.sleep(for: retryDelay)
                        performSwap(to: themeID, attempt: attempt + 1, reason: reason)
                        return
                    }
                    completeSwap()
                    return
                }

                let reported = UIApplication.shared.alternateIconName
                if reported == desired {
                    print("[Aqua] setAlternateIconName(\(desired)) succeeded")
                    SharedStorage.iconSyncedThemeID = themeID
                    completeSwap()
                    return
                }

                print(
                    "[Aqua] setAlternateIconName(\(desired)) UIKit ok "
                    + "but alternateIconName=\(reported ?? "nil"); retrying"
                )
                if attempt < maxAttempts {
                    inFlight = false
                    try? await Task.sleep(for: retryDelay)
                    performSwap(to: themeID, attempt: attempt + 1, reason: reason)
                    return
                }
                completeSwap()
            }
        }
    }

    private static func completeSwap() {
        inFlight = false
        if let pending = pendingThemeID {
            pendingThemeID = nil
            performSwap(to: pending, attempt: 1, reason: "queued")
        }
    }

    private static func silentReinforce(to themeID: ThemeID) {
        guard supportsAlternateIcons, !inFlight else { return }
        guard needsIconSwap(for: themeID) else { return }
        let desired = themeID.alternateIconName
        UIApplication.shared.setAlternateIconName(desired) { error in
            Task { @MainActor in
                guard error == nil,
                      UIApplication.shared.alternateIconName == desired else { return }
                SharedStorage.iconSyncedThemeID = themeID
            }
        }
    }
}
