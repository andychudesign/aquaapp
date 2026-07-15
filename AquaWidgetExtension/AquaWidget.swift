//
//  AquaWidget.swift
//  AquaWidgetExtension
//

import AppIntents
import HealthKit
import WidgetKit
import SwiftUI

private let appGroupID = "group.andychudesign.Aqua"
private let hydrationDuration: TimeInterval = 7200

// MARK: - App Intent

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "I drank water"

    func perform() async throws -> some IntentResult {
        SharedStorage.recordSip()
        _ = await HealthKitManager.saveSip(requestAuth: false)
        // Reload each widget kind exactly once, after all shared state is
        // committed (including the HealthKit auth flag, which decides which
        // intent the button binds to).
        //
        // The home widget that owns the tapped button is auto-reloaded by
        // WidgetKit when this intent returns; the lock-screen (accessory)
        // widgets do not contain the button, so they depend entirely on
        // these explicit reloads — which are metered by WidgetKit's
        // per-widget reload budget.
        //
        // Previously this site charged the accessory budget 3× per sip
        // (`reloadAllTimelines()` + two `reloadTimelines(ofKind:)` calls).
        // With two lock-screen widgets installed and several sips logged in
        // quick succession, the budget was exhausted almost immediately and
        // subsequent accessory reloads were silently dropped, freezing the
        // lock-screen water level/status. A single charge per kind keeps the
        // reliable per-kind delivery while leaving ample budget headroom.
        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
        return .result()
    }
}

// MARK: - Timeline

struct AquaWidgetEntry: TimelineEntry {
    let date: Date
    let hydrationLevel: Double
    let needsHealthKitAuth: Bool
    let sipCount: Int
    let themeID: ThemeID
}

