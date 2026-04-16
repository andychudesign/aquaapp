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
- **Dependencies:** None — pure Apple frameworks (SwiftUI, Foundation, WidgetKit, AppIntents, HealthKit)

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

## V1.1 Features

### Apple HealthKit Integration
- **What:** Each sip saves a `dietaryWater` sample to Apple Health, from both the main app and the widget.
- **Flow:** First sip in the main app triggers the system HealthKit authorization sheet (write-only for Water). Once authorized, all subsequent sips — including widget taps — write silently. Failures are non-blocking and never prevent a sip from being logged.
- **Implementation:** `HealthKitManager` — shared target membership (app + widget). Called from `WaterStateViewModel.logWater()` (app) and `LogWaterIntent.perform()` (widget).
- **Files changed:**
  - `Core/HealthKitManager.swift` — new, shared target membership (app + widget)
  - `Core/WaterStateViewModel.swift` — added `Task { await HealthKitManager.saveSip() }` in `logWater()`
  - `AquaWidgetExtension/AquaWidget.swift` — added `await HealthKitManager.saveSip()` in `LogWaterIntent.perform()`
  - `aqua.entitlements` + `AquaWidgetExtension.entitlements` — added `com.apple.developer.healthkit` keys
  - Xcode: HealthKit capability enabled on both targets, usage descriptions set in build settings

## V1.2 Bug Fixes

### 5. Widget sips not writing to Apple Health (Widget)
- **Bug:** Logging water via the widget never saved to Apple Health. Only in-app sips reached HealthKit.
- **Cause:** Two issues. (1) The widget extension target was missing `INFOPLIST_KEY_NSHealthUpdateUsageDescription` in its build settings — without the write-usage description, `requestAuthorization(toShare:read:)` threw `errorAuthorizationDenied` and the `guard` bailed out before attempting the save. (2) `HealthKitManager` was `@MainActor`-isolated, adding unnecessary actor-hopping in the widget extension process, and `saveSip()` called `requestAuthorization` unconditionally — which can't present UI from an extension.
- **Fix:** Added `NSHealthUpdateUsageDescription` to both Debug and Release build settings of the widget extension target. Removed `@MainActor` from `HealthKitManager` (HKHealthStore is thread-safe). Added a `requestAuth` parameter to `saveSip(requestAuth:)` — the main app uses the default (`true`) to trigger the authorization sheet; the widget passes `false` to skip it. `saveSip` now returns `Bool`; on success the widget sets `"healthKitAuthResolved"` in shared `UserDefaults`. The same flag is set by the main app after a successful in-app save.

### 6. First widget sip opens app for HealthKit authorization (Widget → App)
- **Problem:** Widget extensions cannot present the HealthKit authorization sheet. Users who only use the widget would never be prompted.
- **Fix:** Two-intent pattern. A shared `LogWaterAuthIntent` (`openAppWhenRun = true`, defined in `Core/SipIntents.swift`, compiled into both targets) opens the app, requests HealthKit authorization in the foreground, saves the sip, and sets the `"healthKitAuthResolved"` flag. The background `LogWaterIntent` is used for all subsequent saves. The widget timeline provider reads the flag and passes `needsHealthKitAuth` to each entry; the widget view conditionally renders `Button(intent: LogWaterAuthIntent())` or `Button(intent: LogWaterIntent())`.
- **Flow:** First widget tap after install/update → app opens → HealthKit permission sheet → authorized → sip saved → flag set → timeline reloads → all future taps are seamless background saves.

## V1.2 Changes

### Default sip volume reduced to 70 mL
- **What:** Changed the per-sip HealthKit sample from 100 mL to 70 mL.
- **Files changed:**
  - `Core/HealthKitManager.swift` — `sipVolume` constant updated
  - `project.pbxproj` — `NSHealthUpdateUsageDescription` strings updated (all 4 build configs)

## V1.3 Changes

