# Sip App Context

## Overview
Sip is a minimal water-tracking iOS app. Tap a button, log a sip, watch the screen fill with water that drains over 2 hours. A Home/Lock Screen widget mirrors hydration and lets you log directly. App name toggles: **"Aqua"** (水) when hydrated, **"Sip"** (飲) when dehydrated. Bilingual EN + 中文 throughout.

## Tech
- **Platform:** iOS 26.2, iPhone & iPad
- **Language:** Swift 5, `@Observable`, async/await, App Intents
- **UI:** SwiftUI only, fixed light color scheme (theme-driven)
- **Architecture:** MVVM — `WaterStateViewModel` (`@Observable`) drives `ContentView`
- **Persistence:** `UserDefaults` via App Group (`group.andychudesign.Aqua`), shared between app and widget
- **Widget:** `AquaWidgetExtension` — `SipHomeWidget` (small/medium) + `SipStatusWidget` (circular/rectangular accessory)
- **Fonts:** Inter-Medium app-wide (referenced via `Font.custom("Inter-Medium", ...)` — **not yet bundled**, silently falls back to system). Crimson Text Regular + SemiBold bundled in `aqua/Resources/Fonts/` and registered at launch via `CTFontManagerRegisterFontsForURL` (see `BundledFonts.registerAll()` in `aquaApp.swift`, called from `aquaApp.init()`), used for the Kurosawa theme name in the gallery preview.
- **Frameworks:** SwiftUI, Foundation, WidgetKit, AppIntents, HealthKit, AVFoundation, CoreText

## Core Logic
- **Single data point:** `lastWaterLogTime` (Date in shared App Group `UserDefaults`)
- **Hydration formula:** `hydrationLevel = max(0, 1 - elapsed / 7200)` — linear decay 1.0 → 0.0 over 2 hours
- **Log sip:** Sets `lastWaterLogTime` to now → hydration jumps to 1.0 → begins draining
- **Refresh:** 1s timer in VM recalculates `hydrationLevel`; refreshes on `scenePhase == .active`
- **Widget sync:** `WidgetCenter.shared.reloadAllTimelines()` after each log; provider pre-computes 5-minute drain entries

## Key Files
- `Core/AppTheme.swift` — theme model (`.default` cream+blue, `.kurosawa` charcoal+stone); 19 color roles. `ThemeID: Identifiable` with `displayName` + bilingual `nameChinese` (e.g. "Kurosawa" / "黑澤")
- `Core/SharedStorage.swift` — App Group `UserDefaults` wrapper; `lastWaterLogTime`, `fillStartLevel`, `selectedThemeID`, `currentTheme`, `unlockedThemeIDs` / `isUnlocked()` / `unlock()`, `sipVolumeML` (rw, default 70), `todayTotalVolumeML` accumulator, `todaySipCount`, `sipHistory` (7-day dict), `incrementSipCount()`, `last7DaysSipCounts`, `previous6DayAverage`
- `Core/WaterStateViewModel.swift` — `@Observable` VM; `hydrationLevel`, `theme`, `unlockedThemeIDs`, `applyTheme(_:)`, `unlockTheme(_:)`, `todaySipCount`, `last7Days`, `recentAverage`, `todayVolumeML`, `sipVolumeML`, `logWater()`, `refreshFromStorage()`, `syncSipStats()`
- `Core/HealthKitManager.swift` — `saveSip(requestAuth:)`; reads `sipVolumeML` from UserDefaults directly (not in widget target via SharedStorage)
- `Core/SipIntents.swift` — `LogWaterAuthIntent` (`openAppWhenRun = true`, foreground HealthKit auth + sip)
- `ContentView.swift` — main UI, stats overlay, `SipVolumeSheet`, dual-layer water-mask text rendering, sip sound (`AVAudioPlayer` from `sip.mp3`)
- `UI/WelcomeOverlay.swift` — first-launch welcome (theme-aware)
- `AquaWidgetExtension/AquaWidget.swift` — `SipHomeWidget` + `SipStatusWidget`, `AquaTimelineProvider`, `LogWaterIntent` (background), entry carries `themeID` + `sipCount` + `needsHealthKitAuth`
- `AquaWidgetExtension/AquaWidgetBundle.swift` — registers both widgets
- `aqua.entitlements` + `AquaWidgetExtension.entitlements` — App Group + HealthKit

