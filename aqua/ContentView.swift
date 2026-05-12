//
//  ContentView.swift
//  aqua
//

import AVFoundation
import SwiftUI
import UIKit

private struct ButtonFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct HeaderFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct WaveShape: Shape {
    var phase: Double
    var amplitude: CGFloat
    var frequency: Double
    var bumpHeight: CGFloat
    var bumpWidth: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(amplitude, bumpHeight) }
        set {
            amplitude = newValue.first
            bumpHeight = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        guard w > 0 else { return path }

        let headroom = amplitude * 2 + bumpHeight

        path.move(to: CGPoint(x: 0, y: headroom))

        for x in stride(from: 0, through: w, by: 1) {
            let t: CGFloat = x / w

            let angle1: CGFloat = (t * frequency + phase) * .pi * 2
            let w1: CGFloat = amplitude * sin(angle1)

            let angle2: CGFloat = (t * frequency * 0.6 - phase * 0.8) * .pi * 2
            let w2: CGFloat = amplitude * 0.4 * sin(angle2)

            let dx: CGFloat = t - 0.5
            let bump: CGFloat = bumpHeight * exp(-dx * dx / (2 * bumpWidth * bumpWidth))

            let y: CGFloat = headroom + w1 + w2 - bump
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: w, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

struct ContentView: View {
    @State private var viewModel = WaterStateViewModel()
    @State private var buttonFrame: CGRect = .zero
    @State private var headerFrame: CGRect = .zero
    @State private var sloshAmplitude: CGFloat = 0
    @State private var showStats = false
    @State private var showVolumeSheet = false
    @State private var showThemePicker = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    /// Theme used to render the UI right now. Theme switching happens
    /// exclusively via the gallery sheet — there is no inline preview state.
    private var theme: AppTheme { viewModel.theme }

    /// Convenience pass-through to the view-model's live hydration value.
    private var hydrationLevel: Double { viewModel.hydrationLevel }

    /// Swaps the key window's `overrideUserInterfaceStyle` between `.dark`
    /// (water covers status bar → trait collection becomes dark → status
    /// bar reads as `.lightContent`, glyphs render in white) and `.light`
    /// (everywhere else — also pins the app to its intended light identity
    /// so users on system-wide Dark Mode still see the cream / stone
    /// themes). Animated so the trait swap fades in lockstep with the
    /// water rising past the safe-area inset rather than snapping.
    private func setStatusBarLightContent(_ light: Bool) {
        let target: UIUserInterfaceStyle = light ? .dark : .light
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let keyWindow, keyWindow.overrideUserInterfaceStyle != target else { return }
        UIView.animate(withDuration: 0.3) {
            keyWindow.overrideUserInterfaceStyle = target
        }
    }

    private static let sipSoundPlayer: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "sip", withExtension: "wav")
                ?? Bundle.main.url(forResource: "sip", withExtension: "mp3")
                ?? Bundle.main.url(forResource: "sip", withExtension: "caf") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }()

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let statusBarBottom = geometry.safeAreaInsets.top

            let waterSurfaceY = screenHeight * (1 - hydrationLevel)
            let bumpH: CGFloat = hydrationLevel > 0 && buttonFrame != .zero
                ? max(0, waterSurfaceY - buttonFrame.midY + 10)
                : 0

            // Status bar glyph polarity follows the background colour behind
            // them. Both themes' `waterColor` is dark (Default: deep blue,
            // Kurosawa: near-black) and both `dehydratedBackground`s are
            // light, so once the water has risen high enough to sit behind
            // the status bar we flip the preferred colour scheme to `.dark`
            // — iOS responds by drawing the time, signal, wifi, and battery
            // glyphs in light content (white). We pad the threshold by a few
            // points so the swap completes a beat before the wave's trough
            // would expose the light dehydrated background underneath.
            let statusBarThreshold = max(0, statusBarBottom - 6)
            let waterCoversStatusBar = waterSurfaceY <= statusBarThreshold

            // Whether the water has actually risen high enough to cover the
            // control-row buttons. Drives the dehydrated ↔ on-water color
            // swap for the sip button, the two side buttons, and the
            // "Last sip" caption. Using `buttonFrame.midY` means the swap
            // happens once roughly half the button is underwater, which feels
            // like the right moment perceptually — earlier than this the
            // translucent on-water styles would be unreadable against the
            // exposed dehydrated background (the very bug we're fixing).
            let buttonsOnWater: Bool = hydrationLevel > 0
                && buttonFrame != .zero
                && waterSurfaceY <= buttonFrame.midY

            ZStack(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    theme.dehydratedBackground
                    waterFillView(screenHeight: screenHeight, bumpHeight: bumpH)
                }
                .ignoresSafeArea()
                .scaleEffect(showStats ? 1.1 : 1)
                .blur(radius: showStats ? 20 : 0)

                VStack(spacing: 0) {
                    stickyHeader(screenHeight: screenHeight, bumpHeight: bumpH)
                        .background(
                            GeometryReader { headerGeo in
                                Color.clear.preference(
                                    key: HeaderFrameKey.self,
                                    value: headerGeo.frame(in: .named("root"))
                                )
                            }
                        )
                    hydrationVisual(screenHeight: screenHeight, bumpHeight: bumpH)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    controlRow(buttonsOnWater: buttonsOnWater)
                    bottomBar(onWater: buttonsOnWater)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, geometry.safeAreaInsets.top + 62)
            }
            .coordinateSpace(name: "root")
            // NB: we deliberately do **not** apply
            // `.preferredColorScheme(theme.preferredColorScheme)` here. That
            // modifier bridges to the hosting controller's
            // `preferredStatusBarStyle = .darkContent` and that *explicit*
            // style wins over every other knob we tried (subclassing
            // `UIHostingController`, overriding `childForStatusBarStyle`,
            // setting `overrideUserInterfaceStyle`). Dropping the modifier
            // lets `preferredStatusBarStyle` fall back to `.default`, which
            // reads the trait collection — and the trait collection is
            // exactly what `UIWindow.overrideUserInterfaceStyle` controls,
            // the same UIKit hook the home indicator's auto contrast adapt
            // hangs off of.
            //
            // The cost of dropping the modifier is that SwiftUI's
            // `\.colorScheme` env value now follows the window's trait
            // collection (it was hard-pinned to `.light` before). We force
            // it back to `.light` on the few system surfaces that care
            // (`SipVolumeSheet`); `ContentView` itself only uses explicit
            // theme colours so it's unaffected, and `ThemeGalleryView`
            // already pins itself to `.preferredColorScheme(.dark)`.
            .onChange(of: waterCoversStatusBar) { _, covers in
                setStatusBarLightContent(covers)
            }
            .onAppear {
                setStatusBarLightContent(waterCoversStatusBar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onPreferenceChange(ButtonFrameKey.self) { buttonFrame = $0 }
        .onPreferenceChange(HeaderFrameKey.self) { headerFrame = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.refreshFromStorage()
            }
        }
        .overlay {
            if showWelcome {
                WelcomeView(theme: viewModel.theme) {
                    hasSeenWelcome = true
                    withAnimation(.spring(duration: 0.4)) {
                        showWelcome = false
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            if !hasSeenWelcome {
                showWelcome = true
            }
        }
        .sheet(isPresented: $showVolumeSheet, onDismiss: {
            viewModel.refreshFromStorage()
        }) {
            SipVolumeSheet(currentVolume: viewModel.sipVolumeML) { newVolume in
                SharedStorage.sipVolumeML = newVolume
            }
        }
        .fullScreenCover(isPresented: $showThemePicker) {
            ThemeGalleryView(
                appliedID: viewModel.theme.id,
                unlockedIDs: viewModel.unlockedThemeIDs,
                onApply: { id in viewModel.applyTheme(id) },
                onUnlock: { id in viewModel.unlockTheme(id) }
            )
        }
    }

    // MARK: - Bottom bar

    private func bottomBar(onWater: Bool) -> some View {
        lastLogText(onWater: onWater)
    }

    private func stickyHeader(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        // `.top` alignment keeps the close (✕) button at the same Y position as
        // the sip-count number it replaces: `headerTitleAndCount`'s HStack is
        // sized by the taller title+subtitle VStack, so the sip count (sitting
        // at the top of that HStack) is higher than the center of the outer
        // ZStack. Without explicit `.top` here, the close button would render
        // centered against the title block and visibly shift downward when the
        // stats overlay opens.
        ZStack(alignment: .top) {
            // Title text + sip-count number get the dual-layer water mask so
            // the color split tracks the wave as it rises/falls through them.
            ZStack {
                headerTitleAndCount(
                    primary: theme.headerPrimary,
                    secondary: theme.headerSecondary,
                    countColor: theme.statsPrimary
                )

                headerTitleAndCount(
                    primary: theme.headerPrimaryOnWater,
                    secondary: theme.headerSecondaryOnWater,
                    countColor: theme.headerPrimaryOnWater
                )
                .mask(waterShapeMask(screenHeight: screenHeight, bumpHeight: bumpHeight))
            }

            // Close (✕) button uses the same dual-layer + blurred water-mask
            // treatment as the stats text it belongs to (see `statsOverlay`):
            // a dehydrated base in `statsPrimary` (dark) plus an on-water
            // overlay in `statsPrimaryOnWater` (light) masked by the wave
            // shape with a 30pt blur. The blur intentionally bleeds the
            // color split across the thin xmark strokes so the glyph reads
            // as a soft gradient as the wave rises/falls through it — same
            // visual language as the sip-count number and stats text.
            ZStack {
                HStack {
                    Spacer()
                    closeButton(color: theme.statsPrimary)
                }

                HStack {
                    Spacer()
                    closeButton(color: theme.statsPrimaryOnWater)
                }
                .mask(waterShapeMask(screenHeight: screenHeight, bumpHeight: bumpHeight).blur(radius: 30))
                .allowsHitTesting(false)
            }
            .opacity(showStats ? 1 : 0)
            .allowsHitTesting(showStats)
        }
        .padding(.vertical, 8)
    }

    /// Renders the title block (Aqua/Sip + 水/飲, top-left) and the sip-count
    /// number (top-right). The close (✕) button is intentionally NOT included
    /// — see `stickyHeader` for why it's rendered separately.
    private func headerTitleAndCount(primary: Color, secondary: Color, countColor: Color) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(theme.id.headerTitleFont)
                    .foregroundStyle(primary)
                    .contentTransition(.opacity)
                Text(headerSubtitle)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(secondary)
                    .contentTransition(.opacity)
            }
            .opacity(showStats ? 0 : 1)

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    showStats.toggle()
                }
            } label: {
                Text("\(viewModel.todaySipCount)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(countColor)
                    .frame(height: 27, alignment: .center)
                    .opacity(showStats ? 0 : 1)
            }
            .buttonStyle(.plain)
        }
    }

    /// Close (✕) button rendered in a given color. Used twice by
    /// `stickyHeader` to build the dual-layer water-mask treatment — see
    /// the comment there for the full story. The 27pt frame matches the
    /// sip-count `Text` it visually replaces so the two share the same
    /// hit target and Y position.
    private func closeButton(color: Color) -> some View {
        Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                showStats.toggle()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(color)
                .frame(height: 27, alignment: .center)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close stats")
    }

    /// Title shown top-left, driven by current hydration state.
    private var headerTitle: String {
        hydrationLevel > 0 ? "Aqua" : "Sip"
    }

    /// Bilingual subtitle shown top-left, paired with `headerTitle`.
    private var headerSubtitle: String {
        hydrationLevel > 0 ? "水" : "飲"
    }

    /// Mask that renders the exact same WaveShape as the water fill,
    /// perfectly synced via TimelineView so the color split tracks every wave frame.
    private func waterShapeMask(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        TimelineView(.animation(paused: hydrationLevel <= 0)) { timeline in
            let wavePhase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 4) / 4
            let baseAmplitude: CGFloat = hydrationLevel > 0 ? 4 : 0
            let waveAmplitude: CGFloat = baseAmplitude + sloshAmplitude
            let waterBase = screenHeight * hydrationLevel
            let totalWaterHeight = waterBase + waveAmplitude * 2 + bumpHeight

            GeometryReader { geo in
                let frame = geo.frame(in: .named("root"))

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    WaveShape(
                        phase: wavePhase,
                        amplitude: waveAmplitude,
                        frequency: 1.5,
                        bumpHeight: bumpHeight,
                        bumpWidth: 0.18
                    )
                    .fill(Color.white)
                    .frame(height: max(0, totalWaterHeight))
                }
                .frame(width: geo.size.width, height: screenHeight, alignment: .bottom)
                .offset(y: -frame.minY)
            }
        }
    }

    private func waterFillView(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        let baseAmplitude: CGFloat = hydrationLevel > 0 ? 4 : 0
        let waveAmplitude: CGFloat = baseAmplitude + sloshAmplitude
        let waterBase = screenHeight * hydrationLevel
        let totalHeight = waterBase + waveAmplitude * 2 + bumpHeight

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            TimelineView(.animation(paused: hydrationLevel <= 0)) { timeline in
                let wavePhase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 4) / 4
                WaveShape(
                    phase: wavePhase,
                    amplitude: waveAmplitude,
                    frequency: 1.5,
                    bumpHeight: bumpHeight,
                    bumpWidth: 0.18
                )
                .fill(theme.waterColor)
            }
            .frame(height: max(0, totalHeight))
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    /// Interpolates between dehydrated and hydrated visuals over the 5s transition.
    private func hydrationVisual(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        ZStack {
            DehydratedView()
                .opacity(1 - hydrationLevel)
            HydratedView()
                .opacity(hydrationLevel)

            if showStats {
                statsOverlay(screenHeight: screenHeight, bumpHeight: bumpHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hydrationLevel)
    }

    // MARK: - Stats overlay

    private func statsOverlay(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        statsContent(
            primary: theme.statsPrimary,
            secondary: theme.statsSecondary
        )
        .overlay {
            statsContent(
                primary: theme.statsPrimaryOnWater,
                secondary: theme.statsSecondaryOnWater
            )
            .mask(waterShapeMask(screenHeight: screenHeight, bumpHeight: bumpHeight).blur(radius: 30))
        }
        .padding(.horizontal, 32)
    }

    private func statsContent(primary: Color, secondary: Color) -> some View {
        VStack(spacing: 32) {
            VStack(spacing: 4) {
                Text("\(viewModel.todaySipCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)
                    .contentTransition(.numericText())
                Text("Sips today")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            }

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(viewModel.todayVolumeML)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(primary)
                        .contentTransition(.numericText())
                    Text("ml")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                }
                Text("In total")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            }

            VStack(spacing: 12) {
                weeklyBarChart(foreground: primary, pastDayColor: secondary)
                averageLabel(foreground: secondary)
            }
        }
    }

    private func weeklyBarChart(foreground: Color, pastDayColor: Color) -> some View {
        let days = viewModel.last7Days
        let maxCount = max(days.map(\.count).max() ?? 1, 1)

        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = index == days.count - 1
                let barHeight: CGFloat = day.count > 0
                    ? max(8, CGFloat(day.count) / CGFloat(maxCount) * 40)
                    : 4

                RoundedRectangle(cornerRadius: 3)
                    .fill(isToday ? foreground : pastDayColor)
                    .frame(width: 8, height: barHeight)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }

    private func averageLabel(foreground: Color) -> some View {
        Group {
            if viewModel.recentAverage > 0 {
                let diff = Double(viewModel.todaySipCount) - viewModel.recentAverage
                if diff > 0 {
                    Text("More than 7-day avg.")
                } else if diff < 0 {
                    Text("Less than 7-day avg.")
                } else {
                    Text("Same as 7-day avg.")
                }
            } else {
                Text("Start sipping to build your history")
            }
        }
        .font(.subheadline)
        .foregroundStyle(foreground)
    }

    /// "Last sip: ..." caption rendered in the bottom bar. Color picks the
    /// on-water (translucent white) vs dehydrated (subtle gray) variant from
    /// the shared `buttonsOnWater` predicate so it stays in sync with the
    /// neighbouring controls when water rises/falls past them.
    private func lastLogText(onWater: Bool) -> some View {
        Group {
            if let date = SharedStorage.lastWaterLogTime {
                Text("Last sip: \(Self.formatLastDrank(date))")
            } else {
                Text("Last sip: —")
            }
        }
        .font(.subheadline)
        .foregroundStyle(onWater ? theme.lastSipOnWater : theme.lastSipDehydrated)
        .animation(.easeInOut(duration: 0.3), value: onWater)
    }

    private static func formatLastDrank(_ date: Date) -> String {
        let cal = Calendar.current
        let timeStr = Self.timeFormatter.string(from: date)
        if cal.isDateInToday(date) {
            return "Today at \(timeStr)"
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday at \(timeStr)"
        }
        let dateStr = cal.isDate(date, equalTo: Date(), toGranularity: .year)
            ? Self.dayMonthFormatter.string(from: date)
            : Self.dayMonthYearFormatter.string(from: date)
        return "\(dateStr) at \(timeStr)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static let dayMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f
    }()

    /// Primary "log a sip" button. Color identity is keyed to whether water
    /// is currently covering the control row:
    /// - **Below water (`onWater == false`)**: solid `waterColor` background
    ///   + white droplet → reads as a strong CTA on the dehydrated cream/
    ///   stone canvas, which is exactly when the user most needs to be
    ///   prompted to drink.
    /// - **Submerged (`onWater == true`)**: theme's `buttonPrimary*` pair
    ///   (white bg + tinted droplet) → high contrast against the water fill.
    private func logWaterButton(onWater: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.5)) {
                viewModel.logWater()
            }
            sloshAmplitude = 10
            withAnimation(.interpolatingSpring(stiffness: 18, damping: 3)) {
                sloshAmplitude = 0
            }
            Self.sipSoundPlayer?.currentTime = 0
            Self.sipSoundPlayer?.play()
        } label: {
            Image(systemName: "drop.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(onWater ? theme.buttonPrimaryForeground : .white)
                .padding(20)
                .background(
                    onWater ? theme.buttonPrimaryBackground : theme.waterColor,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I drank water")
        .animation(.easeInOut(duration: 0.35), value: onWater)
    }

    // MARK: - Bottom control row (volume / sip / theme)

    /// Horizontal row of three buttons: sip-volume (left), log-sip (center,
    /// primary), theme-switch (right). The center button keeps the geometry
    /// reader so the water bump tracks it. `buttonsOnWater` is threaded down
    /// from `body` so all three buttons swap their color pair in unison at
    /// the moment water actually crosses the row.
    private func controlRow(buttonsOnWater: Bool) -> some View {
        HStack(spacing: 28) {
            sipVolumeButton(onWater: buttonsOnWater)
                .opacity(showStats ? 0 : 1)
                .allowsHitTesting(!showStats)

            logWaterButton(onWater: buttonsOnWater)
                .background(
                    GeometryReader { btnGeo in
                        Color.clear.preference(
                            key: ButtonFrameKey.self,
                            value: btnGeo.frame(in: .named("root"))
                        )
                    }
                )

            themeSwitchButton(onWater: buttonsOnWater)
                .opacity(showStats ? 0 : 1)
                .allowsHitTesting(!showStats)
        }
    }

    private func sipVolumeButton(onWater: Bool) -> some View {
        secondaryCircleButton(
            systemImage: "plusminus",
            accessibilityLabel: "Adjust sip amount",
            onWater: onWater
        ) {
            showVolumeSheet = true
        }
    }

    private func themeSwitchButton(onWater: Bool) -> some View {
        secondaryCircleButton(
            systemImage: "circle.righthalf.filled",
            accessibilityLabel: "Change theme",
            onWater: onWater
        ) {
            showThemePicker = true
        }
    }

    /// Shared style for the two flanking circle buttons. Picks the subtle
    /// gray-on-overlay pair when the button is on the dehydrated background
    /// (so it stays visible without competing with the central sip button)
    /// and the translucent-white pair when water has risen over the row.
    private func secondaryCircleButton(
        systemImage: String,
        accessibilityLabel: String,
        onWater: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(onWater ? theme.buttonForegroundOnWater : theme.buttonSubtleForeground)
                .frame(width: 20, height: 20)
                .padding(14)
                .background(
                    onWater ? theme.buttonBackgroundOnWater : theme.buttonSubtleBackground,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeInOut(duration: 0.35), value: onWater)
    }
}

// MARK: - Sip Volume Sheet

struct SipVolumeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var volume: Int
    let onSave: (Int) -> Void

    init(currentVolume: Int, onSave: @escaping (Int) -> Void) {
        _volume = State(initialValue: currentVolume)
        self.onSave = onSave
    }

    private var isAtMinimum: Bool { volume <= 70 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Spacer()

                HStack(spacing: 24) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            volume = max(70, volume - 10)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(isAtMinimum ? Color.blue.opacity(0.3) : .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAtMinimum)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(volume)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("ml")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 150)

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            volume = min(500, volume + 10)
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Text("Each sip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Default sip is 70ml. Changes will apply from the next sip onward — previous sips keep their original amount.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Sip Volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonBorderShape(.circle)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(volume)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                }
            }
        }
        // The root view drives the iOS status bar by flipping the key
        // window's `overrideUserInterfaceStyle` between `.light` and `.dark`
        // — so when this sheet is presented during the high-water state the
        // window trait is `.dark` and the sheet's `.secondary` / `.tertiary`
        // text plus system-coloured chrome would otherwise inherit it.
        // Pinning to `.light` here keeps the sheet's identity stable
        // regardless of what the underlying surface is doing.
        .preferredColorScheme(.light)
    }
}

