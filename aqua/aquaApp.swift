//
//  aquaApp.swift
//  aqua
//
//  Created by Andy Chu on 3/12/26.
//

import CoreText
import SwiftUI

@main
struct aquaApp: App {
    init() {
        BundledFonts.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Registers fonts bundled inside `aqua.app` with the system font manager so
/// `Font.custom(_:size:)` resolves them. We register at runtime instead of via
/// `UIAppFonts` in Info.plist because Xcode's auto-Info-plist generation does
/// not honor `INFOPLIST_KEY_UIAppFonts` in our project setup.
private enum BundledFonts {
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