### Lock Screen widget redesign
- **What:** Replaced the flat, non-informative lock screen widgets with battery-style gauges that reflect the current hydration level.
- **Circular** (`.accessoryCircular`): Now uses `Gauge` with `.accessoryCircularCapacity` — a circular progress ring that drains over 2 hours matching the hydration formula. Center shows `drop.fill` icon when hydrated (>0%), switches to "飲" when fully dehydrated (0%).
- **Rectangular** (`.accessoryRectangular`): Mirrors the iOS battery rectangular widget layout — line 1: drop icon + hydration percentage (e.g. "72%"); line 2: "Hydrated" when >0%, "Sip 飲" at 0%; line 3: `Gauge` with `.accessoryLinearCapacity` bar.
- **Tap behavior changed:** Lock screen widgets no longer log sips — tapping opens the app instead. Removed all `Button(intent:)` wrappers from accessory views; default WidgetKit tap-to-open behavior applies.

### Widget split into two configurations
- **What:** Split the single `AquaWidget` into two separate `Widget` structs so each gets its own description in the widget picker.
- **`SipHomeWidget`** (kind: `"AquaWidget"`, preserved for backward compatibility) — supports `.systemSmall`, `.systemMedium`. Display name: "Sip", description: "Track your hydration and log a sip from your Home Screen."
- **`SipStatusWidget`** (kind: `"SipStatusWidget"`, new) — supports `.accessoryCircular`, `.accessoryRectangular`. Display name: "Sip", description: "Your hydration level at a glance."
- `AquaWidgetBundle` updated to register both widgets.
- All `reloadTimelines(ofKind: "AquaWidget")` calls across the codebase replaced with `reloadAllTimelines()` so both widget kinds refresh after every sip.
- **Note:** Existing lock screen widgets will need to be re-added after update (new kind). Home screen widgets are unaffected.
- **Files changed:**
  - `AquaWidgetExtension/AquaWidget.swift` — circular/rectangular views rewritten, `AquaWidget` split into `SipHomeWidget` + `SipStatusWidget`, preview updated
  - `AquaWidgetExtension/AquaWidgetBundle.swift` — registers both widgets
  - `Core/SharedStorage.swift` — `reloadAllTimelines()`
  - `Core/SipIntents.swift` — `reloadAllTimelines()`
  - `Core/WaterStateViewModel.swift` — `reloadAllTimelines()`

### Daily sip count tracking
- **What:** Every sip increments a daily counter stored in App Group `UserDefaults`. The count resets automatically when the calendar day changes. A 7-day history dictionary (`[String: Int]`, date string → count) is maintained alongside, auto-pruning entries older than 7 days.
- **Widget display:** The sip count appears in the top-right of `.systemSmall` and `.systemMedium` Home Screen widgets (16pt bold rounded). Uses the same `headerColor` logic as the app name text — white on water, dark on dehydrated, dark-on-tinted — so it stays legible in all states.
- **Increment paths:** Count is incremented from all three sip entry points:
  - `SharedStorage.logWater()` (main app)
  - `LogWaterIntent.perform()` (widget background, inline `UserDefaults` logic)
  - `LogWaterAuthIntent.perform()` (widget auth-open, inline `UserDefaults` logic)
- **Files changed:**
  - `Core/SharedStorage.swift` — added `todaySipCount`, `incrementSipCount()`, `last7DaysSipCounts`, `previous6DayAverage`, `sipVolumeML`, `sipHistory` dictionary, date helpers
  - `Core/WaterStateViewModel.swift` — added `todaySipCount`, `last7Days`, `recentAverage`, `todayVolumeML`, `syncSipStats()` helper; synced on init, `refreshFromStorage()`, and `logWater()`
  - `AquaWidgetExtension/AquaWidget.swift` — `AquaWidgetEntry` gains `sipCount: Int`; `AquaTimelineProvider` reads count via `todaySipCount()` helper; `LogWaterIntent` gets inline `incrementSipCount(suite:)` method; sip count rendered in small/medium widget header
  - `Core/SipIntents.swift` — `LogWaterAuthIntent.perform()` increments count via inline `UserDefaults` logic