// MARK: - Theme Gallery

/// Full-screen theme picker modeled on the iOS lock-screen wallpaper gallery.
/// Cards live in a horizontal paging carousel with peeks of adjacent cards on
/// both sides; the bottom Apply / Unlock pill updates as the user scrolls.
struct ThemeGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    let appliedID: ThemeID
    let unlockedIDs: Set<ThemeID>
    let onApply: (ThemeID) -> Void
    let onUnlock: (ThemeID) -> Void

    /// Bound to `ScrollView.scrollPosition` — tracks which card is currently
    /// snapped to center. Starts as `nil` and is set to `appliedID` in
    /// `.onAppear` (see the carousel modifier). `scrollPosition(id:)` is
    /// unreliable at honoring the *initial value* of the binding when the
    /// scroll content depends on a `GeometryReader`, so we deliberately let
    /// the value change after the first layout pass — that state transition
    /// reliably drives the ScrollView to the applied theme.
    @State private var scrolledID: ThemeID?

    private var selectedID: ThemeID { scrolledID ?? appliedID }
    private var selectedTheme: AppTheme { .forID(selectedID) }
    private var isSelectedApplied: Bool { selectedID == appliedID }
    private var isSelectedLocked: Bool { !unlockedIDs.contains(selectedID) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                carousel
                    .frame(maxHeight: .infinity)

                pageIndicator
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                actionPill
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        ZStack {
            Text("Themes")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Close")
            }
        }
        .frame(height: 52)
    }

    /// Paging horizontal carousel. Each card has a fixed width of 82% of the
    /// gallery's available width; the surrounding `.padding(.horizontal, sideInset)`
    /// on the HStack provides the slack needed for the first/last card to
    /// center via `scrollPosition(anchor: .center)`. The leftover slack on the
    /// opposite side becomes the adjacent-card peek.
    private var carousel: some View {
        GeometryReader { proxy in
            let cardFraction: CGFloat = 0.82
            let cardWidth = proxy.size.width * cardFraction
            let sideInset = (proxy.size.width - cardWidth) / 2

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(ThemeID.allCases) { id in
                        ThemePreviewCard(themeID: id)
                            .frame(width: cardWidth)
                            .id(id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, sideInset)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledID, anchor: .center)
            .onAppear {
                // Forces `scrolledID` to transition nil → appliedID after the
                // ScrollView has laid out, which reliably snaps the centered
                // card to the user's currently-applied theme every time the
                // gallery opens.
                scrolledID = appliedID
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(ThemeID.allCases) { id in
                Circle()
                    .fill(id == selectedID ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.2), value: selectedID)
            }
        }
    }

    /// (label, sf-symbol) pair shown inside the bottom pill, derived from
    /// the currently centered card's applied + unlocked state.
    private var actionPillContent: (label: String, icon: String) {
        if isSelectedApplied {
            return ("Applied", "checkmark")
        }
        if isSelectedLocked {
            return ("Unlock \(selectedID.displayName)", "lock.open.fill")
        }
        return ("Set \(selectedID.displayName) as theme", "checkmark")
    }

    /// On a dark gallery background, an "applied" pill uses a translucent
    /// white style so it reads as disabled; otherwise we tint with the
    /// selected theme's dehydrated background + primary header color so the
    /// pill feels like a colored preview of the theme itself.
    private var actionPill: some View {
        let content = actionPillContent
        let bg: Color = isSelectedApplied
            ? Color.white.opacity(0.12)
            : selectedTheme.dehydratedBackground
        let fg: Color = isSelectedApplied
            ? Color.white.opacity(0.55)
            : selectedTheme.headerPrimary

        return Button {
            if isSelectedApplied {
                return
            } else if isSelectedLocked {
                withAnimation(.easeInOut(duration: 0.3)) {
                    onUnlock(selectedID)
                }
            } else {
                onApply(selectedID)
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: content.icon)
                    .font(.system(size: 14, weight: .bold))
                Text(content.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(bg))
        }
        .buttonStyle(.plain)
        .disabled(isSelectedApplied)
        .animation(.easeInOut(duration: 0.2), value: selectedID)
    }
}

