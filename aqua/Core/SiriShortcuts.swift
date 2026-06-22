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
//    3. "Sip, how much did I take       → `WaterIntakeQueryIntent`
//        this week / last week"            (day parameter: thisWeek, lastWeek)
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

        // HealthKit auth is handled in onboarding Step 3; write only if already
        // authorized. The sip is still recorded locally and in widgets.
        _ = await HealthKitManager.saveSip(requestAuth: false)

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

    init() {}

    init(day: DayQuery) {
        self.day = day
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let theme = SharedStorage.currentTheme
        let weekDays = SharedStorage.last7DaysSipCounts.map { SipDay(id: $0.date, count: $0.count) }

        if day.isWeekScope {
            let scope = day.weekScope!
            let comparisonScope = day.comparisonWeekScope!
            let count = SharedStorage.sipCount(forWeek: scope)
            let volume = SharedStorage.estimatedVolumeML(forWeek: scope)
            let highlightIDs = SharedStorage.availableDateKeysInWeek(scope: scope)
            let average = SharedStorage.dailyAverage(forWeek: scope)
            let comparisonAverage = SharedStorage.dailyAverage(forWeek: comparisonScope)
            let trend = SipTrend(
                count: Int(average.rounded()),
                comparisonAverage: comparisonAverage,
                comparisonLabel: day.comparisonLabel!
            )
            let sipWord = count == 1 ? "sip" : "sips"
            let verb = day == .thisWeek ? "you've logged" : "you logged"
            let dialog: IntentDialog =
                "\(day.dialogSubject) \(verb) \(count) \(sipWord), about \(volume) milliliters. \(trend.spokenClause)"
            return .result(
                dialog: dialog,
                view: WaterIntakeSnippet(
                    theme: theme,
                    subject: day.snippetSubject,
                    sipCount: count,
                    volumeML: volume,
                    week: weekDays,
                    highlightIDs: highlightIDs,
                    trend: trend
                )
            )
        }

        let date = Self.resolvedDate(for: day)
        let key = SharedStorage.dateKey(for: date)
        let count = SharedStorage.sipCount(on: key)
        let volume = SharedStorage.estimatedVolumeML(on: key)

        // Compare the chosen day against the other days in the 7-day window
        // that have data.
        let others = weekDays.filter { $0.id != key }.map(\.count)
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
                theme: theme,
                subject: day.snippetSubject,
                sipCount: count,
                volumeML: volume,
                week: weekDays,
                highlightIDs: [key],
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
    case thisWeek
    case lastWeek
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Day" }

    static var caseDisplayRepresentations: [DayQuery: DisplayRepresentation] {
        [
            .today: "Today",
            .yesterday: "Yesterday",
            .thisWeek: "this week",
            .lastWeek: "last week",
            .monday: "Monday",
            .tuesday: "Tuesday",
            .wednesday: "Wednesday",
            .thursday: "Thursday",
            .friday: "Friday",
            .saturday: "Saturday",
            .sunday: "Sunday",
        ]
    }

    var isWeekScope: Bool {
        switch self {
        case .thisWeek, .lastWeek: return true
        default: return false
        }
    }

    var weekScope: SharedStorage.WeekScope? {
        switch self {
        case .thisWeek: return .thisWeek
        case .lastWeek: return .lastWeek
        default: return nil
        }
    }

    var comparisonWeekScope: SharedStorage.WeekScope? {
        switch self {
        case .thisWeek: return .lastWeek
        case .lastWeek: return .thisWeek
        default: return nil
        }
    }

    var comparisonLabel: String? {
        switch self {
        case .thisWeek: return "last week"
        case .lastWeek: return "this week"
        default: return nil
        }
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
        case .today, .yesterday, .thisWeek, .lastWeek: return nil
        }
    }

    /// Sentence-leading subject for the spoken dialog ("Today", "Yesterday",
    /// "On Monday", "This week").
    var dialogSubject: String {
        switch self {
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek:  return "This week"
        case .lastWeek:  return "Last week"
        default:         return "On \(snippetSubject)"
        }
    }

    /// Short label for the snippet header.
    var snippetSubject: String {
        switch self {
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek:  return "This week"
        case .lastWeek:  return "Last week"
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
    /// Human label for the comparison baseline ("7-day average", "last week", …).
    let comparisonLabel: String

    init(count: Int, comparisonAverage: Double, comparisonLabel: String = "7-day") {
        self.comparisonLabel = comparisonLabel
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
        case .flat:   return "That's right in line with your \(comparisonLabel) average."
        case .up:     return "That's \(percent) percent above your \(comparisonLabel) average. Nice work."
        case .down:   return "That's \(percent) percent below your \(comparisonLabel) average — time for another sip."
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
        case .up:     return "\(percent)% above your \(comparisonLabel) average"
        case .down:   return "\(percent)% below your \(comparisonLabel) average"
        case .flat:   return "On par with your \(comparisonLabel) average"
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

// MARK: - Snippet layout helper

private extension View {
    /// Encourages the Siri snippet host to offer the full slot width (~85 % of
    /// the panel) instead of sizing to English content width. Pair with
    /// `ContainerRelativeShape()` — see SIP_CONTEXT V1.5 snippet notes.
    func snippetFillWidth() -> some View {
        frame(idealWidth: 1000, maxWidth: .infinity)
    }
}

// MARK: - Snippet: sip logged

private enum SipLoggedSnippetMetrics {
    /// Source PNG is 1024 × 451 px (@3x) → ~341 × 150 pt.
    static let aspectRatio: CGFloat = 1024.0 / 451.0
    static let backgroundAsset = "SipLoggedSnippetBackground"
}

/// Siri result card for `LogSipIntent`. Designer PNG includes "Sip logged" +
/// reflection; SwiftUI overlays only the dynamic count/volume subtitle.
struct SipLoggedSnippet: View {
    let theme: AppTheme
    let sipCount: Int
    let volumeML: Int

    var body: some View {
        ZStack {
            Image(backgroundAssetName)
                .resizable()
                .scaledToFill()

            Text("\(sipCount) today · \(volumeML) ml")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .offset(y: 12)
        }
        .snippetFillWidth()
        .aspectRatio(SipLoggedSnippetMetrics.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(ContainerRelativeShape())
    }

    private var backgroundAssetName: String {
        switch theme.id {
        case .default:  return SipLoggedSnippetMetrics.backgroundAsset
        case .kurosawa: return "SipLoggedSnippetBackgroundKurosawa"
        }
    }
}

// MARK: - Snippet: water intake

private enum WaterIntakeSnippetMetrics {
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.55)
    static let chartBarMaxHeight: CGFloat = 72
    static let chartLabelHeight: CGFloat = 13
    static let chartLabelSpacing: CGFloat = 5
    static let chartBarSpacing: CGFloat = 5
    static let chartBarCornerRadius: CGFloat = 3
    static let chartWidthFraction: CGFloat = 0.48
    static let columnGap: CGFloat = 10
    static let blueLineThickness: CGFloat = 4
    static let minContentHeight: CGFloat = 96
    static let maxContentHeight: CGFloat = 156
    static let trendToLineSpacing: CGFloat = 6
    static let statsGap: CGFloat = 8
    static let statsTopPadding: CGFloat = 2
    static let statsBelowLineThreshold: CGFloat = 0.5
    static let metricFontSize: CGFloat = 26
    static let metricLineSpacing: CGFloat = 8
    static let cardHorizontalPadding: CGFloat = 20
    static let cardTopPadding: CGFloat = 18
    static let cardBottomPadding: CGFloat = 20
    static let trendLabelHeight: CGFloat = 16
    static let statsBlockHeight: CGFloat = 58

    static func barPixelHeight(count: Int, maxCount: Int) -> CGFloat {
        guard count > 0 else { return 2 }
        return max(3, CGFloat(count) / CGFloat(maxCount) * chartBarMaxHeight)
    }
}

/// Siri result card for `WaterIntakeQueryIntent`: 7-day average status sits
/// directly above a blue reference line aligned to the highlighted bar crest,
/// core stats on the left, weekly bar chart on the right. When that bar is
/// below half the chart, stats sit above the line block; otherwise below it.
struct WaterIntakeSnippet: View {
    let theme: AppTheme
    let subject: String
    let sipCount: Int
    let volumeML: Int
    let week: [SipDay]
    let highlightIDs: Set<String>
    let trend: SipTrend

    private var contentMetrics: SnippetContentMetrics {
        SnippetContentMetrics(week: week, highlightIDs: highlightIDs)
    }

    var body: some View {
        contentRegion
            .padding(.horizontal, WaterIntakeSnippetMetrics.cardHorizontalPadding)
            .padding(.top, WaterIntakeSnippetMetrics.cardTopPadding)
            .padding(.bottom, WaterIntakeSnippetMetrics.cardBottomPadding)
            .snippetFillWidth()
            .background { WaterIntakeSnippetCardBackground() }
            .clipShape(ContainerRelativeShape())
    }

    private var contentRegion: some View {
        GeometryReader { geo in
            let layout = SnippetLayout(
                metrics: contentMetrics,
                width: geo.size.width
            )

            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: WaterIntakeSnippetMetrics.columnGap) {
                    leftColumn(layout: layout)
                        .frame(width: layout.leftWidth, height: layout.contentHeight, alignment: .topLeading)

                    weeklyChart(layout: layout)
                }

                trendAndLine
                    .frame(width: geo.size.width, alignment: .leading)
                    .offset(y: layout.trendTopY)
            }
            .clipped()
        }
        .frame(height: contentMetrics.contentHeight)
    }

    private func leftColumn(layout: SnippetLayout) -> some View {
        Group {
            if layout.statsBelowLine {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: layout.statsInsetFromTop)
                    leftStats
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    leftStats
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var trendAndLine: some View {
        VStack(alignment: .leading, spacing: WaterIntakeSnippetMetrics.trendToLineSpacing) {
            trendLabel
            Capsule()
                .fill(theme.waterColor)
                .frame(height: WaterIntakeSnippetMetrics.blueLineThickness)
        }
    }

    private var trendLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: trend.symbolName)
                .font(.system(size: 11, weight: .bold))
            Text(trend.snippetLabel)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(theme.waterColor)
    }

    private var leftStats: some View {
        VStack(alignment: .leading, spacing: WaterIntakeSnippetMetrics.metricLineSpacing) {
            metricLine(value: "\(sipCount)", suffix: countSuffix)
            metricLine(value: "\(volumeML)", suffix: volumeSuffix)
        }
    }

    private func metricLine(value: String, suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(
                    size: WaterIntakeSnippetMetrics.metricFontSize,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(WaterIntakeSnippetMetrics.primaryText)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(suffix)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WaterIntakeSnippetMetrics.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func weeklyChart(layout: SnippetLayout) -> some View {
        let barCount = CGFloat(week.count)
        let spacing = WaterIntakeSnippetMetrics.chartBarSpacing
        let barWidth = max(8, (layout.chartWidth - spacing * (barCount - 1)) / barCount)

        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(week) { day in
                let isHighlighted = highlightIDs.contains(day.id)
                let barHeight = WaterIntakeSnippetMetrics.barPixelHeight(
                    count: day.count,
                    maxCount: layout.maxCount
                )

                VStack(spacing: WaterIntakeSnippetMetrics.chartLabelSpacing) {
                    RoundedRectangle(
                        cornerRadius: WaterIntakeSnippetMetrics.chartBarCornerRadius,
                        style: .continuous
                    )
                    .fill(isHighlighted
                        ? WaterIntakeSnippetMetrics.primaryText
                        : WaterIntakeSnippetMetrics.secondaryText.opacity(0.4))
                    .frame(width: barWidth, height: barHeight)

                    Text(weekdayLetter(for: day.id))
                        .font(.system(size: 11, weight: isHighlighted ? .semibold : .medium))
                        .foregroundStyle(isHighlighted
                            ? WaterIntakeSnippetMetrics.primaryText
                            : WaterIntakeSnippetMetrics.secondaryText)
                }
            }
        }
        .frame(width: layout.chartWidth, height: layout.chartBlockHeight, alignment: .bottom)
    }

    private var countSuffix: String {
        switch subject {
        case "Today":      return "sip today"
        case "This week":  return "sips this week"
        case "Last week":  return "sips last week"
        default:           return "sips"
        }
    }

    private var volumeSuffix: String {
        "ml in total"
    }

    private func weekdayLetter(for dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard let date = formatter.date(from: dateKey) else { return "" }
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        let symbol = Calendar.current.shortWeekdaySymbols[weekday]
        return String(symbol.prefix(1))
    }
}

/// Dark gradient card surface for the water-intake snippet. Real `.glassEffect`
/// blanked the entire card in the Siri snippet host (same class of bug as Log
/// Sip + `GlassEffectContainer`) — this faux-depth stack is host-safe.
private struct WaterIntakeSnippetCardBackground: View {
    var body: some View {
        ContainerRelativeShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color(white: 0.16),
                        Color(white: 0.11),
                        Color(white: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                ContainerRelativeShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.32), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.38)
                        )
                    )
            }
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.04),
                                Color.black.opacity(0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
    }
}