### Stats overlay (analytics view)
- **What:** Tapping the sip count number in the app header toggles a centered stats overlay. Tapping again (now an ✕ icon) dismisses it. The overlay displays three sections:
  1. **Sips today** — large 48pt bold rounded number + "Sips today" label
  2. **Total volume** — 40pt bold rounded number + "ml" unit + "In total" label (computed as `sipCount × 70`)
  3. **7-day bar chart** — 7 vertical bars (oldest left, today right); today's bar is wider and uses `primary` color, previous days are thinner and use `secondary` color; max bar height 40px; below the bars a comparison label ("More than 7-day avg." / "Less than 7-day avg." / "Start sipping to build your history" for new users)
- **Toggle UX:** The top-right element is a `Button` that swaps between the sip count number and an ✕ icon via `ZStack` + `opacity` with `.spring(duration: 0.35, bounce: 0.15)` animation. Both are in a fixed `frame(height: 27)` to prevent positional shift.
- **Description text:** All labels use `.font(.subheadline)`. The `secondaryAlt` parameter was removed — descriptions, "ml" unit, and past-day bars all share a single `secondary` color.
- **Stats overlay colors:** Dual-layer with wave-shape mask for pixel-perfect color split:
  - **Light background** (dehydrated): primary `#888888` (medium gray), secondary `#B9B7B6` (warm light gray)
  - **Dark background** (water filled): primary `.white`, secondary `#86C5F6` (light blue)
  - Past 6-day bars use the `secondary` color (matching descriptions); today's bar uses `primary` at full opacity.
- **Show/hide animation:** `.transition(.opacity.combined(with: .scale(scale: 0.92)))` on the overlay.

### Stats overlay blur effect
- **What:** When the stats overlay is open, everything except the close button (✕), the sip button, and the "Last sip" text is de-emphasized — creating a focused, modal-like feel.
- **Background blur:** The water fill + dehydrated background ZStack gets `.blur(radius: 20)` and `.scaleEffect(1.1)` when stats are shown. The scale pushes edges off-screen to prevent the white fringe artifact that SwiftUI blur creates at view boundaries.
- **Header title fade:** The app name ("Aqua"/"Sip") and Chinese character ("水"/"飲") fade out with `.opacity(0)` when stats are shown (blur was tried first but created an ugly text smudge artifact). The close button (✕) in the top-right stays fully visible and sharp.
- **Wave-shape mask unaffected:** The `waterShapeMask` renders its own independent `WaveShape` via `TimelineView` — it does not depend on the visual blur of the water fill. The text color split remains pixel-perfect even with the background blurred.
- **Animation:** All blur/opacity/scale changes animate with the same `.spring(duration: 0.35, bounce: 0.15)` transaction as the stats toggle.

### iOS home-indicator-style adaptive text color
- **What:** Header text and stats overlay text automatically switch between dark and white at the exact water boundary, matching the pixel-level behavior of the iOS home indicator bar. As the water wave animates, the color split tracks every frame.
- **How:** Dual-layer rendering — each text element (header, stats overlay) is rendered twice:
  1. **Dark layer** (base): dark text always visible, readable on the beige dehydrated background
  2. **White layer** (overlay): white text masked by `waterShapeMask` so it only appears where water covers the content
- **`waterShapeMask`:** Renders the exact same `WaveShape` used by the water fill — same `TimelineView(.animation(...))`, same `wavePhase` from wall-clock time, same `amplitude`, `frequency`, `bumpHeight`, `bumpWidth`. A `GeometryReader` reads the masked view's position in the `"root"` coordinate space and applies `.offset(y: -frame.minY)` so the mask aligns precisely with the background water. Both the header and stats overlay share this mask function.
- **Replaces:** The previous `onWater` boolean threshold, which caused readability issues when the water was at the header level.

