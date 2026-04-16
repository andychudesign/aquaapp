//
//  AppTheme.swift
//  aqua
//

import SwiftUI

enum ThemeID: String, CaseIterable {
    case `default`
    case kurosawa
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
        welcomeAccent: Color(red: 0, green: 0.208, blue: 0.925)
    )
}

// MARK: - Kurosawa (grey + black) — colors to be finalized in v1.4

extension AppTheme {
    static let kurosawa = AppTheme(
        id: .kurosawa,
        preferredColorScheme: .dark,
        waterColor: Color(white: 0.15),
        dehydratedBackground: Color(white: 0.45),
        headerPrimary: .white,
        headerSecondary: Color(white: 0.78),
        headerPrimaryOnWater: Color(white: 0.82),
        headerSecondaryOnWater: Color(white: 0.82).opacity(0.5),
        statsPrimary: Color(white: 0.85),
        statsSecondary: Color(white: 0.6),
        statsPrimaryOnWater: Color(white: 0.82),
        statsSecondaryOnWater: Color(white: 0.6),
        lastSipOnWater: Color(white: 0.6),
        lastSipDehydrated: Color(white: 0.72),
        buttonForeground: .white,
        buttonBackground: Color.white.opacity(0.15),
        buttonForegroundOnWater: Color(white: 0.82),
        buttonBackgroundOnWater: Color(white: 0.82).opacity(0.25),
        welcomeAccent: Color(white: 0.7)
    )
}
