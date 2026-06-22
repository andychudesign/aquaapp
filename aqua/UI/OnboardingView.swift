//
//  OnboardingView.swift
//  aqua
//

import AVFoundation
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Shared metrics

private enum OnboardingMetrics {
    static let horizontalPadding: CGFloat = 16
    static let headerChromeTopInset: CGFloat = 62
    static let headerGlassTopPadding: CGFloat = 8
    static let headerGlassButtonSize: CGFloat = 44
    static let sectionLineHeight: CGFloat = 26
    static let titleMoveDuration: TimeInterval = 0.75
    static let introHoldDuration: TimeInterval = 1.0
    static let leadingHoldDuration: TimeInterval = 1.0
    static let fillAnimationDuration: TimeInterval = 0.5
    static let stepTransitionDuration: TimeInterval = 0.4
    static let contentFadeDuration: TimeInterval = 0.45
    /// Ken-Burns-style zoom on photo backgrounds (Steps 2–3).
    static let photoBackgroundZoomDuration: TimeInterval = 32
    static let photoBackgroundZoomStart: CGFloat = 1.0
    static let photoBackgroundZoomEnd: CGFloat = 1.12

    static func headerTitleTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + headerChromeTopInset + headerGlassTopPadding
            + (headerGlassButtonSize - sectionLineHeight) / 2
            + 4
    }
}

// MARK: - Container

/// Four-step onboarding flow.
struct OnboardingView: View {
    let theme: AppTheme
    let colorScheme: ColorScheme
    var onComplete: () -> Void

    @State private var step = 1

    var body: some View {
        Group {
            switch step {
            case 1:
                OnboardingStep1View(theme: theme, colorScheme: colorScheme) {
                    withAnimation(.easeInOut(duration: OnboardingMetrics.stepTransitionDuration)) {
                        step = 2
                    }
                }
            case 2:
                OnboardingPhotoStepView(
                    theme: theme,
                    backgroundImageName: "OnboardingStep2Background",
                    headline: "Use the widget",
                    subheadline: "so you won't get dried out"
                ) {
                    withAnimation(.easeInOut(duration: OnboardingMetrics.stepTransitionDuration)) {
                        step = 3
                    }
                }
            case 3:
                OnboardingPhotoStepView(
                    theme: theme,
                    backgroundImageName: "OnboardingStep3Background",
                    headline: "Connect to the Health App",
                    subheadline: "track the data"
                ) {
                    Task {
                        await HealthKitManager.completeOnboardingAuthorization()
                        WidgetCenter.shared.reloadTimelines(ofKind: "AquaWidget")
                        WidgetCenter.shared.reloadTimelines(ofKind: "SipStatusWidget")
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: OnboardingMetrics.stepTransitionDuration)) {
                                step = 4
                            }
                        }
                    }
                }
            case 4:
                OnboardingStep4View(theme: theme) {
                    onComplete()
                }
            default:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: OnboardingMetrics.stepTransitionDuration), value: step)
    }
}

// MARK: - Step 1

private struct OnboardingStep1View: View {
    let theme: AppTheme
    let colorScheme: ColorScheme
    var onContinue: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var phase: OnboardingStep1Phase = .intro
    @State private var hydrationLevel: Double = 0
    @State private var sloshAmplitude: CGFloat = 0
    @State private var buttonFrame: CGRect = .zero
    @State private var contentVisible = false
    @State private var didScheduleIntroTransition = false
    @State private var titleRowWidth: CGFloat = 72

    private var richWaterColor: Color { theme.id.richWaterColor(scheme: colorScheme) }
    private var richWaterBodyOpacity: Double { theme.id.richWaterBodyOpacity(scheme: colorScheme) }

