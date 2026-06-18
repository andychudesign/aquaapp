//
//  SiriShortcuts.swift
//  aqua
//
//  Siri / Spotlight integration via the App Intents framework (the modern
//  successor to SiriKit's `INIntent`). Exposes two voice actions:
//
//    1. "Take a Sip"                  → `LogSipIntent`
//    2. "Sip, how much water did I    → `WaterIntakeQueryIntent`
//        drink today / yesterday /        (day parameter: today, yesterday,
//        on Monday"                        or any weekday)
//
//  Both run in the background (no app launch) and answer with a spoken dialog
//  plus a SwiftUI snippet rendered inside the Siri / Spotlight result card.
//
//  App-target only — not shared with the widget extension (snippet views and
//  `AppShortcutsProvider` live in the host app process). The synchronized root
//  group adds this file to the `aqua` target automatically.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Log a sip

/// Logs a sip exactly like the in-app button and the widget's `LogWaterIntent`
/// (persist to the App Group, accumulate volume, write HealthKit, reload
/// widgets), then returns a confirmation dialog and an animated snippet whose
/// water fills 0 → 100 — echoing the lock-screen widget the user asked for.
struct LogSipIntent: AppIntent {
    static let title: LocalizedStringResource = "Take a Sip"
    static let description = IntentDescription(
        "Log a sip of water and watch your hydration top back up to full."
    )
    /// Background execution — we want the animated snippet feedback in Siri,
    /// not to launch the app.
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Persist the sip + reload widgets. Mirrors the in-app / widget log
        // paths (sets `lastWaterLogTime`, accumulates volume, increments the
        // daily count, records the 7-day history, and issues one reload per
        // widget kind).
        SharedStorage.logWater()

        // Mirror the app's HealthKit write. If authorization hasn't been
        // granted yet this is a silent no-op from the background Siri context;
        // the sip is still recorded locally and reflected in the widgets.
        let saved = await HealthKitManager.saveSip(requestAuth: true)
        if saved {
            UserDefaults(suiteName: SharedStorage.appGroupID)?
                .set(true, forKey: "healthKitAuthResolved")
            // Re-reload so the widget button rebinds to the background intent
            // now that auth is resolved. Per-kind (not `reloadAllTimelines()`)
            // to preserve the accessory widgets' reload budget — see
            // `SharedStorage.logWater()`.
            WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
        }

        let count = SharedStorage.todaySipCount
        let volume = SharedStorage.todayTotalVolumeML

        return .result(
            dialog: "Sip logged. That's \(count) today, about \(volume) milliliters.",
            view: SipLoggedSnippet(
                theme: SharedStorage.currentTheme,
                sipCount: count,
                volumeML: volume
            )
        )
    }
}

// MARK: - Check water intake

/// Answers "how much water did I drink today / yesterday / on Monday" with the
/// chosen day's sip count, volume in mL, and how it compares to the rest of the
/// week — both spoken (dialog) and as a snippet with a 7-day mini bar chart.
struct WaterIntakeQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Water Intake"
    static let description = IntentDescription(
        "See how much water you logged on a given day and how it compares to your week."
    )
    static let openAppWhenRun: Bool = false

    /// Which day to report on. Defaults to today, so the plain "how much water
    /// have I had" phrases work without naming a day.
    @Parameter(title: "Day", default: .today)
    var day: DayQuery

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let date = Self.resolvedDate(for: day)
        let key = SharedStorage.dateKey(for: date)
        let count = SharedStorage.sipCount(on: key)
        let volume = SharedStorage.estimatedVolumeML(on: key)
        let week = SharedStorage.last7DaysSipCounts.map { SipDay(id: $0.date, count: $0.count) }

        // Compare the chosen day against the other days in the 7-day window
        // that have data.
        let others = week.filter { $0.id != key }.map(\.count)
        let daysWithData = others.filter { $0 > 0 }.count
        let average = daysWithData > 0 ? Double(others.reduce(0, +)) / Double(daysWithData) : 0
        let trend = SipTrend(count: count, comparisonAverage: average)

        let sipWord = count == 1 ? "sip" : "sips"
        let verb = day == .today ? "you've logged" : "you logged"
        let dialog: IntentDialog =
            "\(day.dialogSubject) \(verb) \(count) \(sipWord), about \(volume) milliliters. \(trend.spokenClause)"

        return .result(
            dialog: dialog,
            view: WaterIntakeSnippet(
                theme: SharedStorage.currentTheme,
                subject: day.snippetSubject,
                sipCount: count,
                volumeML: volume,
                week: week,
                highlightID: key,
                trend: trend
            )
        )
    }

    /// Resolve a `DayQuery` to a concrete date. Weekdays map to the single
    /// matching day inside the trailing 7-day window (today + 6 prior covers
    /// every weekday exactly once).
    static func resolvedDate(for day: DayQuery) -> Date {
        let cal = Calendar.current
        let now = Date()
        switch day {
        case .today:
            return now
        case .yesterday:
            return cal.date(byAdding: .day, value: -1, to: now) ?? now
        default:
            guard let target = day.calendarWeekday else { return now }
            for back in 0...6 {
                if let d = cal.date(byAdding: .day, value: -back, to: now),
                   cal.component(.weekday, from: d) == target {
                    return d
                }
            }
            return now
        }
    }
}

