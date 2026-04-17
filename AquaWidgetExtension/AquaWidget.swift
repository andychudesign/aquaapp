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

    private static func incrementSipCount(suite: UserDefaults?) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let stored = suite?.string(forKey: "todaySipCountDate")
        let isNewDay = stored != today
        let current = isNewDay ? 0 : (suite?.integer(forKey: "todaySipCount") ?? 0)
        suite?.set(current + 1, forKey: "todaySipCount")
        suite?.set(today, forKey: "todaySipCountDate")

        let storedVol = suite?.integer(forKey: "sipVolumeML") ?? 0
        let sipML = storedVol > 0 ? storedVol : 70
        let previousVolume: Int
        if isNewDay {
            previousVolume = 0
        } else if let vol = suite?.object(forKey: "todayTotalVolumeML") as? Int {
            previousVolume = vol
        } else {
            previousVolume = current * 70
        }
        suite?.set(previousVolume + sipML, forKey: "todayTotalVolumeML")
    }

    func perform() async throws -> some IntentResult {
        let suite = UserDefaults(suiteName: appGroupID)
        let previousLevel: Double
        if let logTime = suite?.object(forKey: "lastWaterLogTime") as? Date {
            let elapsed = Date().timeIntervalSince(logTime)
            previousLevel = max(0, min(1, 1 - elapsed / hydrationDuration))
        } else {
            previousLevel = 0
        }
        suite?.set(previousLevel, forKey: "fillStartLevel")
        suite?.set(Date(), forKey: "lastWaterLogTime")
        Self.incrementSipCount(suite: suite)
        WidgetCenter.shared.reloadAllTimelines()
        let saved = await HealthKitManager.saveSip(requestAuth: false)
        if saved {
            suite?.set(true, forKey: "healthKitAuthResolved")
        }
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

        let fillStartLevel = suite?.double(forKey: "fillStartLevel") ?? 0

        let fillDuration: TimeInterval = 2.0
        let fillStep: TimeInterval = 0.3
        if elapsed < fillDuration {
            var ft = elapsed
            while ft < fillDuration {
                let d = logTime.addingTimeInterval(ft)
                if d >= now {
                    let progress = min(1.0, ft / fillDuration)
                    let fillLevel = fillStartLevel + (1.0 - fillStartLevel) * progress
                    entries.append(AquaWidgetEntry(date: d, hydrationLevel: fillLevel, needsHealthKitAuth: needsAuth, sipCount: sipCount, themeID: themeID))
                }
                ft += fillStep
            }
        }

        let drainStep: TimeInterval = 300
        var t = max(elapsed, fillDuration)
        while t < hydrationDuration {
            let d = logTime.addingTimeInterval(t)
            if d >= now, entries.last.map({ d.timeIntervalSince($0.date) >= 1 }) ?? true {
                entries.append(AquaWidgetEntry(date: d, hydrationLevel: Self.hydrationLevel(at: d), needsHealthKitAuth: needsAuth, sipCount: sipCount, themeID: themeID))
            }
            t += drainStep
        }

        if entries.last?.hydrationLevel != 0 {
            entries.append(AquaWidgetEntry(date: endTime, hydrationLevel: 0, needsHealthKitAuth: needsAuth, sipCount: sipCount, themeID: themeID))
        }

        if entries.isEmpty {
            entries.append(AquaWidgetEntry(date: now, hydrationLevel: Self.hydrationLevel(at: now), needsHealthKitAuth: needsAuth, sipCount: sipCount, themeID: themeID))
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

    private var theme: AppTheme { .forID(entry.themeID) }
    private var isHydrated: Bool { entry.hydrationLevel > 0 }
    private var headerOnWater: Bool { entry.hydrationLevel > 0.88 }
    private var buttonOnWater: Bool { entry.hydrationLevel > 0.15 }
    private var isTinted: Bool { renderingMode == .accented }

    private var headerColor: Color {
        headerOnWater
            ? (isTinted ? Color(white: 0.1) : theme.headerPrimaryOnWater)
            : (isTinted ? Color.primary : theme.headerPrimary)
    }

    private var headerSecondaryColor: Color {
        headerOnWater
            ? (isTinted ? Color(white: 0.1, opacity: 0.5) : theme.headerSecondaryOnWater)
            : (isTinted ? Color.secondary : theme.headerSecondary)
    }

    private var sipCountColor: Color {
        headerOnWater
            ? (isTinted ? Color(white: 0.1) : theme.headerPrimaryOnWater)
            : (isTinted ? Color.primary : theme.statsPrimary)
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

    // MARK: Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                Text(isHydrated ? "Aqua" : "Sip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(headerColor)
                Text(isHydrated ? "水" : "飲")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(headerSecondaryColor)

                Spacer()

                Text("\(entry.sipCount)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(headerColor)
                    .contentTransition(.numericText())
            }
            .contentTransition(.interpolate)

            Spacer()

            HStack {
                Spacer()
                drinkButton
            }
        }
        .containerBackground(for: .widget) { waterFillBackground }
    }

    // MARK: Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                Text(isHydrated ? "Aqua" : "Sip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(headerColor)
                Text(isHydrated ? "水" : "飲")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(headerSecondaryColor)

                Spacer()

                Text("\(entry.sipCount)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(headerColor)
                    .contentTransition(.numericText())
            }
            .contentTransition(.interpolate)

            Spacer()

            HStack {
                Spacer()
                drinkButton
            }
        }
        .containerBackground(for: .widget) { waterFillBackground }
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

    private var drinkButtonLabel: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(
                buttonOnWater
                    ? (isTinted ? Color(white: 0.1) : theme.buttonForegroundOnWater)
                    : (isTinted ? Color.primary : theme.buttonForeground)
            )
            .padding(10)
            .background(
                Circle().fill(
                    buttonOnWater
                        ? (isTinted ? Color(white: 0.1).opacity(0.25) : theme.buttonBackgroundOnWater)
                        : (isTinted ? Color.primary.opacity(0.15) : theme.buttonBackground)
                )
            )
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

    // MARK: Water-fill background

    private var waterFillBackground: some View {
        GeometryReader { geo in
            let waveHeadroom: CGFloat = entry.hydrationLevel > 0 ? 8 : 0
            let waterHeight = geo.size.height * entry.hydrationLevel + waveHeadroom
            let wavePhase = entry.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4

            ZStack(alignment: .bottom) {
                theme.dehydratedBackground
                    .widgetAccentable()

                WidgetWaveShape(phase: wavePhase)
                    .fill(theme.waterColor)
                    .frame(height: max(0, waterHeight))
            }
        }
    }
}

// MARK: - Widgets

struct SipHomeWidget: Widget {
    let kind: String = "AquaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AquaTimelineProvider()) { entry in
            AquaWidgetView(entry: entry)
        }
        .configurationDisplayName("Sip")
        .description("Track your hydration and log a sip from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable(false)
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