    private var waterAnimationPaused: Bool {
        hydrationLevel <= 0 || scenePhase != .active
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
            let screenWidth = geometry.size.width
            let safeAreaTop = geometry.safeAreaInsets.top
            let headerTop = OnboardingMetrics.headerTitleTopPadding(safeAreaTop: safeAreaTop)

            let waterSurfaceY = screenHeight * (1 - hydrationLevel)
            let bumpH: CGFloat = hydrationLevel > 0 && buttonFrame != .zero
                ? max(0, waterSurfaceY - buttonFrame.midY + 10)
                : 0
            let baseAmplitude: CGFloat = hydrationLevel > 0 ? 4 : 0
            let waveAmplitude: CGFloat = baseAmplitude + sloshAmplitude

            let statusBarThreshold = max(0, safeAreaTop - 6)
            let waterCoversStatusBar = waterSurfaceY <= statusBarThreshold

            let estimatedLogButtonMidY = screenHeight
                - geometry.safeAreaInsets.bottom
                - 104
            let logButtonMidY = buttonFrame != .zero ? buttonFrame.midY : estimatedLogButtonMidY
            let buttonsOnWater = hydrationLevel > 0 && waterSurfaceY <= logButtonMidY

            let textOrigin = textBlockOrigin(
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                headerTop: headerTop
            )

            ZStack(alignment: .bottom) {
                GlassEffectContainer {
                    ZStack(alignment: .bottom) {
                        theme.dehydratedBackground
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        textBlock
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .offset(x: textOrigin.x, y: textOrigin.y)
                            .animation(
                                .easeInOut(duration: OnboardingMetrics.titleMoveDuration),
                                value: phase
                            )

                        waterFillView(
                            screenHeight: screenHeight,
                            bumpHeight: bumpH
                        )
                    }
                }
                .ignoresSafeArea()

                bottomChrome(buttonsOnWater: buttonsOnWater)
                    .padding(.horizontal, OnboardingMetrics.horizontalPadding)
                    .padding(.bottom, 36)
            }
            .coordinateSpace(name: "onboardingRoot")
            .onChange(of: waterCoversStatusBar) { _, covers in
                applyStatusBar(waterCovers: covers)
            }
            .onAppear {
                applyStatusBar(waterCovers: waterCoversStatusBar)
                scheduleIntroTransitionIfNeeded()
            }
        }
        .ignoresSafeArea()
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    titleRowWidth = width
                }

            instructionBlock
                .opacity(contentVisible ? 1 : 0)
                .animation(.easeIn(duration: OnboardingMetrics.contentFadeDuration), value: contentVisible)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Sip")
                .font(theme.id.headerTitleLatinFont)
                .foregroundStyle(theme.headerPrimary)
            Text("飲")
                .font(chineseTitleFont)
                .fontWeight(theme.id == .kurosawa ? .medium : nil)
                .foregroundStyle(theme.headerSecondary)
        }
    }

    private var instructionBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Take a Sip every 2 hours")
                .font(theme.id.headerTitleLatinFont)
                .foregroundStyle(theme.headerPrimary)
            Text("to stay hydrated")
                .font(chineseTitleFont)
                .fontWeight(theme.id == .kurosawa ? .medium : nil)
                .foregroundStyle(theme.headerPrimary.opacity(0.6))
        }
        .accessibilityHidden(!contentVisible)
    }

    private var chineseTitleFont: Font {
        theme.id == .default ? theme.id.headerTitleLatinFont : .title2
    }

    private func textBlockOrigin(
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        headerTop: CGFloat
    ) -> CGPoint {
        let pad = OnboardingMetrics.horizontalPadding
        let titleRowHeight = OnboardingMetrics.sectionLineHeight
        let centeredTitleY = (screenHeight - titleRowHeight) / 2

        switch phase {
        case .intro:
            return CGPoint(
                x: (screenWidth - titleRowWidth) / 2,
                y: centeredTitleY
            )
        case .titleAtLeading, .ready:
            return CGPoint(x: pad, y: centeredTitleY)
        case .filled:
            return CGPoint(x: pad, y: headerTop)
        }
    }

    @ViewBuilder
    private func bottomChrome(buttonsOnWater: Bool) -> some View {
        VStack(spacing: 8) {
            if phase == .filled {
                OnboardingContinueButton(captionColor: theme.lastSipOnWater, onWater: true, action: onContinue)
                    .transition(.opacity)
            } else if contentVisible {
                logSipButton(onWater: buttonsOnWater)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("onboardingRoot"))
                    } action: { newFrame in
                        buttonFrame = newFrame
                    }

                Text("Log a Sip")
                    .font(.subheadline)
                    .foregroundStyle(
                        buttonsOnWater ? theme.lastSipOnWater : theme.lastSipDehydrated
                    )
            }
        }
        .opacity(bottomChromeOpacity)
        .animation(.easeIn(duration: OnboardingMetrics.contentFadeDuration), value: contentVisible)
        .animation(.easeInOut(duration: 0.35), value: buttonsOnWater)
        .animation(.easeInOut(duration: 0.45), value: phase)
    }

    private var bottomChromeOpacity: Double {
        if phase == .filled { return 1 }
        return contentVisible ? 1 : 0
    }

    private func logSipButton(onWater: Bool) -> some View {
        Button {
            logDemoSip()
        } label: {
            Image(systemName: "drop.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(logDropForeground(onWater: onWater))
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .liquidGlassCircleStyle(onWater: onWater)
        .accessibilityLabel("Log a Sip")
    }

    private func logDropForeground(onWater: Bool) -> Color {
        if onWater { return .white }
        if theme.id == .default { return theme.waterColor }
        return .primary
    }

    private func waterFillView(screenHeight: CGFloat, bumpHeight: CGFloat) -> some View {
        let baseAmplitude: CGFloat = hydrationLevel > 0 ? 4 : 0
        let waveAmplitude: CGFloat = baseAmplitude + sloshAmplitude
        let waterBase = screenHeight * hydrationLevel
        let totalHeight = waterBase + waveAmplitude * 2 + bumpHeight

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            TimelineView(.animation(paused: waterAnimationPaused)) { timeline in
                let wavePhase = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 4) / 4

                LiquidGlassWaterStack(
                    waterColor: richWaterColor,
                    bodyOpacity: richWaterBodyOpacity,
                    wavePhase: wavePhase,
                    amplitude: waveAmplitude,
                    bumpHeight: bumpHeight,
                    bodyHeight: totalHeight
                )
            }
            .frame(height: max(0, totalHeight))
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private func scheduleIntroTransitionIfNeeded() {
        guard !didScheduleIntroTransition else { return }
        didScheduleIntroTransition = true

        DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingMetrics.introHoldDuration) {
            withAnimation(.easeInOut(duration: OnboardingMetrics.titleMoveDuration)) {
                phase = .titleAtLeading
            }
        }

        let contentRevealDelay = OnboardingMetrics.introHoldDuration
            + OnboardingMetrics.leadingHoldDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + contentRevealDelay) {
            phase = .ready
            withAnimation(.easeIn(duration: OnboardingMetrics.contentFadeDuration)) {
                contentVisible = true
            }
        }
    }

    private func logDemoSip() {
        withAnimation(.easeInOut(duration: OnboardingMetrics.fillAnimationDuration)) {
            hydrationLevel = 1.0
            phase = .filled
        }
        sloshAmplitude = 10
        withAnimation(.interpolatingSpring(stiffness: 18, damping: 3)) {
            sloshAmplitude = 0
        }
        Self.sipSoundPlayer?.currentTime = 0
        Self.sipSoundPlayer?.play()
    }

    private func applyStatusBar(waterCovers: Bool) {
        let lightGlyphs = colorScheme == .dark || waterCovers
        OnboardingStatusBar.setLightContent(lightGlyphs)
    }
}

