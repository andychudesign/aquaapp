//
//  AquaWidgetBundle.swift
//  AquaWidgetExtension
//

import CoreText
import WidgetKit
import SwiftUI

@main
struct AquaWidgetBundle: WidgetBundle {
    init() {
        WidgetBundledFonts.registerAll()
    }

    var body: some Widget {
        SipHomeWidget()
        SipStatusWidget()
    }
}

/// Registers fonts bundled inside the widget extension so `Font.custom(_:size:)`
/// resolves them in the widget process. The widget extension is a separate
/// bundle from the host app, so it can't rely on the host's
/// `BundledFonts.registerAll()` call — see `aquaApp.swift` for the matching
/// app-side helper. Font files are pulled into the widget target via
/// `membershipExceptions` in `project.pbxproj`.
private enum WidgetBundledFonts {
    static func registerAll() {
        let names = [
            "CrimsonText-Regular",
            "CrimsonText-SemiBold",
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
