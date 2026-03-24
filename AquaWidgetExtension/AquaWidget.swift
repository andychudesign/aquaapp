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
private let waterBlue = Color(red: 0.2, green: 0.55, blue: 0.9)
private let dehydratedBg = Color(red: 0.98, green: 0.96, blue: 0.92)

// MARK: - App Intent

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "I drank water"

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
        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
        await HealthKitManager.saveSip()
        return .result()
    }
}

// MARK: - Timeline

struct AquaWidgetEntry: TimelineEntry {
    let date: Date
    let hydrationLevel: Double
}

struct AquaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AquaWidgetEntry {
        AquaWidgetEntry(date: Date(), hydrationLevel: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (AquaWidgetEntry) -> Void) {
        completion(AquaWidgetEntry(date: Date(), hydrationLevel: Self.hydrationLevel(at: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AquaWidgetEntry>) -> Void) {
        let now = Date()
        let suite = UserDefaults(suiteName: appGroupID)

        guard let logTime = suite?.object(forKey: "lastWaterLogTime") as? Date else {
            completion(Timeline(
                entries: [AquaWidgetEntry(date: now, hydrationLevel: 0)],
                policy: .after(now.addingTimeInterval(60))
            ))
            return
        }

        let elapsed = now.timeIntervalSince(logTime)
        let endTime = logTime.addingTimeInterval(hydrationDuration)

        guard elapsed < hydrationDuration else {
            completion(Timeline(
                entries: [AquaWidgetEntry(date: now, hydrationLevel: 0)],
                policy: .after(now.addingTimeInterval(60))
            ))
            return
        }

        var entries: [AquaWidgetEntry] = []

        let fillStartLevel = suite?.double(forKey: "fillStartLevel") ?? 0

        // Fill phase: ramp from previous level → 1 over 2 seconds so water visibly rises
        let fillDuration: TimeInterval = 2.0
        let fillStep: TimeInterval = 0.3
        if elapsed < fillDuration {
            var ft = elapsed
            while ft < fillDuration {
                let d = logTime.addingTimeInterval(ft)
                if d >= now {
                    let progress = min(1.0, ft / fillDuration)
                    let fillLevel = fillStartLevel + (1.0 - fillStartLevel) * progress
                    entries.append(AquaWidgetEntry(date: d, hydrationLevel: fillLevel))
                }
                ft += fillStep
            }
        }

        // Drain phase: update every 5 minutes over the 2-hour window
        let drainStep: TimeInterval = 300
        var t = max(elapsed, fillDuration)
        while t < hydrationDuration {
            let d = logTime.addingTimeInterval(t)
            if d >= now, entries.last.map({ d.timeIntervalSince($0.date) >= 1 }) ?? true {
                entries.append(AquaWidgetEntry(date: d, hydrationLevel: Self.hydrationLevel(at: d)))
            }
            t += drainStep
        }

        if entries.last?.hydrationLevel != 0 {
            entries.append(AquaWidgetEntry(date: endTime, hydrationLevel: 0))
        }

        if entries.isEmpty {
            entries.append(AquaWidgetEntry(date: now, hydrationLevel: Self.hydrationLevel(at: now)))
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

    private var isHydrated: Bool { entry.hydrationLevel > 0 }
    private var headerOnWater: Bool { entry.hydrationLevel > 0.75 }
    private var buttonOnWater: Bool { entry.hydrationLevel > 0.15 }
    private var isTinted: Bool { renderingMode == .accented }

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
            HStack(spacing: 4) {
                Text(isHydrated ? "Aqua" : "Sip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        headerOnWater
                            ? (isTinted ? Color(white: 0.1) : Color.white)
                            : (isTinted ? Color.primary : Color(white: 0.15))
                    )
                Text(isHydrated ? "水" : "飲")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        headerOnWater
                            ? (isTinted ? Color(white: 0.1, opacity: 0.5) : Color(white: 1, opacity: 0.5))
                            : (isTinted ? Color.secondary : Color(red: 0.35, green: 0.55, blue: 0.85))
                    )
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
            HStack(spacing: 4) {
                Text(isHydrated ? "Aqua" : "Sip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        headerOnWater
                            ? (isTinted ? Color(white: 0.1) : Color.white)
                            : (isTinted ? Color.primary : Color(white: 0.15))
                    )
                Text(isHydrated ? "水" : "飲")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        headerOnWater
                            ? (isTinted ? Color(white: 0.1, opacity: 0.5) : Color(white: 1, opacity: 0.5))
                            : (isTinted ? Color.secondary : Color(red: 0.35, green: 0.55, blue: 0.85))
                    )
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
        Button(intent: LogWaterIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "drop.fill")
                    .font(.title)
            }
        }
        .buttonStyle(.plain)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                Text(isHydrated ? "Hydrated" : "Dehydrated")
                    .font(.caption.weight(.semibold))
            }
            Button(intent: LogWaterIntent()) {
                Text("Drink")
                    .font(.caption2.weight(.medium))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Drink button

    private var drinkButton: some View {
        Button(intent: LogWaterIntent()) {
            Image(systemName: "drop.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    buttonOnWater
                        ? (isTinted ? Color(white: 0.1) : Color.white)
                        : (isTinted ? Color.primary : waterBlue)
                )
                .padding(10)
                .background(
                    Circle().fill(
                        buttonOnWater
                            ? (isTinted ? Color(white: 0.1).opacity(0.25) : Color.white.opacity(0.25))
                            : (isTinted ? Color.primary.opacity(0.15) : waterBlue.opacity(0.15))
                    )
                )
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
                dehydratedBg
                    .widgetAccentable()

                WidgetWaveShape(phase: wavePhase)
                    .fill(waterBlue)
                    .frame(height: max(0, waterHeight))
            }
        }
    }
}

// MARK: - Widget

struct AquaWidget: Widget {
    let kind: String = "AquaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AquaTimelineProvider()) { entry in
            AquaWidgetView(entry: entry)
        }
        .configurationDisplayName("Aqua")
        .description("Track your hydration. Tap Drink to log water.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
        .containerBackgroundRemovable(false)
    }
}

#Preview(as: .systemSmall) {
    AquaWidget()
} timeline: {
    AquaWidgetEntry(date: Date(), hydrationLevel: 0)
    AquaWidgetEntry(date: Date(), hydrationLevel: 0.5)
    AquaWidgetEntry(date: Date(), hydrationLevel: 1)
}
