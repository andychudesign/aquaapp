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
    /// path with Liquid Glass `.icon`-bundle alternates. `Sip-Aqua.icon`
    /// matches the primary look but must **not** be byte-identical to
    /// `Sip.icon` — SpringBoard treats a primary-equivalent alternate as a
    /// broken revert when switching back from `Sip-Kurosawa`. Names must
    /// match `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
    var alternateIconName: String {
        switch self {
        case .default:  return "Sip-Aqua"
        case .kurosawa: return "Sip-Kurosawa"
        }
    }
}

struct AppTheme {
    let id: ThemeID

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

    /// Resolve a theme's palette for the active system color scheme. Colors
    /// are kept **explicit** (not trait-adaptive `Color`) on purpose: the
    /// status-bar adaptation trick in `ContentView` hijacks the key window's
    /// `overrideUserInterfaceStyle` trait, so a trait-adaptive color would
    /// flip the whole app to its dark palette the instant water covers the
    /// status bar. Resolving here from a separately-captured *system* scheme
    /// (see `ContentView`/`SipVolumeSheet` screen-trait detection) keeps the
    /// two concerns independent.
    static func forID(_ id: ThemeID, scheme: ColorScheme) -> AppTheme {
        switch (id, scheme) {
        case (.default, .dark):   return .defaultDark
        case (.default, _):       return .default
        case (.kurosawa, .dark):  return .kurosawaDark
        case (.kurosawa, _):      return .kurosawa
        }
    }

    /// Light-scheme convenience used by callers that don't carry a scheme
    /// (e.g. the gallery cards, which preview each theme's primary identity).
    static func forID(_ id: ThemeID) -> AppTheme {
        forID(id, scheme: .light)
    }
}

// MARK: - Default (cream + blue)

extension AppTheme {
    static let `default` = AppTheme(
        id: .default,
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

    /// Default theme, dark scheme. Cream backdrop becomes a deep cool
    /// charcoal; the brand blue water is nudged slightly brighter so it still
    /// reads as the saturated accent against the near-black background.
    static let defaultDark = AppTheme(
        id: .default,
        waterColor: Color(red: 0.22, green: 0.56, blue: 0.94),
        dehydratedBackground: Color(red: 0.07, green: 0.08, blue: 0.10),
        headerPrimary: Color(white: 0.95),
        headerSecondary: Color(red: 0.5, green: 0.68, blue: 0.95),
        headerPrimaryOnWater: .white,
        headerSecondaryOnWater: Color.white.opacity(0.5),
        statsPrimary: Color(white: 0.72),
        statsSecondary: Color(white: 0.5),
        statsPrimaryOnWater: .white,
        statsSecondaryOnWater: Color(red: 0x86 / 255.0, green: 0xC5 / 255.0, blue: 0xF6 / 255.0),
        lastSipOnWater: Color.white.opacity(0.5),
        lastSipDehydrated: Color(white: 0.55),
        buttonForeground: Color(red: 0.45, green: 0.68, blue: 0.98),
        buttonBackground: Color.white.opacity(0.12),
        buttonForegroundOnWater: .white,
        buttonBackgroundOnWater: Color.white.opacity(0.25),
        buttonSubtleForeground: Color(white: 0.6),
        buttonSubtleBackground: Color.white.opacity(0.12),
        buttonPrimaryForeground: Color(red: 0.22, green: 0.56, blue: 0.94),
        buttonPrimaryBackground: Color(white: 0.96),
        welcomeAccent: Color(red: 0.3, green: 0.5, blue: 1.0)
    )
}

// MARK: - Kurosawa (grey + black)

extension AppTheme {
    static let kurosawa = AppTheme(
        id: .kurosawa,
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

    /// Kurosawa, dark scheme. The light palette is charcoal-water-on-stone;
    /// dark mode inverts the relationship — the backdrop goes near-black and
    /// the water is *lightened* to a graphite so the wave stays visible
    /// against it (a near-black water on a near-black backdrop would vanish).
    static let kurosawaDark = AppTheme(
        id: .kurosawa,
        waterColor: Color(white: 0.32),
        dehydratedBackground: Color(white: 0.08),
        headerPrimary: Color(white: 0.92),
        headerSecondary: Color(white: 0.60),
        headerPrimaryOnWater: .white,
        headerSecondaryOnWater: Color.white.opacity(0.6),
        statsPrimary: Color(white: 0.70),
        statsSecondary: Color(white: 0.45),
        statsPrimaryOnWater: .white,
        statsSecondaryOnWater: Color(white: 0.80),
        lastSipOnWater: Color.white.opacity(0.6),
        lastSipDehydrated: Color(white: 0.50),
        buttonForeground: Color(white: 0.85),
        buttonBackground: Color.white.opacity(0.12),
        buttonForegroundOnWater: .white,
        buttonBackgroundOnWater: Color.white.opacity(0.22),
        buttonSubtleForeground: Color(white: 0.60),
        buttonSubtleBackground: Color.white.opacity(0.12),
        buttonPrimaryForeground: Color(white: 0.12),
        buttonPrimaryBackground: Color(white: 0.95),
        welcomeAccent: Color(white: 0.85)
    )
}