struct AquaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AquaWidgetEntry {
        AquaWidgetEntry(date: Date(), hydrationLevel: 0, needsHealthKitAuth: false, sipCount: 0, themeID: Self.selectedThemeID())
    }

    func getSnapshot(in context: Context, completion: @escaping (AquaWidgetEntry) -> Void) {
        let suite = UserDefaults(suiteName: appGroupID)
        let authResolved = suite?.bool(forKey: "healthKitAuthResolved") ?? false
        completion(AquaWidgetEntry(date: Date(), hydrationLevel: Self.hydrationLevel(at: Date()), needsHealthKitAuth: !authResolved, sipCount: Self.todaySipCount(), themeID: Self.selectedThemeID()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AquaWidgetEntry>) -> Void) {
        let now = Date()
        let suite = UserDefaults(suiteName: appGroupID)
        let needsAuth = !(suite?.bool(forKey: "healthKitAuthResolved") ?? false)
        let sipCount = Self.todaySipCount()
        let themeID = Self.selectedThemeID()
        // Home-only ramp gate — see comment on the `if isHome ...` branch below.
        let isHome = context.family == .systemSmall || context.family == .systemMedium

        guard let logTime = suite?.object(forKey: "lastWaterLogTime") as? Date else {
            completion(Timeline(
                entries: [AquaWidgetEntry(date: now, hydrationLevel: 0, needsHealthKitAuth: needsAuth, sipCount: sipCount, themeID: themeID)],
                policy: .after(now.addingTimeInterval(60))
            ))
            return
        }

        let elapsed = now.timeIntervalSince(logTime)
        let endTime = logTime.addingTimeInterval(hydrationDuration)

        guard elapsed < hydrationDuration else {
            completion(Timeline(
                entries: [AquaWidgetEntry(date: now, hydrationLevel: 0, needsHealthKitAuth: needsAuth, sipCount: sipCount, themeID: themeID)],
                policy: .after(now.addingTimeInterval(60))
            ))
            return
        }

        var entries: [AquaWidgetEntry] = []

        // Home-widget fill-ramp entries (systemSmall / systemMedium only) —
        // restores the original day-1 stepped fill. After `LogWaterIntent`
        // reloads the timeline, WidgetKit walks through these sub-second
        // entries in order, cross-fading each snapshot so the wave visibly
        // climbs instead of snapping to full.
        //
        // **Stops:** 0% → 0.5% → 25% → 50% → 75% → 100%. The 0.5% primer right
        // after 0% is load-bearing: WidgetKit sometimes coalesces an entry
        // (especially the first one when the device has been idle), and
        // without the primer the next entry up is 25% — visible as a "snap
        // from 0% to ~50% then climb" instead of a true rise from the bottom.
        // With the 0.5% primer, even when iOS drops the 0% entry the next
        // landing is effectively still at the bottom of the widget.
        //
        // **Anchor:** `max(logTime, now)` — by the time WidgetKit actually
        // gets around to rendering the reloaded timeline, `now - logTime`
        // can be 50–200 ms, which previously pushed the first ~2 entries
        // into the past. iOS then "renders the latest non-future entry" and
        // landed on 50 % / 75 %. Anchoring forward of `now` guarantees every
        // ramp entry is at or after WidgetKit's render clock.
        //
        // **Why home only:** "Bug 7" in SIP_CONTEXT — iOS aggressively
        // throttles sub-second timeline updates for accessory (lock-screen)
        // widgets, which previously left them stuck at 0%. Gating on
        // `context.family` keeps the simple single-entry timeline for the
        // accessory widgets (`Gauge` already animates value changes
        // implicitly there) while letting the home widget get the rise.
        //
        // **Why no `TimelineView(.animation)`:** widget extensions don't run
        // an active display link, so a `TimelineView(.animation)`-driven ramp
        // freezes after a frame or two and strands the water at ~20–30 %.
        let rampDuration: TimeInterval = 0.6
        // Tuple = (seconds after the ramp anchor, fraction of the
        // `startLevel → postSipLevel` segment to display at that moment).
        let rampStops: [(time: TimeInterval, fraction: Double)] = [
            (0.00, 0.000),
            (0.05, 0.005),
            (0.18, 0.250),
            (0.33, 0.500),
            (0.47, 0.750),
            (0.60, 1.000),
        ]
        let startLevel: Double = {
            if let n = suite?.object(forKey: "fillStartLevel") as? NSNumber {
                return n.doubleValue
            }
            return 0
        }()
        let postSipLevel = Self.hydrationLevel(at: logTime)

        if isHome && elapsed < rampDuration {
            let rampAnchor = max(logTime, now)
            for stop in rampStops {
                let stepDate = rampAnchor.addingTimeInterval(stop.time)
                let level = startLevel + (postSipLevel - startLevel) * stop.fraction
                entries.append(AquaWidgetEntry(
                    date: stepDate,
                    hydrationLevel: level,
                    needsHealthKitAuth: needsAuth,
                    sipCount: sipCount,
                    themeID: themeID
                ))
            }
        } else {
            // Accessory (lock-screen) widget path. Use the actual `logTime`
            // as the entry date — not `now` — so iOS sees a clear timeline
            // boundary at the sip moment, and so the entry is unambiguously
            // in the past by the time the widget renders (avoids any edge
            // case where iOS treats a `date == captured-now` entry as
            // future after the completion handler has been queued).
            // The hydration level is computed from the same `elapsed` we
            // already validated above, sidestepping a second
            // `UserDefaults` read on a different `Date()`.
            let currentLevel = max(0, 1 - elapsed / hydrationDuration)
            entries.append(AquaWidgetEntry(
                date: logTime,
                hydrationLevel: currentLevel,
                needsHealthKitAuth: needsAuth,
                sipCount: sipCount,
                themeID: themeID
            ))
        }

        // Drain entries at 5-minute intervals for the next 2 hours.
        let drainStep: TimeInterval = 300
        var t = (floor(elapsed / drainStep) + 1) * drainStep
        while t < hydrationDuration {
            let d = logTime.addingTimeInterval(t)
            // Skip any drain step that overlaps the ramp window so the ramp
            // entries play through cleanly without being shadowed by a stray
            // 5-min drain entry.
            if d > now, d > (entries.last?.date ?? .distantPast) {
                entries.append(AquaWidgetEntry(
                    date: d,
                    hydrationLevel: Self.hydrationLevel(at: d),
                    needsHealthKitAuth: needsAuth,
                    sipCount: sipCount,
                    themeID: themeID
                ))
            }
            t += drainStep
        }

        // Final entry: fully dehydrated at end-of-2-hour window.
        if entries.last?.hydrationLevel != 0 {
            entries.append(AquaWidgetEntry(
                date: endTime,
                hydrationLevel: 0,
                needsHealthKitAuth: needsAuth,
                sipCount: sipCount,
                themeID: themeID
            ))
        }

        completion(Timeline(entries: entries, policy: .after(endTime)))
    }

    static func hydrationLevel(at date: Date) -> Double {
        let suite = UserDefaults(suiteName: appGroupID)
        guard let logTime = suite?.object(forKey: "lastWaterLogTime") as? Date else { return 0 }
        let elapsed = date.timeIntervalSince(logTime)
        if elapsed < 0 || elapsed >= hydrationDuration { return 0 }
        return max(0, 1 - elapsed / hydrationDuration)
    }

    static func todaySipCount() -> Int {
        let suite = UserDefaults(suiteName: appGroupID)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        guard let stored = suite?.string(forKey: "todaySipCountDate"),
              stored == today else { return 0 }
        return suite?.integer(forKey: "todaySipCount") ?? 0
    }

    static func selectedThemeID() -> ThemeID {
        let suite = UserDefaults(suiteName: appGroupID)
        guard let raw = suite?.string(forKey: "selectedTheme"),
              let id = ThemeID(rawValue: raw) else { return .default }
        return id
    }
}