// MARK: - Day parameter

/// Day selector for `WaterIntakeQueryIntent`. A fixed `AppEnum` so Siri can
/// match the spoken value ("today", "yesterday", "Monday", …) directly from
/// the App Shortcut phrase without a disambiguation round-trip.
enum DayQuery: String, AppEnum {
    case today
    case yesterday
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Day" }

    static var caseDisplayRepresentations: [DayQuery: DisplayRepresentation] {
        [
            .today: "Today",
            .yesterday: "Yesterday",
            .monday: "Monday",
            .tuesday: "Tuesday",
            .wednesday: "Wednesday",
            .thursday: "Thursday",
            .friday: "Friday",
            .saturday: "Saturday",
            .sunday: "Sunday",
        ]
    }

    /// `Calendar` weekday number (Sunday = 1 … Saturday = 7), or `nil` for the
    /// relative cases.
    var calendarWeekday: Int? {
        switch self {
        case .sunday:    return 1
        case .monday:    return 2
        case .tuesday:   return 3
        case .wednesday: return 4
        case .thursday:  return 5
        case .friday:    return 6
        case .saturday:  return 7
        case .today, .yesterday: return nil
        }
    }

    /// Sentence-leading subject for the spoken dialog ("Today", "Yesterday",
    /// "On Monday").
    var dialogSubject: String {
        switch self {
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        default:         return "On \(snippetSubject)"
        }
    }

    /// Short label for the snippet header.
    var snippetSubject: String {
        switch self {
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        case .sunday:    return "Sunday"
        }
    }
}

// MARK: - Trend model

/// One day in the 7-day history. `id` is the `yyyy-MM-dd` date string, giving
/// each bar a stable identity for `ForEach` (per the foreach idiom — bars are
/// positional but never reorder, and a date key reads clearer than an index).
struct SipDay: Identifiable {
    let id: String
    let count: Int
}

/// Compares one day's sip count to the rest-of-week average and produces the
/// spoken summary + snippet styling.
struct SipTrend {
    enum Direction {
        case up, down, flat, noData
    }

    let direction: Direction
    /// Absolute percentage difference from the comparison average (rounded).
    let percent: Int

    init(count: Int, comparisonAverage: Double) {
        guard comparisonAverage > 0 else {
            direction = .noData
            percent = 0
            return
        }
        let delta = (Double(count) - comparisonAverage) / comparisonAverage
        let pct = Int((abs(delta) * 100).rounded())
        percent = pct
        // Within ~8% reads as "about the same" rather than a real swing.
        if pct < 8 {
            direction = .flat
        } else if delta > 0 {
            direction = .up
        } else {
            direction = .down
        }
    }

    /// Trailing clause appended to the spoken summary.
    var spokenClause: String {
        switch direction {
        case .noData: return "Keep sipping to start building your weekly trend."
        case .flat:   return "That's right in line with your weekly average."
        case .up:     return "That's \(percent) percent above your weekly average. Nice work."
        case .down:   return "That's \(percent) percent below your weekly average — time for another sip."
        }
    }

    var symbolName: String {
        switch direction {
        case .up:     return "arrow.up.right"
        case .down:   return "arrow.down.right"
        case .flat:   return "equal"
        case .noData: return "sparkles"
        }
    }

    var snippetLabel: String {
        switch direction {
        case .up:     return "\(percent)% above your 7-day average"
        case .down:   return "\(percent)% below your 7-day average"
        case .flat:   return "On par with your 7-day average"
        case .noData: return "Building your weekly trend"
        }
    }

    func tintColor(theme: AppTheme) -> Color {
        switch direction {
        case .up:            return theme.waterColor
        case .down:          return .orange
        case .flat, .noData: return theme.statsSecondary
        }
    }
}

// MARK: - Snippet: sip logged

/// Siri result card for `LogSipIntent`. Water rises from empty to full on
/// appear (the lock-screen-widget feedback the user requested); the label +
/// drop icon crossfade from the dehydrated dark treatment to the on-water
/// white treatment as the water covers them, matching the main app.
struct SipLoggedSnippet: View {
    let theme: AppTheme
    let sipCount: Int
    let volumeML: Int

    /// Drives the rise (0 → 1) and the dark→white content crossfade.
    @State private var fill: Double = 0