## Current State (through V1.3)

### Visual / UX
- **Water fill:** `WaveShape` (dual sine waves + Gaussian bump under sip button); `TimelineView(.animation)` drives `wavePhase` from wall-clock time (immune to other animation transactions)
- **Adaptive header text:** Dual-layer rendering — dark base + white overlay masked by `waterShapeMask` (same `WaveShape` aligned via GeometryReader in `"root"` coordinate space). Pixel-perfect color split tracking the wave every frame, like iOS home indicator
- **Adaptive sip button:** White icon + `white.opacity(0.25)` bg on water; `waterBlue` icon + `waterBlue.opacity(0.15)` bg dehydrated
- **Sip sound:** `AVAudioPlayer` static, pre-loaded `sip.mp3`, plays on tap (app only — widgets can't play audio)
- **Welcome flow:** 3-phase overlay on first launch, gated by `@AppStorage("hasSeenWelcome")`

### Stats overlay
- Tap sip count in header → centered overlay (sips today 48pt, total ml 40pt + info button, 7-day bar chart)
- Today's bar: wider, `primary` color; past bars: thinner, `secondary` color; max 40px height; comparison label vs 7-day avg
- Background `.blur(radius: 20).scaleEffect(1.1)` when open; header app name fades to opacity 0; close ✕ stays sharp
- Stats text uses dual-layer water-mask, but mask is `.blur(radius: 30)` for soft gradient blend (prevents bar-chart filling artifact)
- Sip count weight `.semibold`; on dehydrated bg uses `statsPrimary` (#888888), on water uses white
- Toggle animation: `.spring(duration: 0.35, bounce: 0.15)`

### Adjustable sip volume (V1.3)
- Info button in stats opens full-page sheet; `(−)/(+)` 10ml stepper, min 70ml, iOS 26 liquid glass close + blue save buttons
- `todayTotalVolumeML` accumulates actual volume per sip — changing volume does NOT retroactively recalculate
- Migration: pre-update sips assumed at 70ml
- All 3 sip entry points accumulate volume: `SharedStorage.incrementSipCount()`, `LogWaterIntent.incrementSipCount(suite:)`, `LogWaterAuthIntent.perform()`

### HealthKit
- Each sip writes a `dietaryWater` sample (volume from `sipVolumeML`)
- First in-app sip triggers auth sheet; widget can't present UI
- **Two-intent pattern:** `LogWaterAuthIntent` (`openAppWhenRun = true`) opens app for first auth → sets `"healthKitAuthResolved"` flag. After that, widget uses background `LogWaterIntent`. Widget view conditionally picks intent based on flag in entry's `needsHealthKitAuth`
- Widget extension target needs `INFOPLIST_KEY_NSHealthUpdateUsageDescription` set in Debug + Release build settings
- `HealthKitManager` is NOT `@MainActor` (HKHealthStore is thread-safe); widget calls `saveSip(requestAuth: false)`

### Widgets
- **`SipHomeWidget`** (kind `"AquaWidget"`): small/medium, shows water fill + app name + sip count (top-right, 16pt bold rounded). Sip count uses same `headerColor` logic as app name (legible in tinted mode too)
- **`SipStatusWidget`** (kind `"SipStatusWidget"`): circular uses `Gauge .accessoryCircularCapacity` + drop icon (or 飲 at 0%); rectangular uses `Gauge .accessoryLinearCapacity` + percent + label. Tap opens app (no log intent on lock screen)
- Tinted mode: `.containerBackgroundRemovable(false)`, `dehydratedBg.widgetAccentable()` so bg gets tint, water stays lighter
- **Theme-aware:** `AquaWidgetEntry` carries `themeID`; `AppTheme.forID()` resolves colors. Tinted mode stays system-driven
- Lock-screen timeline: single entry at `now` (no sub-second fill-ramp — iOS throttles accessory widgets), then 5-min drain entries

### Theme infrastructure (V1.3 — foundation for V1.4)
- `AppTheme` struct with 19 color roles: water fill, dehydrated bg, header (dark+on-water), stats (dark+on-water), last-sip text, sip button, welcome accent, preferred color scheme
- `ThemeID`: `.default` (current cream+blue look) + `.kurosawa` (grey+black placeholder)
- `SharedStorage.selectedThemeID` rw + `currentTheme` resolved; setting ID triggers `reloadAllTimelines()`
- VM `theme` property synced on init + refresh
- All inline RGB literals across app + widget + welcome replaced with `theme.*`
- Default theme reproduces exact previous look (no visual change)

## V1.4 Completed

### Session log — Theme system shipped (May 2026)

The V1.3 foundation (theme model + storage + inline swipe preview) was extended into a **discoverable, polished theme-picking flow**:

1. **Discoverability** — `logWaterButton` is now flanked by two smaller secondary circle buttons in a `controlRow` HStack. Left (`plusminus`) opens `SipVolumeSheet`; right (`circle.righthalf.filled`) opens the new `ThemeGalleryView`. The old "info button inside stats overlay → volume sheet" path was removed (single, primary entry point per action).
2. **Sip button identity** — `AppTheme` gained `buttonPrimary{Foreground,Background}`, used only by `logWaterButton`. Stable across hydration states so the center action always reads as a solid high-contrast circle (no more white-on-white).
3. **`ThemeGalleryView`** — full-screen `.fullScreenCover`, modeled on iOS's lock-screen wallpaper picker: black canvas, custom top bar with glass `xmark` close button matching `SipVolumeSheet`, peek-style horizontal carousel (`GeometryReader`-driven, 82% card width with computed `sideInset` padding so first/last cards center), animated wave inside each card, custom page-indicator dots, dynamic "Set \<name\> as theme" / "Unlock \<name\>" / "Applied" pill. Gallery always opens centered on the **currently-applied theme** (uses a `nil → appliedID` state transition in `.onAppear` to work around `scrollPosition(id:)`'s flaky handling of initial values when content layout depends on a `GeometryReader`).
4. **Typography per theme** — `ThemeID.previewNameFont` returns `Inter-Medium 18pt` for `.default` and `CrimsonText-Regular 18pt` for `.kurosawa`. Same point size for both themes so the name slot has stable optical height; only the family changes.
5. **Real fonts bundled** — `CrimsonText-Regular.ttf` + `CrimsonText-SemiBold.ttf` (Google Fonts OFL) live in `aqua/Resources/Fonts/`. `INFOPLIST_KEY_UIAppFonts` was tried but is silently dropped by Xcode 26's auto-Info-plist generator, so we register via `CTFontManagerRegisterFontsForURL(..., .process, ...)` in `BundledFonts.registerAll()`, called from `aquaApp.init()`.

**Inline swipe-to-preview flow removed (v1.4)** — `ThemeGalleryView` is now the only theme-switching surface. The old horizontal `DragGesture` on the root, `previewThemeID` state, `themeSwipeGesture`, `cyclePreview(direction:)`, `applyThemePill(for:)`, and all `isPreviewing`-branches in `theme` / `hydrationLevel` / `headerTitle` / `headerSubtitle` / `headerContent` / `controlRow` / `bumpH` are gone. `bottomBar` is now just `lastLogText`. Removed because the gallery covered the same use case while accidental horizontal swipes could drop users into preview mode unexpectedly.

---

- **Bundled fonts via runtime registration** — `aqua/Resources/Fonts/CrimsonText-Regular.ttf` and `CrimsonText-SemiBold.ttf` (Google Fonts, OFL) are auto-included by `PBXFileSystemSynchronizedRootGroup` and flatten to the bundle root. Xcode's `INFOPLIST_KEY_UIAppFonts` build setting was tried but is **silently dropped** by the auto-Info-plist generator in this project's setup — verified by inspecting `Info.plist` in the built `.app`. Solution: register at startup via `CTFontManagerRegisterFontsForURL(...,  .process, ...)` in a `BundledFonts.registerAll()` helper called from `aquaApp.init()`. PostScript names: `CrimsonText-Regular`, `CrimsonText-SemiBold`. Note: `Inter-Medium` referenced throughout the app via `Font.custom("Inter-Medium", ...)` is **not bundled** and silently falls back to the system font — could be added to the same `BundledFonts` helper if/when the actual Inter font file is dropped into `aqua/Resources/Fonts/`.

- **Three-button control row** — `logWaterButton` is now flanked by two smaller secondary circle buttons in a new `controlRow` HStack (spacing 28):
  - **Left: `sipVolumeButton`** (`plusminus` SF Symbol) — opens `SipVolumeSheet` directly. Replaces the old in-stats info-button entry point, which has been removed.
  - **Right: `themeSwitchButton`** (`circle.righthalf.filled`) — taps clear any inline `previewThemeID` and present the `ThemeGalleryView` sheet (see below). Swipe gesture is retained as a parallel power-user shortcut; the swipe guard now also includes `!showThemePicker`.
  - Both secondary buttons render via `secondaryCircleButton(systemImage:accessibilityLabel:action:)`: 16pt semibold icon, 14pt padding, theme-aware `buttonForeground`/`buttonBackground` (and `*OnWater` variants) — same hydration-driven color swap as the sip button, just smaller (~48pt outer vs. sip button's ~64pt) so the center button stays primary.
  - The bump-tracking `ButtonFrameKey` GeometryReader stays attached to the center sip button, so water-bump positioning is unchanged. (Previous v1.4 versions had `.opacity(isPreviewing ? 0 : 1)` + `.allowsHitTesting(!isPreviewing)` on the two non-theme buttons to hide them during inline swipe-preview; removed alongside the swipe flow.)
  - Accessibility labels: "Adjust sip amount", "Change theme".
- **Control-row color swap is gated by actual water coverage, not hydration > 0** — `body`'s GeometryReader computes `buttonsOnWater = hydrationLevel > 0 && buttonFrame != .zero && waterSurfaceY <= buttonFrame.midY` (root coordinate space). This bool is threaded into `controlRow(buttonsOnWater:)`, `bottomBar(onWater:)`, `logWaterButton(onWater:)`, `secondaryCircleButton(onWater:)`, and `lastLogText(onWater:)`. Previously these all keyed off `hydrationLevel > 0`, which caused the side buttons + last-sip caption to flip to their translucent-on-water styling the moment any water appeared at the bottom of the screen — making them invisible against the cream/stone background until water actually rose over them. The swap now happens once roughly half the button row is underwater, with a `.animation(.easeInOut(duration: 0.35), value: onWater)` modifier on each button (and 0.3 on the caption) for a smooth crossfade.
- **Primary sip button has a dehydrated + on-water identity** — `logWaterButton(onWater:)` renders **solid `theme.waterColor` background + white droplet** when water is below the row (high-contrast CTA on the dehydrated canvas — see Aqua's blue circle / Kurosawa's charcoal circle in the user's reference) and **`buttonPrimary{Foreground,Background}`** (white bg + tinted droplet) once water covers it. The earlier "stable in both states" model from V1.4 step 1 was retired in favor of this swap because at low water levels the white-on-cream droplet read as washed-out.
- **New `buttonSubtle{Foreground,Background}` tokens for the side buttons** — `sipVolumeButton` + `themeSwitchButton` render in subordinate gray when dehydrated so they don't compete with the central sip button: `Color(white: 0.5)` on `Color.black.opacity(0.10)` for default, `Color(white: 0.30)` on `Color.black.opacity(0.10)` for Kurosawa. These are **deliberately distinct from `buttonForeground/Background`** (which the widget extension keeps reusing for its dehydrated drop icon and intentionally tints toward the brand water color); changing one surface shouldn't leak into the other. On-water styling is unchanged (still `buttonForegroundOnWater` / `buttonBackgroundOnWater`).
- **`ThemeGalleryView` full-screen picker** — iOS-lock-screen-wallpaper-style theme gallery (`ContentView.swift`, presented via `$showThemePicker` using `.fullScreenCover`, not `.sheet`):
  - **Black canvas** — `Color.black.ignoresSafeArea()` + `.preferredColorScheme(.dark)` so the gallery has its own dark "customisation surface" identity regardless of the app's selected theme.
  - **Custom top bar** — centered "Themes" title, circular `xmark` close button on the right using `.buttonStyle(.glass)` + `.buttonBorderShape(.circle)` + `.controlSize(.large)`, which together match the size and Liquid Glass look of the SipVolumeSheet toolbar close button (toolbars in iOS 26 effectively give their `.cancellationAction` items the `.large` glass control size). Top bar height grew from 44 → 52 to accommodate. Dismisses via `@Environment(\.dismiss)`. No `NavigationStack`.
  - **Peek-style carousel** — `GeometryReader`-wrapped horizontal `ScrollView` with `LazyHStack(spacing: 12)`. Each card has explicit `frame(width: cardWidth)` where `cardWidth = proxy.size.width * 0.82`; the HStack has `.padding(.horizontal, sideInset)` where `sideInset = (proxy.size.width - cardWidth) / 2`. This padding gives the first/last cards enough slack so `scrollPosition(id: $scrolledID, anchor: .center)` actually centers them (without it, the first card would stick to the leading edge). Snap behavior: `.scrollTargetBehavior(.viewAligned)` + `.scrollTargetLayout()` on the HStack. Vertical paddings around the carousel + page indicator + action pill were tightened to give the cards ~50pt more height (closer to the iOS lock-screen reference's tall-card ratio).
  - **Open-on-applied-theme** — `scrolledID` (`@State ThemeID?`) **starts as `nil`** and is assigned `appliedID` in `.onAppear`. The seemingly-roundabout flow exists because `scrollPosition(id:)` doesn't reliably honor the *initial value* of its binding when the scroll content's layout depends on a `GeometryReader` (race: state set → ScrollView tries to scroll → LazyHStack hasn't measured yet → silent failure). Letting the value change *after* layout forces a real state transition the ScrollView observes. `selectedID = scrolledID ?? appliedID` keeps the page indicator + action pill on the applied state from frame zero, so there's no flash of the wrong selection while the scroll settles.
  - **`ThemePreviewCard` (stripped)** — only renders **theme name** (display + Chinese, top-left) and **animated water level**. Theme name font is picked per-theme via `ThemeID.previewNameFont`, always at **18pt** so the name slot has a stable optical height across cards (only the family differs): `.default` uses `Font.custom("Inter-Medium", size: 18)` (silently falls back to system since Inter is not yet bundled), `.kurosawa` uses `Font.custom("CrimsonText-Regular", size: 18)` for a distinctive serif/editorial feel that pairs with the charcoal palette. Chinese subtitle is a uniform `Font.system(size: 18, weight: .medium)` for both themes. Water is a ~40% fill driven by `TimelineView(.animation)` with the same wave-phase math as the main app, so each visible card has its own live wave. Card uses 36pt continuous corner radius. **No** mini sip button, **no** applied checkmark inside the card — the action pill below already conveys applied state.
  - **Page indicator** — custom `HStack` of 7pt circles (white when selected, `white.opacity(0.3)` otherwise) with `.easeInOut(0.2)` animation keyed on `selectedID`.
  - **Action pill** — full-width capsule. Label/icon from `actionPillContent` tuple. States: "Applied" (translucent white bg/fg, disabled), "Unlock \<name\>" (`lock.open.fill`, still free until StoreKit), "Set \<name\> as theme" (commits via `viewModel.applyTheme` then dismisses). Non-applied pill uses the selected theme's `dehydratedBackground` as fill + `headerPrimary` as text — a colored hint of the theme on the dark canvas.
  - The previous inline swipe-to-preview shortcut has been removed; the gallery is now the only entry point. See "Inline swipe-to-preview flow removed (v1.4)" above.
- **Bug 7 fix:** Lock-screen accessory widgets stuck at 0% after sip — removed unreliable sub-second fill-ramp entries; timeline now starts with single entry at `now` (already ~1.0 post-sip), then standard 5-min drain. WidgetKit handles transitions. (`AquaWidgetExtension/AquaWidget.swift`)
- **Theme switching (visual half of v1.4 theme feature):**
  - **Kurosawa palette finalized** — light scheme, charcoal water (`white: 0.10`) on warm stone background (`#E3E0DB`); see `Core/AppTheme.swift`. `ThemeID` is `Identifiable` with `displayName` (English) + `nameChinese` (e.g. "Kurosawa" / "黑澤") used in the gallery card header.
  - **Single entry point: `ThemeGalleryView`** — tapping `themeSwitchButton` in the `controlRow` opens the gallery via `.fullScreenCover`. The earlier inline swipe-to-preview/apply prototype (root `DragGesture` + `previewThemeID` + apply-pill in the bottom bar) was removed; see the dedicated "Inline swipe-to-preview flow removed" note above.
  - **`ContentView` computed simplifications post-removal**:
    - `theme: AppTheme` — returns `viewModel.theme` directly.
    - `hydrationLevel: Double` — pass-through to `viewModel.hydrationLevel`.
    - `headerTitle` / `headerSubtitle` — only `Aqua / 水` ↔ `Sip / 飲` based on hydration.
    - `bottomBar` — always renders `lastLogText`.
    - `controlRow` — `sipVolumeButton` and `logWaterButton` are always visible/interactive; no preview-hiding modifiers.
    - `bumpH` — depends only on `hydrationLevel > 0` and a valid `buttonFrame`.
  - **Unlocks storage** — `SharedStorage.unlockedThemeIDs` (`Set<ThemeID>`, App Group), `isUnlocked()`, `unlock()` helpers. `.default` always included. Currently unlocking is free (placeholder) — when StoreKit 2 ships, hook a verified `Transaction` listener to `unlockTheme()` instead.
  - **VM hooks** — `WaterStateViewModel.unlockedThemeIDs`, `applyTheme(_:)`, `unlockTheme(_:)`; synced on `refreshFromStorage()`.
  - **No widget impact** — theme already flows through to widgets via `selectedThemeID` setter (`reloadAllTimelines()`).
- **Project membership fix** — `ContentView.swift` was accidentally added to the widget extension's `membershipExceptions` in `aqua.xcodeproj/project.pbxproj`, causing "Cannot find 'WaterStateViewModel' in scope" build errors when the widget tried to compile `ContentView`. Removed. The exceptions list correctly contains only `Core/AppTheme.swift`, `Core/HealthKitManager.swift`, `Core/SipIntents.swift` — all genuinely shared with the widget.

- **Adaptive status bar glyphs (UIKit window trait, NOT SwiftUI's `.preferredColorScheme`)** — the time, signal, wifi, and battery icons flip between dark and light content the moment the water surface rises into the status bar's safe-area inset, restoring legibility against both themes' dark `waterColor` (Default's deep blue and Kurosawa's near-black). This took **three attempts** because SwiftUI's `.preferredColorScheme` bridge to UIKit's status bar is fundamentally broken for dynamic updates in our setup — the saga is worth recording in detail because every "obvious" fix runs into the same wall.

  - **Geometry check (unchanged across all three attempts):** `ContentView`'s outer `GeometryReader` computes `waterCoversStatusBar = waterSurfaceY <= max(0, statusBarBottom - 6)`. The 6pt padding completes the swap a beat before the wave's trough would otherwise expose the light `dehydratedBackground` under the glyphs.

  - **Attempt 1 — conditional `.preferredColorScheme` (FAILED, partial).** The first attempt was `.preferredColorScheme(waterCoversStatusBar ? .dark : theme.preferredColorScheme)` on the root view, with a `.animation(.easeInOut(duration: 0.25), value: waterCoversStatusBar)` modifier. This **worked for ~1 second after a sip and then snapped back to dark glyphs**. SwiftUI's bridge from `.preferredColorScheme` to `UIHostingController.preferredStatusBarStyle` fires at initial render but doesn't reliably re-propagate when the bound value changes mid-session — when the VM's 1s refresh timer ticked and rebuilt the body, the bridge didn't re-push and UIKit reverted.

  - **Attempt 2 — custom `UIHostingController` subclass (FAILED, no effect).** Switched `aquaApp.swift` from SwiftUI `App`/`WindowGroup` to a UIKit `@main AppDelegate` + `SceneDelegate` that installed a `SipHostingController<ContentView>` as the root view controller, with `preferredStatusBarStyle` reading from a `@MainActor StatusBarStyleController` singleton. `ContentView` pushed `.lightContent`/`.darkContent` via `.onChange` + `.onAppear`; the singleton's `didSet` walked every `UIWindowScene` and called `setNeedsStatusBarAppearanceUpdate()` inside a `UIView.animate(withDuration: 0.25)`. Even after also overriding `childForStatusBarStyle` to return `nil` (so the hidden SwiftUI child controller couldn't intercept), **glyphs stayed dark**. Most likely cause: the surviving `.preferredColorScheme(theme.preferredColorScheme)` on the root view was *still* bridging an explicit `preferredStatusBarStyle = .darkContent` into our subclass — and an explicit return value beats trait-based fallback every time. (Independently, `INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES` may have generated a scene manifest that bypassed our `application(_:configurationForConnecting:)` and re-installed a default SwiftUI hosting controller; never definitively confirmed because attempt 3 sidestepped the question.)

  - **Attempt 3 — `UIWindow.overrideUserInterfaceStyle`, no SwiftUI bridge (SHIPPED).** Reverted `aquaApp.swift` back to the simple SwiftUI `App` / `WindowGroup` lifecycle — `BundledFonts.registerAll()` is back in `aquaApp.init()`, and the entire `AppDelegate`/`SceneDelegate`/`SipHostingController`/`StatusBarStyleController` stack is gone. **Dropped `.preferredColorScheme(theme.preferredColorScheme)` from `ContentView` entirely.** With no explicit style coming from SwiftUI, `preferredStatusBarStyle` falls back to `.default`, which UIKit resolves against the trait collection — and the trait collection is exactly what `UIWindow.overrideUserInterfaceStyle` controls (the same hook the home indicator's automatic contrast adapt hangs off of). New `ContentView.setStatusBarLightContent(_:)` helper finds the key window via `UIApplication.shared.connectedScenes` and swaps its `overrideUserInterfaceStyle` between `.light` (default — also pins the app to its intended light identity for users on system-wide Dark Mode) and `.dark` (water covers status bar → trait collection becomes dark → glyphs render light). Wrapped in `UIView.animate(withDuration: 0.3)` so the fade is in lockstep with the rising water. Driven by `.onChange(of: waterCoversStatusBar)` + `.onAppear` on the root view.

  - **Side effect of dropping `.preferredColorScheme(.light)`: `SipVolumeSheet` would inherit the dark trait** while presented during the brief high-water window, dragging its `.secondary` / `.tertiary` text and system-coloured `NavigationStack` chrome into dark mode. **Fix:** pinned `SipVolumeSheet` itself to `.preferredColorScheme(.light)`. `ThemeGalleryView` was already `.preferredColorScheme(.dark)` so it's unaffected. `ContentView` only uses explicit theme colours so it doesn't care which way the trait goes.

  - **Key takeaway for future status-bar work in this codebase:** if you find yourself reaching for `.preferredColorScheme(...)` to control the iOS status bar, **don't** — it's the trap that ate two attempts here. Use `UIWindow.overrideUserInterfaceStyle` with `preferredStatusBarStyle` falling back to `.default`, and pin individual surfaces with their own `.preferredColorScheme` modifier when they need to opt out of the window-wide trait.

## V1.4 Remaining Tasks
1. **StoreKit 2 IAP** — pay-to-unlock Kurosawa theme + restore-purchase. Wire `WaterStateViewModel.unlockTheme()` to a verified `Transaction` listener; replace the free `onUnlock` callback in `ThemePickerSheet` with a real purchase flow (or surface a "Restore" affordance). Storage layer (`unlockedThemeIDs`) is already in place.
2. **App icon switching** — `setAlternateIconName()` swap on theme apply. Requires Xcode `CFBundleIcons` / `CFBundleAlternateIcons` plist entries + Kurosawa icon asset.
3. **Kurosawa app icon asset** — design + add to assets.
4. **Widget header readability** — tune `headerOnWater` threshold (currently `> 0.8`) so app name + sip count only switch to on-water colors when water actually reaches them.
5. **Stats overlay wave-mask** — keep dual-layer dehydrated + on-water rendering with blurred `waterShapeMask` (don't revert to single `>50%` threshold).
