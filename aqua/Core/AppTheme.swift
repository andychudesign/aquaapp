//
//  AppTheme.swift
//  aqua
//

import SwiftUI

enum ThemeID: String, CaseIterable, Identifiable {
    case `default`
    case kurosawa

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:  return "Aqua"
        case .kurosawa: return "Kurosawa"
        }
    }

    /// Chinese counterpart shown beneath `displayName` while previewing themes.
    var nameChinese: String {
        switch self {
        case .default:  return "水"
        case .kurosawa: return "黑澤"
        }
    }

    /// Name of the alternate app icon bundled in the app target. Each theme
    /// maps to a *named* alternate (never `nil`), even the default look —
    /// iOS 26 has a known regression on the `setAlternateIconName(nil)`
    /// path with Liquid Glass `.icon`-bundle alternates (NSPOSIXError 35,
    /// "Resource temporarily unavailable"), and SpringBoard's out-of-process
    /// "App Icon Changed" alert is also suppressed for the nil-revert. By
    /// shipping `Sip-Aqua.icon` as a duplicate of the primary `Sip.icon`
    /// and always swapping between named alternates, both directions go
    /// through iOS's normal alternate-to-alternate transition and both
    /// issues disappear. Names must match `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
    var alternateIconName: String {
        switch self {
        case .default:  return "Sip-Aqua"
        case .kurosawa: return "Sip-Kurosawa"
        }
    }
}

struct AppTheme {
    let id: ThemeID
    let preferredColorScheme: ColorScheme

    let waterColor: Color
    let dehydratedBackground: Color

    let headerPrimary: Color
    let headerSecondary: Color
    let headerPrimaryOnWater: Color
    let headerSecondaryOnWater: Color

    let statsPrimary: Color
    let statsSecondary: Color
    let statsPrimaryOnWater: Color
    let statsSecondaryOnWater: Color

    let lastSipOnWater: Color
    let lastSipDehydrated: Color

    let buttonForeground: Color
    let buttonBackground: Color
    let buttonForegroundOnWater: Color
    let buttonBackgroundOnWater: Color

    /// Subordinate dehydrated-state colors for the flanking secondary buttons
    /// in the main app's `controlRow` (sip-volume + theme-switch). Gray-toned
    /// so they sit visually *below* the central sip button rather than
    /// competing with it. Kept distinct from `buttonForeground/Background`
    /// (which the widget reuses as its dehydrated drop-icon style and is
    /// intentionally tinted toward the brand water color) so a change in one
    /// surface doesn't leak into the other.
    let buttonSubtleForeground: Color
    let buttonSubtleBackground: Color

    /// Primary sip button (center) — *on-water* identity. When water is below
    /// the button row the primary button instead renders `waterColor` bg with
    /// a white droplet so it reads as a high-contrast CTA on the dehydrated
    /// background; this pair is used once water actually covers the buttons.
    let buttonPrimaryForeground: Color
    let buttonPrimaryBackground: Color

    let welcomeAccent: Color

    static func forID(_ id: ThemeID) -> AppTheme {
        switch id {
        case .default:  return .default
        case .kurosawa: return .kurosawa
        }
    }
}

// MARK: - Default (cream + blue)

extension AppTheme {
    static let `default` = AppTheme(
        id: .default,
        preferredColorScheme: .light,
        waterColor: Color(red: 0.2, green: 0.55, blue: 0.9),
        dehydratedBackground: Color(red: 0.98, green: 0.96, blue: 0.92),
        headerPrimary: Color(white: 0.1),
        headerSecondary: Color(red: 0.35, green: 0.55, blue: 0.85),
        headerPrimaryOnWater: .white,
        headerSecondaryOnWater: Color.white.opacity(0.5),
        statsPrimary: Color(white: 0x88 / 255.0),
        statsSecondary: Color(red: 0xB9 / 255.0, green: 0xB7 / 255.0, blue: 0xB6 / 255.0),
        statsPrimaryOnWater: .white,
        statsSecondaryOnWater: Color(red: 0x86 / 255.0, green: 0xC5 / 255.0, blue: 0xF6 / 255.0),
        lastSipOnWater: Color.white.opacity(0.5),
        lastSipDehydrated: Color.gray.opacity(0.6),
        buttonForeground: Color(red: 0.2, green: 0.55, blue: 0.9),
        buttonBackground: Color(red: 0.2, green: 0.55, blue: 0.9).opacity(0.15),
        buttonForegroundOnWater: .white,
        buttonBackgroundOnWater: Color.white.opacity(0.25),
        buttonSubtleForeground: Color(white: 0.5),
        buttonSubtleBackground: Color.black.opacity(0.10),
        buttonPrimaryForeground: Color(red: 0.2, green: 0.55, blue: 0.9),
        buttonPrimaryBackground: .white,
        welcomeAccent: Color(red: 0, green: 0.208, blue: 0.925)
    )
}

// MARK: - Kurosawa (grey + black) — colors to be finalized in v1.4

extension AppTheme {
    static let kurosawa = AppTheme(
        id: .kurosawa,
        preferredColorScheme: .light,
        waterColor: Color(white: 0.10),
        dehydratedBackground: Color(red: 0.89, green: 0.88, blue: 0.86),
        headerPrimary: Color(white: 0.08),
        headerSecondary: Color(white: 0.42),
        headerPrimaryOnWater: .white,
        headerSecondaryOnWater: Color.white.opacity(0.55),
        statsPrimary: Color(white: 0.30),
        statsSecondary: Color(white: 0.55),
        statsPrimaryOnWater: .white,
        statsSecondaryOnWater: Color(white: 0.78),
        lastSipOnWater: Color.white.opacity(0.55),
        lastSipDehydrated: Color(white: 0.45),
        buttonForeground: Color(white: 0.08),
        buttonBackground: Color.black.opacity(0.10),
        buttonForegroundOnWater: .white,
        buttonBackgroundOnWater: Color.white.opacity(0.22),
        buttonSubtleForeground: Color(white: 0.30),
        buttonSubtleBackground: Color.black.opacity(0.10),
        buttonPrimaryForeground: Color(white: 0.10),
        buttonPrimaryBackground: Color(white: 0.96),
        welcomeAccent: Color(white: 0.10)
    )
}