### Adaptive sip button
- **What:** The sip button now adapts its color based on the water level, matching the widget's color logic so it stays visible in all states.
- **On water** (hydrated): white `drop.fill` icon + `Color.white.opacity(0.25)` translucent circle background — visible on the blue water.
- **Dehydrated:** `waterBlue` icon + `waterBlue.opacity(0.15)` translucent circle background — subtle on the beige background.
- **Replaces:** The previous solid `waterBlue` circle that was invisible when fully submerged in water.

### Sip sound effect
- **What:** A drinking/gulp sound plays when the user taps the sip button in the main app.
- **Implementation:** `AVAudioPlayer` loaded from a bundled `sip.mp3` (also checks for `.wav`/`.caf`). The player is a static property on `ContentView`, pre-loaded via `prepareToPlay()` for zero-latency playback. Sound resets (`currentTime = 0`) before each play to handle rapid taps.
- **Widget limitation:** Widget extensions cannot play audio — the sound only plays from the main app.
- **Sound asset:** `sip.mp3` — sourced from Pixabay (royalty-free, no attribution required).
- **Files changed:**
  - `ContentView.swift` — added `import AVFoundation`; static `sipSoundPlayer`; play call in `logWaterButton` action

### Theme infrastructure (foundation for v1.4 theme switching)
- **What:** Extracted all hardcoded RGB color literals into a centralized `AppTheme` model. Every color role in the app, widget, and welcome overlay now reads from the active theme instead of inline constants. The selected theme ID is stored in App Group `UserDefaults` so the widget stays in sync.
- **ThemeID enum:** `.default` (cream + blue, current look) and `.kurosawa` (grey + black, placeholder colors for v1.4).
- **AppTheme struct:** 19 color roles covering water fill, dehydrated background, header text (dual-layer dark/on-water), stats overlay (dual-layer), last-sip text, sip button, welcome accent, and preferred color scheme.
- **Theme storage:** `SharedStorage.selectedThemeID` (read/write) + `SharedStorage.currentTheme` (resolved `AppTheme`). Setting the theme ID triggers `reloadAllTimelines()`.
- **ViewModel:** `WaterStateViewModel.theme` property, synced on init and `refreshFromStorage()`.
- **Widget:** `AquaWidgetEntry` carries `themeID`; `AquaTimelineProvider` reads it from the shared suite; `AquaWidgetView` resolves `AppTheme.forID(entry.themeID)` and uses theme colors for all non-tinted rendering. Tinted-mode colors remain system-driven.
- **No visual change:** The default theme reproduces the exact same cream-and-blue colors. The app looks identical to before.
- **Files changed:**
  - `Core/AppTheme.swift` — new, **must be added to both app and widget targets in Xcode**
  - `Core/SharedStorage.swift` — added `selectedThemeID`, `currentTheme`
  - `Core/WaterStateViewModel.swift` — added `theme` property, synced on refresh
  - `ContentView.swift` — replaced all inline colors with `theme.*` properties, `preferredColorScheme` from theme
  - `AquaWidgetExtension/AquaWidget.swift` — removed module-level color constants, added `themeID` to entry/provider, replaced inline colors with theme lookups
  - `UI/WelcomeOverlay.swift` — accepts `theme: AppTheme` parameter, uses theme colors

### Stats overlay polish
- **Blurred water mask on stats:** The dual-layer water shape mask on the stats overlay now uses `.blur(radius: 30)`, creating a soft gradient blend between dark and light colors. This prevents the bar chart from looking like bars are partially "filled" when the water wave intersects them. The header keeps the sharp pixel-perfect split.
- **Sip count weight:** Changed from `.bold` to `.semibold`.
- **Sip count / close button color:** On the dehydrated (cream) background, the sip count number and close button (✕) now use `#888888` (`statsPrimary`) instead of near-black `headerPrimary`. A new `buttonColor` parameter was added to `headerContent` to decouple the button color from the app name color. On water they remain white.