// MARK: - Photo steps (2–3)

private struct OnboardingPhotoStepView: View {
    let theme: AppTheme
    let backgroundImageName: String
    let headline: String
    let subheadline: String
    var onContinue: () -> Void

    @State private var contentVisible = false
    @State private var didScheduleContentReveal = false

    var body: some View {
        GeometryReader { geometry in
            let headerTop = OnboardingMetrics.headerTitleTopPadding(
                safeAreaTop: geometry.safeAreaInsets.top
            )

            ZStack(alignment: .bottom) {
                OnboardingPhotoBackground(
                    imageName: backgroundImageName,
                    size: geometry.size
                )

                VStack(alignment: .leading, spacing: 12) {
                    titleRow
                    instructionBlock
                        .opacity(contentVisible ? 1 : 0)
                        .animation(
                            .easeIn(duration: OnboardingMetrics.contentFadeDuration),
                            value: contentVisible
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, OnboardingMetrics.horizontalPadding)
                .padding(.top, headerTop)

                OnboardingContinueButton(
                    captionColor: .white.opacity(0.6),
                    onWater: true,
                    action: onContinue
                )
                    .opacity(contentVisible ? 1 : 0)
                    .animation(
                        .easeIn(duration: OnboardingMetrics.contentFadeDuration),
                        value: contentVisible
                    )
                    .padding(.bottom, 36)
            }
            .onAppear {
                OnboardingStatusBar.setLightContent(true)
                scheduleContentRevealIfNeeded()
            }
        }
        .ignoresSafeArea()
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Sip")
                .font(theme.id.headerTitleLatinFont)
                .foregroundStyle(.white)
            Text("飲")
                .font(chineseTitleFont)
                .fontWeight(theme.id == .kurosawa ? .medium : nil)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var instructionBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline)
                .font(theme.id.headerTitleLatinFont)
                .foregroundStyle(.white)
            Text(subheadline)
                .font(chineseTitleFont)
                .fontWeight(theme.id == .kurosawa ? .medium : nil)
                .foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityHidden(!contentVisible)
    }

