//
//  WaterState.swift
//  aqua
//

import Foundation

/// Hydration level from 0 (dehydrated) to 1 (hydrated).
/// Used to interpolate between the two visuals over the 5s transition.
enum WaterState {
    case dehydrated
    case hydrated

    var isHydrated: Bool {
        if case .hydrated = self { return true }
        return false
    }
}
