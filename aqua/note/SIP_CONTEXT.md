# Sip App Context

## Overview

Sip is a minimal water-tracking iOS app. Tap a button, log a sip, and watch the screen fill with water that slowly drains over 2 hours — a gentle visual reminder to drink again. A companion Home/Lock Screen widget mirrors the hydration level and lets you log directly from the widget.

The app name toggles contextually: **"Aqua"** (水) when hydrated, **"Sip"** (飲) when dehydrated. Bilingual English + Chinese copy throughout.

## Tech

- **Platform:** iOS 26.2, iPhone & iPad
- **Language:** Swift 5 with `@Observable`, async/await, App Intents
- **UI:** SwiftUI only (no UIKit), fixed light color scheme
- **Architecture:** MVVM — `WaterStateViewModel` (`@Observable`) drives `ContentView`
- **Persistence:** `UserDefaults` via App Group (`group.andychudesign.Aqua`), shared between the main app and the widget extension
- **Widget:** WidgetKit extension (`AquaWidgetExtension`) supporting `.systemSmall`, `.systemMedium`, `.accessoryCircular`, `.accessoryRectangular` with a `LogWaterIntent` (App Intents)
- **Font:** Inter-Medium (custom)
- **Dependencies:** None — pure Apple frameworks (SwiftUI, Foundation, WidgetKit, AppIntents)

## Core Logic

- **Single data point:** `lastWaterLogTime` (a `Date` stored in the shared App Group `UserDefaults`)
- **Hydration formula:** `hydrationLevel = max(0, 1 - elapsed / 7200)` — linear decay from 1.0 to 0.0 over 2 hours (7200 seconds)
- **Log water:** Sets `lastWaterLogTime` to now → hydration jumps to 1.0 → begins draining
- **Refresh:** 1-second timer in the view model continuously recalculates `hydrationLevel` while draining; also refreshes on `scenePhase == .active`
- **Widget sync:** `WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")` fires after each log; timeline provider pre-computes entries at 5-minute intervals for the drain phase

## V1 State

- **Single screen:** GeometryReader-based layout with a sticky header, centered drop button, and "Last sip" timestamp at the bottom
- **Water fill:** `WaveShape` (dual sine waves + Gaussian bump under the button) fills from the bottom, height driven by `hydrationLevel`
- **Animations:** Infinite 4s wave phase loop, 0.5s ease-in-out fill, interpolating spring slosh on tap
- **Colors:** Water blue (`0.2, 0.55, 0.9`), warm dehydrated background (`0.98, 0.96, 0.92`)
- **Welcome flow:** Three-phase overlay on first launch with progress bar, water fill demo, and widget screenshot — dismissed via `@AppStorage("hasSeenWelcome")`
- **Placeholder views:** `DehydratedView` and `HydratedView` are currently `Color.clear`; visual difference is conveyed entirely through water fill level and header text
- **No history / no daily goal / no notifications** — intentionally minimal for V1

## V1.1 Bug Fixes

### 1. Wave animation freezing after logging a sip (App)
- **Bug:** After tapping the sip button the water level rose but the wave animation stopped moving. Closing and reopening the app restored it.
- **Cause:** `WaveShape.animatableData` bundled `phase` with `amplitude` and `bumpHeight`. The `withAnimation(.easeInOut(duration: 0.5))` wrapping `logWater()` re-animated the entire animatable pair, overriding the repeating `.linear(duration: 4)` wave phase loop. After 0.5 s, `phase` was stuck at 1.0 with no active animation.
- **Fix:** Removed `phase` from `animatableData` (now only `amplitude` + `bumpHeight`). Replaced the `.onAppear` repeating animation with a `TimelineView(.animation(paused: hydrationLevel <= 0))` that computes `wavePhase` from wall-clock time each frame, making it immune to other animation transactions.

### 2. Widget water drops to 0 before filling up (Widget)
- **Bug:** Tapping the widget button while water was mid-drain (e.g. 0.5) caused the water to visually drop to 0 then ramp back to 1.
- **Cause:** The timeline fill phase always ramped from `0 → 1` over 2 seconds, ignoring the current level.
- **Fix:** Both `SharedStorage.logWater()` and `LogWaterIntent.perform()` now snapshot the current `hydrationLevel` into a `"fillStartLevel"` key in the shared App Group `UserDefaults` before setting the new log time. The timeline provider reads this value and ramps from `fillStartLevel → 1` instead of `0 → 1`.

### 3. "Last sip" text unreadable at low water levels (App)
- **Bug:** At low hydration levels the "Last sip" text switched to dark color while still sitting on the blue water (Gaussian bump keeps water visually high).
- **Cause:** The `bottomTextOnWater` threshold was `hydrationLevel > 0.08`, but the bump pushes visible water well above the base height even at levels near 0.
- **Fix:** Changed threshold to `hydrationLevel > 0` — text stays white as long as any water is on screen, matching the bump behaviour.

### 4. Widget water invisible in iOS Tinted mode (Widget)
- **Bug:** In Home Screen Tinted mode, the water fill was invisible — the widget showed a flat tinted background with no water.
- **Cause:** The system removes `containerBackground` content by default in tinted mode, discarding the water fill entirely.
- **Fix:** Added `.containerBackgroundRemovable(false)` to the widget configuration so the custom background persists. Marked `dehydratedBg` with `.widgetAccentable()` so the system renders the background with the tint color (darker) while the water stays in the non-accented group (lighter). Also added `@Environment(\.widgetRenderingMode)` detection with conditional text/button colors that swap to dark when on water in tinted mode.
