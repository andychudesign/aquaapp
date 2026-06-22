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

    /// Cold launch: align bookkeeping with the home-screen icon without
    /// calling `setAlternateIconName` when the primary `Sip` icon already
    /// matches the Default theme (fresh install / reinstall).
    static func bootstrapIfNeeded() {
        guard !didBootstrapThisSession else { return }
        didBootstrapThisSession = true
        guard supportsAlternateIcons else { return }

        let persisted = SharedStorage.selectedThemeID
        if isIconAligned(for: persisted) {
            syncBookkeeping(for: persisted)
            return
        }
        performSwap(to: persisted, attempt: 1, reason: "bootstrap")
    }

    /// User tapped "Set theme" — must be called synchronously from the gallery
    /// pill's `Button` action before `dismiss()`.
    static func applyUserThemeChange(to themeID: ThemeID) {
        cancelReinforces()
        // A silent bootstrap/reconcile swap must not win over an explicit pick.
        if inFlight {
            inFlight = false
            pendingThemeID = nil
        }
        performSwap(to: themeID, attempt: 1, reason: "userApply")
    }

    /// Silent repair when foregrounding or heading home.
    static func reconcileIfNeeded() {
        guard supportsAlternateIcons else { return }
        let persisted = SharedStorage.selectedThemeID
        guard needsIconSwap(for: persisted) else {
            syncBookkeeping(for: persisted)
            return
        }
        guard !inFlight else { return }
        performSwap(to: persisted, attempt: 1, reason: "reconcile")
    }

    /// Whether the home-screen icon matches `themeID`. Exposed for the theme
    /// gallery so "Applied" can offer a retry when persistence and SpringBoard
    /// drift apart.
    static func isThemeIconAligned(_ themeID: ThemeID) -> Bool {
        isIconAligned(for: themeID)
    }

    /// Nudge every SpringBoard surface after the gallery dismisses when the
    /// user-initiated swap did not fully land (Spotlight can lag).
    static func schedulePostDismissReinforces(for themeID: ThemeID) {
        cancelReinforces()
        guard needsIconSwap(for: themeID) else { return }
        reinforceTask = Task {
            for seconds in [0.35, 0.9, 1.8] {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                guard SharedStorage.selectedThemeID == themeID else { return }
                guard needsIconSwap(for: themeID) else { return }
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

    /// Whether the home-screen icon already matches the persisted theme.
    /// Primary `Sip` (nil alternate) counts as Default — do not force a
    /// `Sip-Aqua` swap on first launch; that only triggers SpringBoard's
    /// "App Icon Changed" alert with no user action.
    private static func isIconAligned(for themeID: ThemeID) -> Bool {
        let reported = UIApplication.shared.alternateIconName
        switch themeID {
        case .default:
            return reported == nil || reported == ThemeID.default.alternateIconName
        case .kurosawa:
            return reported == ThemeID.kurosawa.alternateIconName
        }
    }

    private static func needsIconSwap(for themeID: ThemeID) -> Bool {
        !isIconAligned(for: themeID)
    }

    private static func syncBookkeeping(for themeID: ThemeID) {
        if SharedStorage.iconSyncedThemeID != themeID {
            SharedStorage.iconSyncedThemeID = themeID
        }
    }

    /// Named alternate for every theme; Default may fall back to `nil`
    /// (primary `Sip`) on the final retry when reverting from Kurosawa —
    /// iOS 26/27 can accept UIKit success for `Sip-Aqua` without updating
    /// SpringBoard's cache.
    private static func swapIconName(for themeID: ThemeID, attempt: Int) -> String? {
        switch themeID {
        case .kurosawa:
            return ThemeID.kurosawa.alternateIconName
        case .default:
            let reported = UIApplication.shared.alternateIconName
            if attempt >= maxAttempts,
               reported == ThemeID.kurosawa.alternateIconName {
                return nil
            }
            return ThemeID.default.alternateIconName
        }
    }

    private static func performSwap(to themeID: ThemeID, attempt: Int, reason: String) {
        guard supportsAlternateIcons else { return }
        if inFlight {
            pendingThemeID = themeID
            return
        }
        inFlight = true
        let desired = swapIconName(for: themeID, attempt: attempt)
        let desiredLabel = desired ?? "nil"
        print("[Aqua] setAlternateIconName(\(desiredLabel)) [\(reason)] attempt \(attempt)")
        UIApplication.shared.setAlternateIconName(desired) { error in
            Task { @MainActor in
                if let error {
                    let ns = error as NSError
                    print("[Aqua] setAlternateIconName(\(desiredLabel)) failed: \(error)")
                    if ns.domain == NSPOSIXErrorDomain, ns.code == 35, attempt < maxAttempts {
                        inFlight = false
                        try? await Task.sleep(for: retryDelay)
                        performSwap(to: themeID, attempt: attempt + 1, reason: reason)
                        return
                    }
                    completeSwap()
                    return
                }

                if isIconAligned(for: themeID) {
                    print("[Aqua] setAlternateIconName(\(desiredLabel)) succeeded")
                    SharedStorage.iconSyncedThemeID = themeID
                    completeSwap()
                    return
                }

                let reported = UIApplication.shared.alternateIconName
                print(
                    "[Aqua] setAlternateIconName(\(desiredLabel)) UIKit ok "
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
        guard needsIconSwap(for: themeID) else {
            syncBookkeeping(for: themeID)
            return
        }
        let desired = swapIconName(for: themeID, attempt: maxAttempts)
        UIApplication.shared.setAlternateIconName(desired) { error in
            Task { @MainActor in
                guard error == nil, isIconAligned(for: themeID) else { return }
                SharedStorage.iconSyncedThemeID = themeID
            }
        }
    }
}