    private var chineseTitleFont: Font {
        theme.id == .default ? theme.id.headerTitleLatinFont : .title2
    }

    private func scheduleContentRevealIfNeeded() {
        guard !didScheduleContentReveal else { return }
        didScheduleContentReveal = true

        DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingMetrics.introHoldDuration) {
            withAnimation(.easeIn(duration: OnboardingMetrics.contentFadeDuration)) {
                contentVisible = true
            }
        }
    }
}

private struct OnboardingPhotoBackground: View {
    let imageName: String
    let size: CGSize
    var zoomEnabled: Bool = true

    @State private var zoom = OnboardingMetrics.photoBackgroundZoomStart

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .scaleEffect(zoomEnabled ? zoom : 1)
            .frame(width: size.width, height: size.height)
            .clipped()
            .background(themeFallbackColor)
            .ignoresSafeArea()
            .onAppear {
                guard zoomEnabled else { return }
                zoom = OnboardingMetrics.photoBackgroundZoomStart
                withAnimation(.linear(duration: OnboardingMetrics.photoBackgroundZoomDuration)) {
                    zoom = OnboardingMetrics.photoBackgroundZoomEnd
                }
            }
    }

    private var themeFallbackColor: Color {
        zoomEnabled ? .black : Color(red: 0.96, green: 0.95, blue: 0.92)
    }
}

// MARK: - Step 4 (achievements)

private struct OnboardingStep4View: View {
    let theme: AppTheme
    var onLogSip: () -> Void

    @State private var contentVisible = false
    @State private var didScheduleContentReveal = false