// MARK: - Static wave shape for widget surface decoration

struct WidgetWaveShape: Shape {
    var phase: Double = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        guard w > 0 else { return path }

        let amp: CGFloat = 3
        let headroom = amp * 2.5
        let p = phase * .pi * 2

        path.move(to: CGPoint(x: 0, y: headroom))

        for x in stride(from: 0, through: w, by: 1) {
            let t = x / w
            let y = headroom
                + amp * sin(t * 1.5 * .pi * 2 + p)
                + amp * 0.3 * sin(t * 2.2 * .pi * 2 + 1.0 + p * 0.6)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: w, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Widget views

struct AquaWidgetView: View {
    var entry: AquaWidgetEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    /// Whether WidgetKit is drawing the removable container background (false
    /// in Liquid Glass / vibrant lock-screen contexts where the wallpaper shows
    /// through). Used with `renderingMode` to decide when a content-layer
    /// backdrop is needed for edge-to-edge fill.
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground
    // Default content margins, reapplied manually to the text/button after the
    // widget opts out of automatic margins (so the water can bleed edge-to-edge
    // as content while the chrome keeps its original inset).
    @Environment(\.widgetContentMargins) private var contentMargins

    /// The palette is resolved for the widget's color scheme, so Dark Mode
    /// uses each theme's real dark palette (dark backdrop + light-leaning
    /// content) rather than a one-off override. The off-water content colors
    /// (`headerPrimary`, `statsPrimary`, etc.) are already light in the dark
    /// palette, so they stay legible on the dark backdrop without any
    /// scheme-specific branching here.
    private var theme: AppTheme { .forID(entry.themeID, scheme: colorScheme) }
    /// Aqua home-widget water fill — `#008EEC` (icon droplet blue); Kurosawa uses `theme.waterColor`.
    private var widgetWaterFillColor: Color {
        switch theme.id {
        case .default:
            return Color(red: 0x00 / 255.0, green: 0x8E / 255.0, blue: 0xEC / 255.0)
        case .kurosawa:
            return theme.waterColor
        }
    }
    private var isHydrated: Bool { entry.hydrationLevel > 0 }
    private var headerOnWater: Bool { entry.hydrationLevel >= 0.80 }
    private var buttonOnWater: Bool { entry.hydrationLevel > 0.15 }
    private var isTinted: Bool { renderingMode == .accented }
    /// Full-color contexts (home screen default, iPad Lock Screen gallery
    /// preview) need an explicit content-layer backdrop so the dehydrated panel
    /// bleeds edge-to-edge. WidgetKit can inset the removable
    /// `containerBackground` in those contexts (notably iPad Lock Screen) even
    /// with `.contentMarginsDisabled()` — Apple's WWDC pattern is to paint the
    /// backdrop in the content `ZStack` and keep `containerBackground` for
    /// removal signaling only.
    private var usesFullColorBackdrop: Bool {
        renderingMode == .fullColor && showsWidgetContainerBackground
    }

    private var headerColor: Color {
        if headerOnWater {
            return isTinted ? Color(white: 0.1) : theme.headerPrimaryOnWater
        }
        // Below 80 % the header sits over the light glass / dehydrated backdrop.
        // `Color.primary` is system-tinted white in accented (Liquid Glass) mode,
        // so always use the theme's explicit off-water colors here.
        return theme.headerPrimary
    }

    private var headerSecondaryColor: Color {
        if headerOnWater {
            return isTinted ? Color(white: 0.1, opacity: 0.5) : theme.headerSecondaryOnWater
        }
        return theme.headerSecondary
    }

    private var sipCountColor: Color {
        if headerOnWater {
            return isTinted ? Color(white: 0.1) : theme.headerPrimaryOnWater
        }
        // Match the title — black/near-black on the light dehydrated backdrop,
        // not the muted stats gray used in the main app's stats overlay.
        return theme.headerPrimary
    }

    /// Title font for the widget header. Mirrors `ThemeID.headerTitleFont` in
    /// the main app: Kurosawa uses Crimson Text Regular (bundled via the
    /// widget target's font membership exceptions); the default theme stays
    /// on the system font so it inherits dynamic-type behavior.
    private var titleFont: Font {
        switch entry.themeID {
        case .default:
            return .system(size: 15, weight: .medium)
        case .kurosawa:
            return .custom("CrimsonText-SemiBold", size: 15)
        }
    }

    var body: some View {
        switch family {
        case .systemSmall:       smallView
        case .systemMedium:      mediumView
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        default: smallView
        }
    }

    // MARK: Small / Medium (shared)

    // The small and medium home widgets share one layout. The water is widget
    // *content* (not the container background) so it survives — and gets
    // system-tinted like any other content — when the user's tinted/clear Home
    // Screen appearance makes WidgetKit swap our backdrop for adaptive glass.
    private var smallView: some View { homeView }
    private var mediumView: some View { homeView }

    private var homeView: some View {
        ZStack(alignment: .bottom) {
            if usesFullColorBackdrop {
                widgetBackground
            }

            waterFill
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 4) {
                    Text(isHydrated ? "Aqua" : "Sip")
                        .font(titleFont)
                        .foregroundStyle(headerColor)
                    Text(isHydrated ? "水" : "飲")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(headerSecondaryColor)

                    Spacer()

                    Text("\(entry.sipCount)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(sipCountColor)
                        .contentTransition(.numericText())
                }
                .contentTransition(.interpolate)

                Spacer()

                HStack {
                    Spacer()
                    drinkButton
                }
            }
            .padding(contentMargins)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { widgetBackground }
    }

    // MARK: Accessory

    private var circularView: some View {
        Gauge(value: entry.hydrationLevel, in: 0...1) {
            Text("Water")
        } currentValueLabel: {
            if isHydrated {
                Image(systemName: "drop.fill")
            } else {
                Text("飲")
                    .font(.system(size: 20, weight: .medium))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(for: .widget) { }
    }

    private var rectangularView: some View {
        let percent = Int(round(entry.hydrationLevel * 100))

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 14))
                Text("\(percent)%")
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(isHydrated ? "Hydrated" : "Sip 飲")
                .font(.caption2)

            Gauge(value: entry.hydrationLevel, in: 0...1) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
        }
        .containerBackground(for: .widget) { }
    }

    // MARK: Drink button

    private var buttonForegroundColor: Color {
        if isTinted {
            return buttonOnWater ? Color(white: 0.1) : Color.primary
        }
        return buttonOnWater ? theme.buttonForegroundOnWater : theme.buttonForeground
    }

    private var buttonBackgroundColor: Color {
        if isTinted {
            return buttonOnWater ? Color(white: 0.1).opacity(0.25) : Color.primary.opacity(0.15)
        }
        return buttonOnWater ? theme.buttonBackgroundOnWater : theme.buttonBackground
    }

    private var drinkButtonLabel: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(buttonForegroundColor)
            .padding(10)
            .background(Circle().fill(buttonBackgroundColor))
    }

