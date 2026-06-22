//
//  SipIntents.swift
//  aqua
//
//  Shared between the main app and widget extension targets.
//

import AppIntents
import WidgetKit

/// Foreground intent used by the widget when HealthKit authorization hasn't been
/// resolved yet. Opens the app so the user can finish onboarding (Step 3
/// presents the HealthKit sheet); logs the sip without requesting auth here.
struct LogWaterAuthIntent: AppIntent {
    static let title: LocalizedStringResource = "I drank water"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedStorage.recordSip()

        _ = await HealthKitManager.saveSip(requestAuth: false)

        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
        return .result()
    }
}
