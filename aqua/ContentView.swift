//
//  ContentView.swift
//  aqua
//

import SwiftUI

private struct ButtonFrameKey: PreferenceKey {
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

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(phase, AnimatablePair(amplitude, bumpHeight)) }
        set {
            phase = newValue.first
            amplitude = newValue.second.first
            bumpHeight = newValue.second.second
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
    @State private var wavePhase: Double = 0
    @State private var buttonFrame: CGRect = .zero
    @State private var sloshAmplitude: CGFloat = 0
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    private static let waterBlue = Color(red: 0.2, green: 0.55, blue: 0.9)
    private static let dehydratedBackground = Color(red: 0.98, green: 0.96, blue: 0.92)

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
                    Self.dehydratedBackground
                    waterFillView(screenHeight: screenHeight, bumpHeight: bumpH)
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    stickyHeader
                    hydrationVisual
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
            .preferredColorScheme(.light)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onPreferenceChange(ButtonFrameKey.self) { buttonFrame = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.refreshFromStorage()
            }
        }
        .overlay {
            if showWelcome {
                WelcomeView {
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
    }

    private var headerOnWater: Bool { viewModel.hydrationLevel > 0.78 }

    private var stickyHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.hydrationLevel > 0 ? "Aqua" : "Sip")
                .font(.custom("Inter-Medium", size: 22))
                .foregroundStyle(headerOnWater ? .white : Color(white: 0.1))
            Text(viewModel.hydrationLevel > 0 ? "水" : "飲")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(headerOnWater ? Color.white.opacity(0.5) : Color(red: 0.35, green: 0.55, blue: 0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.3), value: headerOnWater)
    }

    private func waterFillView(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        let baseAmplitude: CGFloat = viewModel.hydrationLevel > 0 ? 4 : 0
        let waveAmplitude: CGFloat = baseAmplitude + sloshAmplitude
        let waterBase = screenHeight * viewModel.hydrationLevel
        let totalHeight = waterBase + waveAmplitude * 2 + bumpHeight

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            WaveShape(
                phase: wavePhase,
                amplitude: waveAmplitude,
                frequency: 1.5,
                bumpHeight: bumpHeight,
                bumpWidth: 0.18
            )
            .fill(Self.waterBlue)
            .frame(height: max(0, totalHeight))
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                wavePhase = 1
            }
        }
    }

    /// Interpolates between dehydrated and hydrated visuals over the 5s transition.
    private var hydrationVisual: some View {
        ZStack {
            DehydratedView()
                .opacity(1 - viewModel.hydrationLevel)
            HydratedView()
                .opacity(viewModel.hydrationLevel)
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.hydrationLevel)
    }

    private var bottomTextOnWater: Bool { viewModel.hydrationLevel > 0.08 }

    private var lastLogText: some View {
        Group {
            if let date = SharedStorage.lastWaterLogTime {
                Text("Last drank: \(Self.formatLastDrank(date))")
                    .font(.subheadline)
                    .foregroundStyle(bottomTextOnWater ? Color.white.opacity(0.5) : Color.gray.opacity(0.6))
            } else {
                Text("Last drank: —")
                    .font(.subheadline)
                    .foregroundStyle(bottomTextOnWater ? Color.white.opacity(0.5) : Color.gray.opacity(0.4))
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
        Button {
            withAnimation(.easeInOut(duration: 0.5)) {
                viewModel.logWater()
            }
            sloshAmplitude = 10
            withAnimation(.interpolatingSpring(stiffness: 18, damping: 3)) {
                sloshAmplitude = 0
            }
        } label: {
            Image(systemName: "drop.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .padding(20)
                .background(Self.waterBlue, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I drank water")
    }
}

#Preview {
    ContentView()
}
