//
//  ContentView.swift
//  aqua
//

import AVFoundation
import SwiftUI

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
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    private var theme: AppTheme { viewModel.theme }

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
            let waterBaseHeight = screenHeight * viewModel.hydrationLevel
            let waterCoversStatusBar = waterBaseHeight > (screenHeight - statusBarBottom)

            let waterSurfaceY = screenHeight * (1 - viewModel.hydrationLevel)
            let bumpH: CGFloat = viewModel.hydrationLevel > 0 && buttonFrame != .zero
                ? max(0, waterSurfaceY - buttonFrame.midY + 10)
                : 0

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
                    logWaterButton
                        .background(
                            GeometryReader { btnGeo in
                                Color.clear.preference(
                                    key: ButtonFrameKey.self,
                                    value: btnGeo.frame(in: .named("root"))
                                )
                            }
                        )
                    lastLogText
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, geometry.safeAreaInsets.top + 62)
            }
            .coordinateSpace(name: "root")
            .preferredColorScheme(theme.preferredColorScheme)
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
    }

    private func stickyHeader(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        ZStack {
            headerContent(
                primary: theme.headerPrimary,
                secondary: theme.headerSecondary,
                buttonColor: theme.statsPrimary
            )

            headerContent(
                primary: theme.headerPrimaryOnWater,
                secondary: theme.headerSecondaryOnWater,
                buttonColor: theme.headerPrimaryOnWater
            )
            .mask(waterShapeMask(screenHeight: screenHeight, bumpHeight: bumpHeight))
        }
        .padding(.vertical, 8)
    }

    private func headerContent(primary: Color, secondary: Color, buttonColor: Color) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.hydrationLevel > 0 ? "Aqua" : "Sip")
                    .font(.custom("Inter-Medium", size: 22))
                    .foregroundStyle(primary)
                Text(viewModel.hydrationLevel > 0 ? "水" : "飲")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(secondary)
            }
            .opacity(showStats ? 0 : 1)

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    showStats.toggle()
                }
            } label: {
                ZStack {
                    Text("\(viewModel.todaySipCount)")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                        .opacity(showStats ? 0 : 1)

                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .bold))
                        .opacity(showStats ? 1 : 0)
                }
                .foregroundStyle(buttonColor)
                .frame(height: 27, alignment: .center)
            }
            .buttonStyle(.plain)
        }
    }

    /// Mask that renders the exact same WaveShape as the water fill,
    /// perfectly synced via TimelineView so the color split tracks every wave frame.
    private func waterShapeMask(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        TimelineView(.animation(paused: viewModel.hydrationLevel <= 0)) { timeline in
            let wavePhase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 4) / 4
            let baseAmplitude: CGFloat = viewModel.hydrationLevel > 0 ? 4 : 0
            let waveAmplitude: CGFloat = baseAmplitude + sloshAmplitude
            let waterBase = screenHeight * viewModel.hydrationLevel
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
        let baseAmplitude: CGFloat = viewModel.hydrationLevel > 0 ? 4 : 0
        let waveAmplitude: CGFloat = baseAmplitude + sloshAmplitude
        let waterBase = screenHeight * viewModel.hydrationLevel
        let totalHeight = waterBase + waveAmplitude * 2 + bumpHeight

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            TimelineView(.animation(paused: viewModel.hydrationLevel <= 0)) { timeline in
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
                .opacity(1 - viewModel.hydrationLevel)
            HydratedView()
                .opacity(viewModel.hydrationLevel)

            if showStats {
                statsOverlay(screenHeight: screenHeight, bumpHeight: bumpHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.hydrationLevel)
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
                    Button { showVolumeSheet = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(primary)
                    }
                    .buttonStyle(.plain)
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
                    .frame(width: isToday ? 10 : 8, height: barHeight)
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

    private var bottomTextOnWater: Bool { viewModel.hydrationLevel > 0 }

    private var lastLogText: some View {
        Group {
            if let date = SharedStorage.lastWaterLogTime {
                Text("Last sip: \(Self.formatLastDrank(date))")
                    .font(.subheadline)
                    .foregroundStyle(bottomTextOnWater ? theme.lastSipOnWater : theme.lastSipDehydrated)
            } else {
                Text("Last sip: —")
                    .font(.subheadline)
                    .foregroundStyle(bottomTextOnWater ? theme.lastSipOnWater : theme.lastSipDehydrated)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: bottomTextOnWater)
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

    private var logWaterButton: some View {
        let onWater = viewModel.hydrationLevel > 0
        return Button {
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
                .foregroundStyle(onWater ? theme.buttonForegroundOnWater : theme.buttonForeground)
                .padding(20)
                .background(
                    onWater
                        ? theme.buttonBackgroundOnWater
                        : theme.buttonBackground,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I drank water")
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
    }
}

#Preview {
    ContentView()
}

#Preview("Sip Volume Sheet") {
    SipVolumeSheet(currentVolume: 70) { _ in }
}