/// Week-level sizing for the water-intake snippet — dynamic content height from
/// the tallest bar plus trend/stats space when today leads the week.
private struct SnippetContentMetrics {
    let maxCount: Int
    let maxBarPx: CGFloat
    let highlightBarPx: CGFloat
    let chartBlockHeight: CGFloat
    let contentHeight: CGFloat
    let barRatio: CGFloat
    let statsBelowLine: Bool
    let isHighlightTallest: Bool
    let trendBlockHeight: CGFloat

    init(week: [SipDay], highlightIDs: Set<String>) {
        let m = WaterIntakeSnippetMetrics.self
        maxCount = max(week.map(\.count).max() ?? 0, 1)
        let highlightCount = week.filter { highlightIDs.contains($0.id) }.map(\.count).max() ?? 0
        maxBarPx = m.barPixelHeight(count: maxCount, maxCount: maxCount)
        highlightBarPx = m.barPixelHeight(count: highlightCount, maxCount: maxCount)
        chartBlockHeight = maxBarPx + m.chartLabelSpacing + m.chartLabelHeight
        trendBlockHeight = m.trendLabelHeight + m.trendToLineSpacing + m.blueLineThickness
        barRatio = CGFloat(highlightCount) / CGFloat(maxCount)
        statsBelowLine = barRatio >= m.statsBelowLineThreshold
        isHighlightTallest = highlightCount >= maxCount

        let statsPath = trendBlockHeight + m.blueLineThickness + m.statsGap + m.statsBlockHeight

        let computed: CGFloat
        if statsBelowLine {
            if isHighlightTallest {
                // Trend flush above today's (tallest) bar crest, stats below the line.
                computed = max(chartBlockHeight + trendBlockHeight, statsPath)
            } else {
                // Drop dead space above the trend — height tracks today's bar, not the
                // fixed 72pt chart well.
                let compact = trendBlockHeight + m.chartLabelSpacing + m.chartLabelHeight + highlightBarPx
                computed = max(compact, statsPath, chartBlockHeight)
            }
        } else if isHighlightTallest {
            computed = max(
                m.statsBlockHeight + m.statsGap + trendBlockHeight + chartBlockHeight,
                chartBlockHeight
            )
        } else {
            let compact = m.statsBlockHeight + m.statsGap + trendBlockHeight
                + m.chartLabelSpacing + m.chartLabelHeight + highlightBarPx
            computed = max(compact, chartBlockHeight)
        }

        contentHeight = min(
            m.maxContentHeight,
            max(m.minContentHeight, computed)
        )
    }
}