    var body: some View {
        GeometryReader { geometry in
            let headerTop = OnboardingMetrics.headerTitleTopPadding(
                safeAreaTop: geometry.safeAreaInsets.top
            )

            ZStack(alignment: .bottom) {
                OnboardingPhotoBackground(
                    imageName: "OnboardingStep4Background",
                    size: geometry.size,
                    zoomEnabled: false
                )

                VStack(alignment: .leading, spacing: 12) {
                    titleRow
                    instructionBlock
                        .opacity(contentVisible ? 1 : 0)
                        .animation(
                            .easeIn(duration: OnboardingMetrics.contentFadeDuration),
                            value: contentVisible
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, OnboardingMetrics.horizontalPadding)
                .padding(.top, headerTop)

                OnboardingLogSipControl(
                    theme: theme,
                    onWater: false,
                    caption: "Take a Sip now",
                    captionColor: theme.headerPrimary.opacity(0.6),
                    action: onLogSip
                )
                .opacity(contentVisible ? 1 : 0)
                .animation(
                    .easeIn(duration: OnboardingMetrics.contentFadeDuration),
                    value: contentVisible
                )
                .padding(.bottom, 36)
            }
            .onAppear {
                OnboardingStatusBar.setLightContent(false)
                scheduleContentRevealIfNeeded()
            }
        }
        .ignoresSafeArea()
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Sip")
                .font(theme.id.headerTitleLatinFont)
                .foregroundStyle(theme.headerPrimary)
            Text("飲")
                .font(chineseTitleFont)
                .fontWeight(theme.id == .kurosawa ? .medium : nil)
                .foregroundStyle(theme.headerPrimary.opacity(0.6))
        }
    }

    private var instructionBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sip regularly")
                .font(theme.id.headerTitleLatinFont)
                .foregroundStyle(theme.headerPrimary)
            Text("to earn achievements")
                .font(chineseTitleFont)
                .fontWeight(theme.id == .kurosawa ? .medium : nil)
                .foregroundStyle(theme.headerPrimary.opacity(0.6))
        }
        .accessibilityHidden(!contentVisible)
    }

    private var chineseTitleFont: Font {
        theme.id == .default ? theme.id.headerTitleLatinFont : .title2
    }

    private func scheduleContentRevealIfNeeded() {
        guard !didScheduleContentReveal else { return }
        didScheduleContentReveal = true

        DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingMetrics.introHoldDuration) {
            withAnimation(.easeIn(duration: OnboardingMetrics.contentFadeDuration)) {
                contentVisible = true
            }
        }
    }
}

// MARK: - Shared chrome

private struct OnboardingLogSipControl: View {
    let theme: AppTheme
    var onWater: Bool = false
    let caption: String
    let captionColor: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(dropForeground)
                    .frame(width: 30, height: 30)
            }
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .liquidGlassCircleStyle(onWater: onWater)
            .accessibilityLabel(caption)

            Text(caption)
                .font(.subheadline)
                .foregroundStyle(captionColor)
        }
    }

    private var dropForeground: Color {
        if onWater { return .white }
        if theme.id == .default { return theme.waterColor }
        return .primary
    }
}

private struct OnboardingContinueButton: View {
    let captionColor: Color
    var onWater: Bool = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(onWater ? .white : .primary)
                    .frame(width: 24, height: 24)
            }
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .liquidGlassCircleStyle(onWater: onWater)
            .accessibilityLabel("Continue")

            Text("Continue")
                .font(.subheadline)
                .foregroundStyle(captionColor)
        }
    }
}

// MARK: - Status bar

private enum OnboardingStatusBar {
    static func setLightContent(_ light: Bool) {
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
}

// MARK: - Phases

private enum OnboardingStep1Phase: Equatable {
    case intro
    case titleAtLeading
    case ready
    case filled
}

#Preview("Step 1") {
    OnboardingStep1View(theme: .default, colorScheme: .light) { }
}

#Preview("Step 2") {
    OnboardingPhotoStepView(
        theme: .default,
        backgroundImageName: "OnboardingStep2Background",
        headline: "Use the widget",
        subheadline: "so you won't get dried out"
    ) { }
}

#Preview("Step 3") {
    OnboardingPhotoStepView(
        theme: .default,
        backgroundImageName: "OnboardingStep3Background",
        headline: "Connect to the Health App",
        subheadline: "track the data"
    ) { }
}

#Preview("Step 4") {
    OnboardingStep4View(theme: .default) { }
}