    @ViewBuilder
    private var drinkButton: some View {
        Group {
            if entry.needsHealthKitAuth {
                Button(intent: LogWaterAuthIntent()) { drinkButtonLabel }
            } else {
                Button(intent: LogWaterIntent()) { drinkButtonLabel }
            }
        }
        .buttonStyle(.plain)
        .contentTransition(.interpolate)
    }

    // MARK: Water fill (widget content) + backdrop (container background)

    /// The rising water level. This is now widget **content**, anchored to the
    /// bottom and bleeding edge-to-edge (the widget opts out of automatic
    /// content margins via `.contentMarginsDisabled()`). Keeping it as content
    /// — rather than inside `containerBackground` — is what lets the water
    /// survive when WidgetKit removes the backdrop and substitutes its glass
    /// material for tinted/clear Home Screen appearances; in those modes the
    /// system tints this shape just like every other widget's content.
    ///
    /// The actual rising animation is driven by the **timeline**:
    /// `AquaTimelineProvider.getTimeline` emits sub-second entries during the
    /// post-sip ramp window with stepped hydration levels, and WidgetKit walks
    /// through them in order. Each entry is rendered statically here — no
    /// `TimelineView(.animation)`, no `.animation(value:)` — because neither
    /// produces a real fill animation in widget process context. See the ramp
    /// loop in `getTimeline` for the full history.
    private var waterFill: some View {
        GeometryReader { geo in
            let waveHeadroom: CGFloat = entry.hydrationLevel > 0 ? 8 : 0
            let waterHeight = geo.size.height * entry.hydrationLevel + waveHeadroom
            let wavePhase = entry.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4

            WidgetWaveShape(phase: wavePhase)
                .fill(widgetWaterFillColor)
                // Tinted/clear Home Screen appearances system-tint all content
                // white, so an opaque water fill matches the header + button and
                // vanishes. 70 % transparency keeps the level readable.
                .opacity(isTinted ? 0.3 : 1)
                .frame(height: max(0, waterHeight))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// The widget backdrop behind the water. Declared inside
    /// `containerBackground(for: .widget)` (and the widget no longer calls
    /// `.containerBackgroundRemovable(false)`), so WidgetKit **removes this and
    /// substitutes its own adaptive glass material** — light glass in Light
    /// Mode, dark glass in Dark Mode, showing the wallpaper through it — the
    /// moment the user's Home Screen uses a tinted or clear (Liquid Glass)
    /// appearance. That's the Batteries-widget look and it's entirely
    /// system-driven; we don't (and can't) paint the wallpaper ourselves.
    ///
    /// In the **default full-color** appearance the system does *not* show the
    /// wallpaper through third-party widgets, so this solid backdrop shows
    /// instead. `theme.dehydratedBackground` is already the dark palette's
    /// near-black panel in Dark Mode, so it supports Dark Mode without a
    /// scheme-specific override.
    private var widgetBackground: some View {
        theme.dehydratedBackground
    }
}

// MARK: - Widgets

struct SipHomeWidget: Widget {
    let kind: String = "AquaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AquaTimelineProvider()) { entry in
            AquaWidgetView(entry: entry)
        }
        .configurationDisplayName("Hydration")
        .description("Log your sip and stay hydrated.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // Opt *in* to background removal (no `containerBackgroundRemovable(false)`)
        // so tinted/clear Home Screen appearances swap our backdrop for the
        // system's adaptive Liquid Glass — the battery-widget look.
        // Disable automatic content margins so the water fill bleeds
        // edge-to-edge; the text/button reapply the system margins themselves.
        .contentMarginsDisabled()
    }
}

struct SipStatusWidget: Widget {
    let kind: String = "SipStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AquaTimelineProvider()) { entry in
            AquaWidgetView(entry: entry)
        }
        .configurationDisplayName("Sip")
        .description("Your hydration level at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    SipHomeWidget()
} timeline: {
    AquaWidgetEntry(date: Date(), hydrationLevel: 0, needsHealthKitAuth: false, sipCount: 0, themeID: .default)
    AquaWidgetEntry(date: Date(), hydrationLevel: 0.5, needsHealthKitAuth: false, sipCount: 3, themeID: .default)
    AquaWidgetEntry(date: Date(), hydrationLevel: 1, needsHealthKitAuth: false, sipCount: 7, themeID: .default)
}