/// Shared geometry for `WaterIntakeSnippet` — one source of truth for bar crest,
/// blue-line, trend, and stats-column placement.
private struct SnippetLayout {
    let maxCount: Int
    let maxBarPx: CGFloat
    let highlightBarPx: CGFloat
    let chartBlockHeight: CGFloat
    let contentHeight: CGFloat
    let barRatio: CGFloat
    let barTopY: CGFloat
    let lineTopY: CGFloat
    let trendTopY: CGFloat
    let statsBelowLine: Bool
    let statsInsetFromTop: CGFloat
    let chartWidth: CGFloat
    let leftWidth: CGFloat

    init(metrics: SnippetContentMetrics, width: CGFloat) {
        let m = WaterIntakeSnippetMetrics.self
        maxCount = metrics.maxCount
        maxBarPx = metrics.maxBarPx
        highlightBarPx = metrics.highlightBarPx
        chartBlockHeight = metrics.chartBlockHeight
        contentHeight = metrics.contentHeight
        barRatio = metrics.barRatio
        statsBelowLine = metrics.statsBelowLine

        barTopY = contentHeight - chartBlockHeight + (maxBarPx - highlightBarPx)
        lineTopY = barTopY
        trendTopY = max(0, lineTopY - metrics.trendBlockHeight)

        chartWidth = width * m.chartWidthFraction
        leftWidth = max(0, width - chartWidth - m.columnGap)

        statsInsetFromTop = statsBelowLine
            ? lineTopY + m.blueLineThickness + m.statsGap
            : m.statsTopPadding
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
                "How many \(.applicationName) did I take \(\.$day)",
                "How much \(.applicationName) did I take \(\.$day)",
                "How many \(.applicationName)s did I take \(\.$day)",
                "How many \(.applicationName) did I do \(\.$day)",
                "How many \(.applicationName) do I take \(\.$day)",
                "How much water I \(.applicationName) \(\.$day)",
                "How many water I \(.applicationName) \(\.$day)",
                "How much water did I \(.applicationName)",
                "How much did I \(.applicationName)",
                "How many \(.applicationName) did I take",
                "How much \(.applicationName) did I take",
                "How many \(.applicationName)s did I take",
                "How many \(.applicationName) did I do",
                "How many \(.applicationName) do I take",
                "How much water I \(.applicationName)",
                "How many water I \(.applicationName)"
            ],
            shortTitle: "Water Intake",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: WaterIntakeQueryIntent(day: .thisWeek),
            phrases: [
                "How much \(.applicationName) did I take this week",
                "How many \(.applicationName)s did I take this week",
                "How much water did I \(.applicationName) this week",
                "How many \(.applicationName) did I do this week"
            ],
            shortTitle: "Water Intake",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: WaterIntakeQueryIntent(day: .lastWeek),
            phrases: [
                "How much \(.applicationName) did I take last week",
                "How many \(.applicationName)s did I take last week",
                "How much water did I \(.applicationName) last week",
                "How many \(.applicationName) did I do last week"
            ],
            shortTitle: "Water Intake",
            systemImageName: "chart.bar.fill"
        )
    }
}
