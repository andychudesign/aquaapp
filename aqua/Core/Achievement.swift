//
//  Achievement.swift
//  aqua
//

import Foundation

/// Persistent achievement identifiers (App Group `UserDefaults`).
enum AchievementID: String, CaseIterable, Identifiable, Codable {
    case unlockKurosawa
    case total100Sips
    case sevenConsecutiveSevenSipDays
    case fiftyLoggedDays
    case hundredLoggedDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlockKurosawa:
            return "Unlock Kurosawa theme"
        case .total100Sips:
            return "Log total 100 sips"
        case .sevenConsecutiveSevenSipDays:
            return "Log 7 sips each day for 7 days"
        case .fiftyLoggedDays:
            return "50 days log sip"
        case .hundredLoggedDays:
            return "100 days log sip"
        }
    }

    var target: Int {
        switch self {
        case .unlockKurosawa: return 1
        case .total100Sips: return 100
        case .sevenConsecutiveSevenSipDays: return 7
        case .fiftyLoggedDays: return 50
        case .hundredLoggedDays: return 100
        }
    }

    /// Asset catalog image name — locked (in-progress) cup artwork (list row).
    var lockedImageName: String { "Achievement-\(rawValue)-locked" }

    /// Asset catalog image name — unlocked (achieved) cup artwork (list row).
    var unlockedImageName: String { "Achievement-\(rawValue)-unlocked" }

    /// High-resolution locked cup for the achievement detail zoom.
    var lockedDetailImageName: String { "Achievement-\(rawValue)-locked-detail" }

    /// High-resolution unlocked cup for the achievement detail zoom.
    var unlockedDetailImageName: String { "Achievement-\(rawValue)-unlocked-detail" }
}

/// How to render the achieved-state subtitle.
enum AchievementUnlockDisplay: Equatable {
    case inProgress
    case achieved(on: Date)
    /// v1.4 unlock with no recorded date (e.g. Kurosawa backfill).
    case achievedLegacy
}

struct AchievementProgress: Identifiable, Equatable {
    let id: AchievementID
    let current: Int
    let target: Int
    let unlockDisplay: AchievementUnlockDisplay

    var isComplete: Bool {
        switch unlockDisplay {
        case .inProgress: return false
        case .achieved, .achievedLegacy: return true
        }
    }

    var progressFraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(current) / Double(target))
    }
}