/// Single carousel card. Only renders the two ingredients the user cares
/// about: the theme name (display + Chinese, top-left) and the live water
/// wave (animated via TimelineView, ~50% fill).
private struct ThemePreviewCard: View {
    let themeID: ThemeID

    private var theme: AppTheme { .forID(themeID) }
    private let cornerRadius: CGFloat = 36
    private let waterFraction: CGFloat = 0.4

    var body: some View {
        GeometryReader { geo in
            let cardHeight = geo.size.height
            let waterHeight = cardHeight * waterFraction

            ZStack {
                theme.dehydratedBackground

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    TimelineView(.animation) { timeline in
                        let wavePhase = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 4) / 4
                        WaveShape(
                            phase: wavePhase,
                            amplitude: 4,
                            frequency: 1.5,
                            bumpHeight: 0,
                            bumpWidth: 0.18
                        )
                        .fill(theme.waterColor)
                    }
                    .frame(height: waterHeight)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(themeID.displayName)
                        .font(themeID.previewNameFont)
                        .foregroundStyle(theme.headerPrimary)
                    Text(themeID.nameChinese)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.headerSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private extension ThemeID {
    /// Per-theme font for the Latin display name in `ThemePreviewCard`. Both
    /// themes share the same 18pt size so the name slot has a stable optical
    /// height across cards; only the family differs. Kurosawa uses bundled
    /// Crimson Text Regular (serif) for a distinctive editorial feel; the
    /// default theme keeps Inter-Medium (app-wide convention).
    var previewNameFont: Font {
        switch self {
        case .default:
            return .custom("Inter-Medium", size: 18)
        case .kurosawa:
            return .custom("CrimsonText-Regular", size: 18)
        }
    }

    /// Per-theme font for the Latin header title ("Aqua"/"Sip") shown top-left
    /// of `ContentView`. Mirrors `previewNameFont` so the main UI matches the
    /// theme's identity in the gallery card. Kurosawa uses Crimson Text;
    /// the default theme keeps Inter-Medium. The Chinese subtitle stays on
    /// the system font for both themes (Crimson Text has no CJK coverage).
    var headerTitleFont: Font {
        switch self {
        case .default:
            return .custom("Inter-Medium", size: 22)
        case .kurosawa:
            return .custom("CrimsonText-Regular", size: 22)
        }
    }
}

#Preview {
    ContentView()
}

#Preview("Sip Volume Sheet") {
    SipVolumeSheet(currentVolume: 70) { _ in }
}

#Preview("Theme Gallery") {
    ThemeGalleryView(
        appliedID: .default,
        unlockedIDs: [.default],
        onApply: { _ in },
        onUnlock: { _ in }
    )
}