### Adjustable sip volume
- **What:** Users can now adjust the per-sip water volume (default 70ml). An info button (`info.circle`, 20px semibold, `primary` color) appears next to "ml" in the stats overlay. Tapping it opens a full-page sheet.
- **Sheet UI:** Navigation bar with "Sip Volume" title; iOS 26 liquid glass circular close button (✕, top left) and blue prominent save button (✓, top right). Center shows the volume with `(−)` and `(+)` circle buttons in iOS blue, stepping by 10ml. Minimum is 70ml (minus button disabled and faded at floor). "Each sip" label below the stepper. Footnote at the bottom: "Default sip is 70ml. Changes will apply from the next sip onward — previous sips keep their original amount."
- **Volume accumulation:** Total mL is now tracked as a running accumulator (`todayTotalVolumeML`) rather than `sipCount × currentVolume`. Each sip adds whatever the volume setting was at that moment. Changing the volume does **not** retroactively recalculate past sips — only future sips use the new amount.
- **Migration:** For users who upgrade mid-day with existing sip count data but no volume tracking, the system assumes those sips were at 70ml (the original default). The first new sip after the update accumulates correctly on top.
- **Storage:** `SharedStorage.sipVolumeML` changed from a hardcoded `let = 70` to a read/write App Group `UserDefaults` property (default 70). `SharedStorage.todayTotalVolumeML` is a new accumulated value that resets on day change.
- **HealthKit:** `HealthKitManager.sipVolume` now reads the user's chosen volume from App Group UserDefaults (reads directly, not via SharedStorage, since SharedStorage isn't in the widget target).
- **All 3 sip entry points updated:** `SharedStorage.incrementSipCount()` (main app), `LogWaterIntent.incrementSipCount(suite:)` (widget background), `LogWaterAuthIntent.perform()` (widget auth-open) — all accumulate actual volume alongside the sip count.
- **Files changed:**
  - `Core/SharedStorage.swift` — `sipVolumeML` read/write property, `todayTotalVolumeML` accumulator, volume accumulation in `incrementSipCount()`
  - `Core/WaterStateViewModel.swift` — `sipVolumeML` and `todayVolumeML` as stored properties synced from SharedStorage
  - `Core/HealthKitManager.swift` — `sipVolume` reads from UserDefaults instead of hardcoded 70
  - `ContentView.swift` — `SipVolumeSheet` view, `showVolumeSheet` state, info button in stats, `.sheet` modifier, blurred stats mask, header `buttonColor` parameter
  - `AquaWidgetExtension/AquaWidget.swift` — volume accumulation in inline `incrementSipCount`
  - `Core/SipIntents.swift` — volume accumulation in `LogWaterAuthIntent`

### V1.3 files changed (cumulative)
- `Core/AppTheme.swift` — new (theme model + default/kurosawa definitions)
- `Core/SharedStorage.swift` — theme storage, adjustable sip volume, volume accumulator
- `Core/WaterStateViewModel.swift` — theme property, sip volume + accumulated volume properties
- `Core/HealthKitManager.swift` — dynamic sip volume from UserDefaults
- `Core/SipIntents.swift` — volume accumulation in auth intent
- `ContentView.swift` — theme-driven colors, stats overlay polish, adjustable sip volume sheet, blur effect, header title fade, adaptive sip button, sip sound, `import AVFoundation`
- `AquaWidgetExtension/AquaWidget.swift` — theme-aware widget rendering, volume accumulation
- `UI/WelcomeOverlay.swift` — theme-aware welcome overlay
- `sip.mp3` — bundled sound asset (app target only)

## V1.4 Planned Tasks
1. **Kurosawa theme** — finalize the grey + black palette for all 19 color roles, create Kurosawa app icon asset.
2. **Swipe-to-switch UI** — horizontal swipe gesture (Instagram-story style) to preview and select themes.
3. **StoreKit 2 in-app purchase** — pay-to-unlock Kurosawa theme, with restore-purchase support.
4. **App icon switching** — `setAlternateIconName()` to swap icon when theme changes.
5. **Lock indicator** — show lock icon on unpurchased themes in the swipe UI.