    var body: some View {
        ZStack {
            risingWater
            content
        }
        // Apple's canonical snippet layout: fill the width the system hands the
        // snippet and let `ContainerRelativeShape` adopt the host's corner
        // radius + margins, rather than fixing a width/corner ourselves.
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(theme.dehydratedBackground)
        .clipShape(ContainerRelativeShape())
        .onAppear {
            withAnimation(.easeOut(duration: 1.4)) { fill = 1 }
        }
    }

    private var risingWater: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 4) / 4
                WaveShape(
                    phase: phase, amplitude: 5, frequency: 1.5,
                    bumpHeight: 0, bumpWidth: 0.18
                )
                .fill(theme.waterColor)
                .frame(height: max(0, geo.size.height * fill + (fill > 0 ? 12 : 0)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.waterColor.opacity(0.15))
                    .opacity(1 - fill)
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .opacity(fill)
                adaptiveDrop
            }
            .frame(width: 56, height: 56)

            crossfadeText("Sip logged", size: 17, weight: .semibold)
            crossfadeText("\(sipCount) today · \(volumeML) ml", size: 13, weight: .medium)
        }
    }

    private var adaptiveDrop: some View {
        ZStack {
            Image(systemName: "drop.fill")
                .foregroundStyle(theme.waterColor)
                .opacity(1 - fill)
            Image(systemName: "drop.fill")
                .foregroundStyle(.white)
                .opacity(fill)
        }
        .font(.system(size: 26, weight: .medium))
    }

    /// Dark text on the dehydrated start, white once the water has covered it.
    private func crossfadeText(_ string: String, size: CGFloat, weight: Font.Weight) -> some View {
        ZStack {
            Text(string)
                .foregroundStyle(theme.headerPrimary)
                .opacity(1 - fill)
            Text(string)
                .foregroundStyle(.white)
                .opacity(fill)
        }
        .font(.system(size: size, weight: weight))
    }
}

// MARK: - Snippet: water intake

/// Siri result card for `WaterIntakeQueryIntent`: the chosen day's sip count +
/// volume, a 7-day mini bar chart (the chosen day highlighted), and the trend
/// vs. the rest of the week.
struct WaterIntakeSnippet: View {
    let theme: AppTheme
    let subject: String
    let sipCount: Int
    let volumeML: Int
    let week: [SipDay]
    let highlightID: String
    let trend: SipTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            chart
            trendLabel
        }
        .padding(18)
        // Apple's canonical snippet layout: fill the width the system hands the
        // snippet and let `ContainerRelativeShape` adopt the host's corner
        // radius + margins, rather than fixing a width/corner ourselves.
        .frame(maxWidth: .infinity)
        .background(theme.dehydratedBackground)
        .clipShape(ContainerRelativeShape())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subject)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.statsSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(sipCount)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.statsPrimary)
                    Text(sipCount == 1 ? "sip" : "sips")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.statsSecondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(volumeML)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.waterColor)
                    Text("ml")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.statsSecondary)
                }
                Text("water intake")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.statsSecondary)
            }
        }
    }

    private var chart: some View {
        let maxCount = max(week.map(\.count).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(week) { day in
                let isHighlighted = day.id == highlightID
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isHighlighted ? theme.waterColor : theme.statsSecondary.opacity(0.5))
                    .frame(height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 44))
            }
        }
        .frame(height: 44, alignment: .bottom)
    }

    private var trendLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: trend.symbolName)
                .font(.system(size: 12, weight: .bold))
            Text(trend.snippetLabel)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(trend.tintColor(theme: theme))
    }
}

// MARK: - App Shortcuts provider

/// Registers the Siri / Spotlight phrases. Every phrase must contain the
/// `\(.applicationName)` token (an Apple requirement for app-provided
/// shortcuts). The app's display name is "Sip", so it slots in as a natural
/// verb: log reads as "Take a Sip", and the query reads as "How much water did
/// I Sip today". A `\(\.$day)` token lets the query vary by today / yesterday /
/// weekday; the plain query phrases default to today.
struct SipShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSipIntent(),
            phrases: [
                "Take a \(.applicationName)",
                "Log a \(.applicationName)",
                "Add a \(.applicationName)",
                "I drank a \(.applicationName)",
                "Track a \(.applicationName)"
            ],
            shortTitle: "Take a Sip",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: WaterIntakeQueryIntent(),
            phrases: [
                "How much water did I \(.applicationName) \(\.$day)",
                "How much did I \(.applicationName) \(\.$day)",
                "How many \(.applicationName)s did I have \(\.$day)",
                "How much water did I \(.applicationName)",
                "How much did I \(.applicationName)"
            ],
            shortTitle: "Water Intake",
            systemImageName: "chart.bar.fill"
        )
    }
}
