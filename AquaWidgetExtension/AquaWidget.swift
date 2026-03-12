//
//  AquaWidget.swift
//  AquaWidgetExtension
//

import AppIntents
import WidgetKit
import SwiftUI

private let appGroupID = "group.andychudesign.aqua"
private let hydrationDuration: TimeInterval = 5.0

// MARK: - App Intent (log water from widget without opening app)

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "I drank water"

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: appGroupID)?.set(Date(), forKey: "lastWaterLogTime")
        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
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
        let entry = AquaWidgetEntry(date: Date(), hydrationLevel: Self.hydrationLevel(at: Date()))
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AquaWidgetEntry>) -> Void) {
        let now = Date()
        let level = Self.hydrationLevel(at: now)

        let nextUpdate: Date
        if level > 0 {
            let suite = UserDefaults(suiteName: appGroupID)
            let logTime = suite?.object(forKey: "lastWaterLogTime") as? Date ?? now
            nextUpdate = logTime.addingTimeInterval(hydrationDuration)
        } else {
            nextUpdate = now.addingTimeInterval(60)
        }

        let entries = [
            AquaWidgetEntry(date: now, hydrationLevel: level),
            AquaWidgetEntry(date: nextUpdate, hydrationLevel: 0)
        ]
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }

    static func hydrationLevel(at date: Date) -> Double {
        let suite = UserDefaults(suiteName: appGroupID)
        guard let logTime = suite?.object(forKey: "lastWaterLogTime") as? Date else { return 0 }
        let elapsed = date.timeIntervalSince(logTime)
        if elapsed >= hydrationDuration { return 0 }
        return max(0, 1 - elapsed / hydrationDuration)
    }
}

// MARK: - Widget views (same concept: dehydrated / hydrated)

struct AquaWidgetView: View {
    var entry: AquaWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    private var smallView: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.88, green: 0.94, blue: 0.98)
                ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            VStack(spacing: 6) {
                dropletImage
                statusText
                Button(intent: LogWaterIntent()) {
                    Label("I drank water", systemImage: "drop.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.2, green: 0.55, blue: 0.85))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var mediumView: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.88, green: 0.94, blue: 0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(entry.hydrationLevel > 0 ? Color(red: 0.2, green: 0.6, blue: 0.9) : Color(red: 0.4, green: 0.5, blue: 0.6))
                    statusText
                    Spacer(minLength: 0)
                }
                Button(intent: LogWaterIntent()) {
                    Label("I drank water", systemImage: "drop.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.2, green: 0.55, blue: 0.85))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    private var circularView: some View {
        Button(intent: LogWaterIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                dropletImage
            }
        }
        .buttonStyle(.plain)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                dropletImage
                statusText
            }
            Button(intent: LogWaterIntent()) {
                Text("I drank water")
                    .font(.caption2.weight(.medium))
            }
            .buttonStyle(.plain)
        }
    }

    private var dropletImage: some View {
        Image(systemName: "drop.fill")
            .font(family == .accessoryCircular ? .title : .title2)
            .foregroundStyle(entry.hydrationLevel > 0 ? Color(red: 0.2, green: 0.6, blue: 0.9) : Color(red: 0.4, green: 0.5, blue: 0.6))
    }

    private var statusText: some View {
        Group {
            if entry.hydrationLevel > 0 {
                Text("Hydrated")
                    .font(.caption.weight(.semibold))
            } else {
                Text("Dehydrated")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
        .description("See if you're hydrated. Tap to open and log water.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    AquaWidget()
} timeline: {
    AquaWidgetEntry(date: Date(), hydrationLevel: 0)
    AquaWidgetEntry(date: Date(), hydrationLevel: 1)
}
