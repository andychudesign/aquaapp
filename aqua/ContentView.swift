//
//  ContentView.swift
//  aqua
//

import AVFoundation
import SwiftUI
import UIKit

/// Shared surface formula used by `WaveShape` (closed body) and
/// `WaveCrestShape` (open top line). Keeps the two paths pixel-identical.
@inline(__always)
private func waveSurfaceY(
    t: CGFloat,
    phase: Double,
    amplitude: CGFloat,
    frequency: Double,
    bumpHeight: CGFloat,
    bumpWidth: CGFloat,
    headroom: CGFloat
) -> CGFloat {
    let angle1: CGFloat = (t * frequency + phase) * .pi * 2
    let w1: CGFloat = amplitude * sin(angle1)
    let angle2: CGFloat = (t * frequency * 0.6 - phase * 0.8) * .pi * 2
    let w2: CGFloat = amplitude * 0.4 * sin(angle2)
    let dx: CGFloat = t - 0.5
    let bump: CGFloat = bumpHeight * exp(-dx * dx / (2 * bumpWidth * bumpWidth))
    return headroom + w1 + w2 - bump
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

        // Stride by 2 — halves path tessellation cost with no visible change on
        // a smooth sine surface at phone/tablet widths.
        for x in stride(from: 0, through: w, by: 2) {
            let t: CGFloat = x / w
            let y = waveSurfaceY(
                t: t, phase: phase, amplitude: amplitude,
                frequency: frequency, bumpHeight: bumpHeight,
                bumpWidth: bumpWidth, headroom: headroom
            )
            path.addLine(to: CGPoint(x: x, y: y))
        }

        let endY = waveSurfaceY(
            t: 1, phase: phase, amplitude: amplitude,
            frequency: frequency, bumpHeight: bumpHeight,
            bumpWidth: bumpWidth, headroom: headroom
        )
        path.addLine(to: CGPoint(x: w, y: endY))
        path.addLine(to: CGPoint(x: w, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

/// Open path tracing only the top surface of the wave (no closure, no sides).
/// Used to stroke a specular sheen + subsurface glow band along the waterline.
struct WaveCrestShape: Shape {
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
        var started = false
        for x in stride(from: 0, through: w, by: 2) {
            let t: CGFloat = x / w
            let y = waveSurfaceY(
                t: t, phase: phase, amplitude: amplitude,
                frequency: frequency, bumpHeight: bumpHeight,
                bumpWidth: bumpWidth, headroom: headroom
            )
            let p = CGPoint(x: x, y: y)
            if started {
                path.addLine(to: p)
            } else {
                path.move(to: p)
                started = true
            }
        }
        if started {
            let endY = waveSurfaceY(
                t: 1, phase: phase, amplitude: amplitude,
                frequency: frequency, bumpHeight: bumpHeight,
                bumpWidth: bumpWidth, headroom: headroom
            )
            path.addLine(to: CGPoint(x: w, y: endY))
        }
        return path
    }
}

// MARK: - Shared liquid-glass water (main UI + theme gallery)

enum LiquidGlassWaterMetrics {
    static let bodyOpacity = 0.50
    static let meniscusTintOpacity = 0.52
}

/// Full-screen stats scrim — blurred canvas underneath, white type on top.
private enum StatsOverlayMetrics {
    static let scrimOpacity = 0.50
    static let backgroundBlur: CGFloat = 26
    static let horizontalPadding: CGFloat = 16
    /// Matches layer-3 `padding(.top, safeArea + headerChromeTopInset)`.
    static let headerChromeTopInset: CGFloat = 62
    /// Matches `headerGlassButtons` inner `.padding(.top, 8)`.
    static let headerGlassTopPadding: CGFloat = 8
    /// Scroll content top inset — lines up with the ✕ / sip-count row.
    static var statsContentTopInset: CGFloat { headerChromeTopInset + headerGlassTopPadding }
    /// `.controlSize(.large)` liquid-glass circle (sip count + close).
    static let headerGlassButtonSize: CGFloat = 44
    /// Line height for `sectionFont` — centres the first stats line on the ✕.
    static let sectionLineHeight: CGFloat = 26

    /// Top padding so the first stats line is vertically centred on the ✕.
    static func statsScrollTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + statsContentTopInset
            + (headerGlassButtonSize - sectionLineHeight) / 2
            + 4
    }
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)
    static let sectionFont = Font.system(size: 22, weight: .medium, design: .default)
    static let bodyFont = Font.system(size: 17, weight: .medium, design: .default)
    static let detailFont = Font.system(size: 15, weight: .medium, design: .default)
    static let edgeFadeHeight: CGFloat = 72
    static let bottomEdgeFadeHeight: CGFloat = 48
    /// Vertical gap between core stats block and Achievements section.
    static let statsToAchievementsSpacing: CGFloat = 65
    /// Mini 7-day chart bar thickness (vertical capsule width).
    static let miniChartBarThickness: CGFloat = 3
    /// Achievement progress track — 40 % of text-column width, same thickness as chart bars.
    static let achievementProgressBarWidthFraction: CGFloat = 0.4
}

/// Full-screen achievement detail — fade over stats, horizontal paging.
private enum AchievementDetailMetrics {
    static let detailCupSize: CGFloat = 234
    static let cupToDetailsSpacing: CGFloat = 32
    static let scrimOpacity: Double = 0.90
    static let fadeAnimation: Animation = .easeInOut(duration: 0.32)
}

/// Red dot for unseen achievement unlocks (sip count + list rows).
private struct NewUpdateBadge: View {
    private static let badgeColor = Color(red: 1, green: 0.23, blue: 0.19)

    var body: some View {
        Circle()
            .fill(Self.badgeColor)
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }
}

extension ThemeID {
    /// Layer-2 water body colour — `#0089E6` for default; Kurosawa charcoal.
    func richWaterColor(scheme: ColorScheme) -> Color {
        switch self {
        case .default:
            return Color(red: 0x00 / 255.0, green: 0x89 / 255.0, blue: 0xE6 / 255.0)
        case .kurosawa:
            // Light mode: near-black base — at 50 % opacity on stone it washed out.
            return scheme == .light ? Color(white: 0.04) : Color(white: 0.06)
        }
    }

    /// Layer-2 fill opacity. Kurosawa light needs a higher alpha so charcoal
    /// reads dark over the warm stone backdrop; default stays translucent blue.
    func richWaterBodyOpacity(scheme: ColorScheme) -> Double {
        switch self {
        case .default:  return LiquidGlassWaterMetrics.bodyOpacity
        case .kurosawa: return scheme == .light ? 0.78 : LiquidGlassWaterMetrics.bodyOpacity
        }
    }

    /// Solid water colour for theme-gallery preview cards only.
    var previewWaterColor: Color {
        switch self {
        case .default:
            return Color(red: 0x00 / 255.0, green: 0xA9 / 255.0, blue: 0xEF / 255.0)
        case .kurosawa:
            // Approximates Kurosawa light-mode water on stone (0.04 @ 78 %).
            return Color(red: 0x2E / 255.0, green: 0x2D / 255.0, blue: 0x2B / 255.0)
        }
    }

    /// Latin title in the inline main-screen header ("Sip" / "Aqua").
    var headerTitleLatinFont: Font {
        switch self {
        case .default:
            return .system(size: 22, weight: .medium, design: .default)
        case .kurosawa:
            return .custom("CrimsonText-SemiBold", size: 24)
        }
    }
}

/// Meniscus-edge liquid glass — refracts layer-1 content near the wave crest.
struct MeniscusGlassBand: View {
    let waterColor: Color
    let bodyShape: WaveShape
    let bodyHeight: CGFloat

    var body: some View {
        let fadeEnd = min(0.22, 64 / max(bodyHeight, 1))

        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: bodyHeight)
            .glassEffect(
                .clear.tint(waterColor.opacity(LiquidGlassWaterMetrics.meniscusTintOpacity)),
                in: bodyShape
            )
            .mask(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: fadeEnd * 0.45),
                        .init(color: .clear, location: fadeEnd)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
    }
}

/// Transparent tinted wave body + meniscus glass + depth/crest highlights.
struct LiquidGlassWaterStack: View {
    let waterColor: Color
    let bodyOpacity: Double
    let wavePhase: Double
    let amplitude: CGFloat
    let bumpHeight: CGFloat
    let bodyHeight: CGFloat

    var body: some View {
        let bodyShape = WaveShape(
            phase: wavePhase, amplitude: amplitude,
            frequency: 1.5, bumpHeight: bumpHeight, bumpWidth: 0.18
        )
        let crestShape = WaveCrestShape(
            phase: wavePhase, amplitude: amplitude,
            frequency: 1.5, bumpHeight: bumpHeight, bumpWidth: 0.18
        )
        let height = max(bodyHeight, 1)

        ZStack(alignment: .top) {
            bodyShape
                .fill(waterColor.opacity(bodyOpacity))

            MeniscusGlassBand(
                waterColor: waterColor,
                bodyShape: bodyShape,
                bodyHeight: height
            )

            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.10), location: 0.0),
                    .init(color: Color.clear, location: 0.20),
                    .init(color: Color.black.opacity(0.12), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(bodyShape)
            .blendMode(.overlay)
            .allowsHitTesting(false)

            crestShape
                .stroke(Color.white.opacity(0.18), lineWidth: 12)
                .blur(radius: 7)
                .offset(y: 5)
                .clipShape(bodyShape)
                .allowsHitTesting(false)

            crestShape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.75),
                            Color.white.opacity(0.25)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.5
                )
                .blur(radius: 0.25)
                .allowsHitTesting(false)
        }
        .clipShape(bodyShape)
    }
}

/// Lightweight gallery preview — solid fill + animated wave only.
private struct ThemePreviewWaterStack: View {
    let waterColor: Color
    let wavePhase: Double
    let amplitude: CGFloat
    let bumpHeight: CGFloat

    var body: some View {
        WaveShape(
            phase: wavePhase, amplitude: amplitude,
            frequency: 1.5, bumpHeight: bumpHeight, bumpWidth: 0.18
        )
        .fill(waterColor)
    }
}

struct ContentView: View {
    @State private var viewModel = WaterStateViewModel()
    @State private var buttonFrame: CGRect = .zero
    @State private var sloshAmplitude: CGFloat = 0
    @State private var showStats = false
    @State private var showVolumeSheet = false
    @State private var showThemePicker = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @State private var pendingPostOnboardingSip = false
    @State private var achievementDetailOpen = false
    @State private var achievementDetailInitialID: AchievementID?
    @State private var achievementDetailScrollID: AchievementID?
    @Environment(\.scenePhase) private var scenePhase

    /// Theme used to render the UI right now. Theme switching happens
    /// exclusively via the gallery sheet — there is no inline preview state.
    private var theme: AppTheme { viewModel.theme }

    /// Convenience pass-through to the view-model's live hydration value.
    private var hydrationLevel: Double { viewModel.hydrationLevel }

    /// Pauses the live wave + liquid-glass stack when nothing needs it —
    /// dehydrated, backgrounded, covered by a sheet/gallery/welcome, or hidden
    /// behind the stats / achievement-detail overlays (still blurred underneath).
    /// Stops the presenter from animating under covers and avoids live-blur cost.
    private var waterAnimationPaused: Bool {
        hydrationLevel <= 0
            || scenePhase != .active
            || showThemePicker
            || showVolumeSheet
            || showWelcome
            || showStats
            || achievementDetailOpen
    }

    private var richWaterColor: Color { theme.id.richWaterColor(scheme: viewModel.colorScheme) }
    private var richWaterBodyOpacity: Double { theme.id.richWaterBodyOpacity(scheme: viewModel.colorScheme) }
    /// Decides the status-bar glyph polarity from both inputs and applies it.
    /// Glyphs must be light (white) whenever the surface behind them is dark —
    /// which is true when the device is in Dark Mode (the dehydrated backdrop
    /// is dark) OR when water has risen over the status bar (both themes'
    /// `waterColor` is dark). In Light Mode with no water over the bar, glyphs
    /// stay dark against the light cream / stone backdrop.
    private func applyStatusBar(waterCovers: Bool) {
        let lightGlyphs = viewModel.colorScheme == .dark || waterCovers
        setStatusBarLightContent(lightGlyphs)
    }

    /// Swaps the key window's `overrideUserInterfaceStyle` between `.dark`
    /// (light status-bar glyphs) and `.light` (dark glyphs). This drives the
    /// status bar *only*; theme colors are resolved explicitly from the
    /// captured system scheme (`viewModel.colorScheme`), so flipping the
    /// window trait here never affects which palette the app renders.
    /// Animated so the trait swap fades in lockstep with the water rising
    /// past the safe-area inset rather than snapping.
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
            let baseAmplitude: CGFloat = hydrationLevel > 0 ? 4 : 0
            let waveAmplitude: CGFloat = baseAmplitude + sloshAmplitude
            // Match `waterFillView`: the visible crest sits above the nominal
            // fill line by wave amplitude + bump, so button swaps track the
            // real water top — not the flat percentage line alone.
            let waterTopY = waterSurfaceY - waveAmplitude * 2 - bumpH

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

            // Top-right glass buttons: layout-math centre + wave crest offset.
            let headerGlassCenterY = geometry.safeAreaInsets.top + 62 + 30
            let sipCountOnWater = hydrationLevel > 0 && waterTopY <= headerGlassCenterY

            // Control row + "Last sip": swap when the nominal fill line crosses the
            // centre log button. Preference frames were unreliable with Liquid
            // Glass, so fall back to layout math (stable bottom chrome insets).
            let estimatedLogButtonMidY = screenHeight
                - geometry.safeAreaInsets.bottom
                - 104 // 36 bottom + ~20 caption + 16 gap + ~32 half log button
            let logButtonMidY = buttonFrame != .zero ? buttonFrame.midY : estimatedLogButtonMidY
            let buttonsOnWater = hydrationLevel > 0 && waterSurfaceY <= logButtonMidY

            ZStack(alignment: .bottom) {
                // Layers 1 + 2 — background, title, translucent water.
                // `GlassEffectContainer` is scoped here so the meniscus-edge
                // glass band (not the full body) can refract layer 1.
                // Blurred together when the stats overlay is open.
                GlassEffectContainer {
                    ZStack(alignment: .bottom) {
                        // Layer 1: full-screen canvas + static title beneath the water.
                        theme.dehydratedBackground
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        bottomLayerTitle
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, StatsOverlayMetrics.horizontalPadding)
                            .padding(.top, headerTitleTopPadding(safeAreaTop: geometry.safeAreaInsets.top))

                        // Layer 2: animated translucent water body.
                        waterFillView(screenHeight: screenHeight, bumpHeight: bumpH)
                    }
                }
                .ignoresSafeArea()
                .scaleEffect(showStats ? 1.1 : 1)
                .blur(radius: showStats ? StatsOverlayMetrics.backgroundBlur : 0)

                if showStats {
                    Color.black.opacity(StatsOverlayMetrics.scrimOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Layer 3: interactive chrome — buttons + last-sip caption.
                if !showStats {
                    VStack(spacing: 0) {
                        headerLayoutSpacer
                        Spacer(minLength: 0)
                        controlRow(buttonsOnWater: buttonsOnWater)
                        bottomBar(onWater: buttonsOnWater)
                            .padding(.top, 16)
                            .padding(.bottom, 36)
                    }
                    .overlay(alignment: .topTrailing) {
                        headerGlassButtons(onWater: sipCountOnWater)
                    }
                    .padding(.horizontal, StatsOverlayMetrics.horizontalPadding)
                    .padding(.top, geometry.safeAreaInsets.top + StatsOverlayMetrics.headerChromeTopInset)
                }
            }
            .overlay {
                if showStats {
                    statsFullScreenOverlay(
                        safeAreaTop: geometry.safeAreaInsets.top,
                        safeAreaBottom: geometry.safeAreaInsets.bottom
                    )
                    .transition(.opacity)
                }
            }
            .overlay {
                if showStats, achievementDetailOpen, let initialID = achievementDetailInitialID {
                    achievementDetailOverlay(
                        initialScrollID: initialID,
                        safeAreaBottom: geometry.safeAreaInsets.bottom,
                        screenSize: geometry.size
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                if showStats, !achievementDetailOpen {
                    closeButton(statsOverlayOpen: true, onWater: sipCountOnWater)
                        .padding(
                            .top,
                            geometry.safeAreaInsets.top + StatsOverlayMetrics.statsContentTopInset
                        )
                        .padding(.trailing, StatsOverlayMetrics.horizontalPadding)
                }
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
            // `\.colorScheme` env value follows the window's trait collection,
            // which `applyStatusBar(waterCovers:)` flips for the glyph trick.
            // `ContentView` doesn't read `\.colorScheme` — it renders from the
            // palette resolved against the *system* scheme (`viewModel.theme`
            // / `viewModel.colorScheme`), so the window flip can't drag the UI
            // into the wrong palette. System surfaces that DO read the trait
            // pin themselves to the system scheme (`SipVolumeSheet`), and
            // `ThemeGalleryView` pins itself to `.dark`.
            .onChange(of: showStats) { _, open in
                if open {
                    return
                }
                dismissAchievementDetail(immediate: true)
                viewModel.markAchievementsSeen()
            }
            .onChange(of: waterCoversStatusBar) { _, covers in
                applyStatusBar(waterCovers: covers)
            }
            .onChange(of: viewModel.colorScheme) { _, _ in
                applyStatusBar(waterCovers: waterCoversStatusBar)
            }
            .onAppear {
                applyStatusBar(waterCovers: waterCoversStatusBar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Refresh both hydration state and the system color scheme.
                // A live Control-Center Dark Mode toggle while foregrounded is
                // picked up on the next activation (same cadence as
                // `SipVolumeSheet`).
                viewModel.updateColorScheme(WaterStateViewModel.currentSystemScheme())
                viewModel.refreshFromStorage()
                AppIconCoordinator.reconcileIfNeeded()
            } else if phase == .background {
                AppIconCoordinator.reconcileIfNeeded()
            }
        }
        .overlay {
            if showWelcome {
                OnboardingView(
                    theme: viewModel.theme,
                    colorScheme: viewModel.colorScheme
                ) {
                    hasSeenWelcome = true
                    pendingPostOnboardingSip = true
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showWelcome = false
                    }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: showWelcome) { _, isShowing in
            guard !isShowing, pendingPostOnboardingSip else { return }
            pendingPostOnboardingSip = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                performAnimatedLogSip()
            }
        }
        .onAppear {
            viewModel.updateColorScheme(WaterStateViewModel.currentSystemScheme())
            AppIconCoordinator.bootstrapIfNeeded()
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
        .onChange(of: showThemePicker) { _, open in
            if open {
                AppIconCoordinator.reconcileIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $showThemePicker, onDismiss: {
            let theme = SharedStorage.selectedThemeID
            SharedStorage.reloadWidgetsForThemeChange()
            AppIconCoordinator.schedulePostDismissReinforces(for: theme)
        }) {
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

    /// Layer-1 title top inset — vertically centred on the sip-count / ✕ row.
    private func headerTitleTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        StatsOverlayMetrics.statsScrollTopPadding(safeAreaTop: safeAreaTop)
    }

    /// Extra top inset inside layer 3 so `headerLayoutSpacer` matches layer 1.
    private var headerTitleSpacerTopOffset: CGFloat {
        StatsOverlayMetrics.statsScrollTopPadding(safeAreaTop: 0)
            - StatsOverlayMetrics.headerChromeTopInset
    }

    /// Layer 1 title — single dehydrated palette. The mid-layer liquid-glass
    /// water refracts this text when the fill rises over it.
    private var bottomLayerTitle: some View {
        headerTitleBlock(
            primary: theme.headerPrimary,
            secondary: theme.headerSecondary
        )
    }

    /// Invisible duplicate of the title block so layer 3 keeps the same
    /// vertical layout the old `stickyHeader` provided.
    private var headerLayoutSpacer: some View {
        headerTitleBlock(primary: .clear, secondary: .clear)
            .padding(.top, headerTitleSpacerTopOffset)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    // MARK: - Stats overlay

    /// Edge-to-edge scroll surface with top/bottom fade masks. Sits above the
    /// scrim so content is not cropped by the main-app header layout spacer.
    private func statsFullScreenOverlay(
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> some View {
        statsScrollContent(
            safeAreaTop: safeAreaTop,
            safeAreaBottom: safeAreaBottom
        )
        .ignoresSafeArea()
    }

    private func achievementDetailOverlay(
        initialScrollID: AchievementID,
        safeAreaBottom: CGFloat,
        screenSize: CGSize
    ) -> some View {
        AchievementDetailOverlay(
            achievements: viewModel.achievements,
            initialScrollID: initialScrollID,
            scrollID: $achievementDetailScrollID,
            screenSize: screenSize,
            safeAreaBottom: safeAreaBottom,
            cupImage: { AnyView(achievementCupImage(for: $0, detail: true)) },
            onAchievementPageShown: acknowledgeAchievementDetailIfNeeded(for:),
            onDismiss: { dismissAchievementDetail() }
        )
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private func openAchievementDetail(_ id: AchievementID) {
        achievementDetailInitialID = id
        achievementDetailScrollID = nil
        withAnimation(AchievementDetailMetrics.fadeAnimation) {
            achievementDetailOpen = true
        }
        acknowledgeAchievementDetailIfNeeded(for: id)
    }

    private func acknowledgeAchievementDetailIfNeeded(for id: AchievementID) {
        guard let progress = viewModel.achievements.first(where: { $0.id == id }),
              progress.isComplete else { return }
        viewModel.acknowledgeFirstAchievementDetailView(id)
    }

    private func dismissAchievementDetail(immediate: Bool = false) {
        guard achievementDetailOpen else { return }

        if immediate {
            achievementDetailOpen = false
            achievementDetailInitialID = nil
            achievementDetailScrollID = nil
            return
        }

        withAnimation(AchievementDetailMetrics.fadeAnimation) {
            achievementDetailOpen = false
        }
        achievementDetailInitialID = nil
        achievementDetailScrollID = nil
    }

    /// Shared cup artwork for list rows and the detail overlay.
    @ViewBuilder
    private func achievementCupImage(for progress: AchievementProgress, detail: Bool = false) -> some View {
        let name = achievementCupAssetName(for: progress, detail: detail)
        if Bundle.main.url(forResource: name, withExtension: "png") != nil
            || UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: detail ? 72 : 28))
                .foregroundStyle(
                    progress.isComplete
                        ? StatsOverlayMetrics.primaryText.opacity(0.85)
                        : StatsOverlayMetrics.secondaryText.opacity(0.5)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// List thumbnails use `Achievement-<id>-{locked,unlocked}`; detail zoom
    /// prefers `Achievement-<id>-{locked,unlocked}-detail`, falling back to list art.
    private func achievementCupAssetName(for progress: AchievementProgress, detail: Bool) -> String {
        let detailName = progress.isComplete
            ? progress.id.unlockedDetailImageName
            : progress.id.lockedDetailImageName
        let listName = progress.isComplete
            ? progress.id.unlockedImageName
            : progress.id.lockedImageName
        guard detail else { return listName }
        if UIImage(named: detailName) != nil {
            return detailName
        }
        return listName
    }

    private func statsScrollContent(safeAreaTop: CGFloat, safeAreaBottom: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StatsOverlayMetrics.statsToAchievementsSpacing) {
                statsSummarySection
                achievementsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, StatsOverlayMetrics.horizontalPadding)
            .padding(.top, StatsOverlayMetrics.statsScrollTopPadding(safeAreaTop: safeAreaTop))
            .padding(.bottom, safeAreaBottom + 32)
        }
        .scrollIndicators(.hidden)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: StatsOverlayMetrics.edgeFadeHeight)

                Rectangle().fill(.black)

                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: StatsOverlayMetrics.bottomEdgeFadeHeight)
            }
        }
    }

    private var statsSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            statsMetricLine(
                value: "\(viewModel.todaySipCount)",
                suffix: "sip today"
            )

            statsMetricLine(
                value: "\(viewModel.todayVolumeML)",
                suffix: "ml in total"
            )

            HStack(alignment: .center, spacing: 10) {
                weeklyBarChart
                averageLabel
            }
        }
    }

    private func statsMetricLine(value: String, suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .foregroundStyle(StatsOverlayMetrics.primaryText)
                .contentTransition(.numericText())
            Text(suffix)
                .foregroundStyle(StatsOverlayMetrics.secondaryText)
        }
        .font(StatsOverlayMetrics.sectionFont)
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Achievements")
                    .foregroundStyle(StatsOverlayMetrics.primaryText)
                Text("成就")
                    .foregroundStyle(StatsOverlayMetrics.secondaryText)
            }
            .font(StatsOverlayMetrics.sectionFont)

            VStack(spacing: 28) {
                ForEach(viewModel.achievements) { achievement in
                    AchievementRow(
                        progress: achievement,
                        showNewBadge: achievement.isComplete && viewModel.isAchievementUnseen(achievement.id),
                        cupImage: { achievementCupImage(for: achievement) },
                        onTap: { openAchievementDetail(achievement.id) }
                    )
                }
            }
        }
    }

    private func headerGlassButtons(onWater: Bool) -> some View {
        sipCountButton(onWater: onWater)
            .padding(.top, StatsOverlayMetrics.headerGlassTopPadding)
    }

    /// Renders the title block (Aqua/Sip + 水/飲, top-left). The sip-count
    /// button lives in `headerGlassButtons`; close (✕) is in `statsFullScreenOverlay`.
    private func headerTitleBlock(primary: Color, secondary: Color) -> some View {
        HStack(alignment: .top) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(headerTitle)
                    .font(theme.id.headerTitleLatinFont)
                    .foregroundStyle(primary)
                    .contentTransition(.opacity)
                Text(headerSubtitle)
                    .font(theme.id == .default
                        ? theme.id.headerTitleLatinFont
                        : .title2)
                    .fontWeight(theme.id == .kurosawa ? .medium : nil)
                    .foregroundStyle(secondary)
                    .contentTransition(.opacity)
            }

            Spacer()
        }
    }

    /// Standalone Liquid Glass sip-count button (top-right). Tapping toggles
    /// the stats overlay. Over water, `.glass` + dark color scheme + white
    /// content (Text needs an explicit foreground; SF Symbols use tint).
    /// The numeral label is a fixed 20×20 slot at 24pt for a single digit; two or
    /// more digits scale down inside the same slot so the glass button never grows.
    private func sipCountButton(onWater: Bool) -> some View {
        let count = viewModel.todaySipCount
        let isSingleDigit = count < 10

        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                showStats.toggle()
            }
        } label: {
            Text("\(count)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(onWater ? .white : .primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(isSingleDigit ? 1.0 : 0.3)
                .allowsTightening(!isSingleDigit)
                .frame(width: 20, height: 20)
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .liquidGlassCircleStyle(onWater: onWater)
        .overlay(alignment: .topTrailing) {
            if viewModel.hasUnseenAchievements {
                NewUpdateBadge()
                    .offset(x: 3, y: -3)
            }
        }
        .accessibilityLabel(
            viewModel.hasUnseenAchievements ? "Show stats, new achievement" : "Show stats"
        )
        .animation(.easeInOut(duration: 0.35), value: onWater)
        .animation(.easeInOut(duration: 0.35), value: viewModel.hasUnseenAchievements)
    }

    /// Close (✕) Liquid Glass button. Crossfades in place with the sip-count
    /// button when the stats overlay is open. Over the stats scrim, always
    /// white on dark glass (ignores `onWater`).
    private func closeButton(statsOverlayOpen: Bool, onWater: Bool) -> some View {
        let glassOnWater = statsOverlayOpen || onWater
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                showStats.toggle()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(glassOnWater ? .white : .primary)
                .frame(width: 20, height: 20)
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .liquidGlassCircleStyle(onWater: glassOnWater)
        .accessibilityLabel("Close stats")
        .animation(.easeInOut(duration: 0.35), value: onWater)
    }

    /// Title shown top-left, driven by current hydration state.
    private var headerTitle: String {
        hydrationLevel > 0 ? "Aqua" : "Sip"
    }

    /// Bilingual subtitle shown top-left, paired with `headerTitle`.
    private var headerSubtitle: String {
        hydrationLevel > 0 ? "水" : "飲"
    }

    /// Layer 2 water rendering: transparent rich-blue body + meniscus-edge
    /// liquid glass (refracts submerged title near the wave crest) + depth
    /// and crest highlights. `WaveShape` amplitude / phase / bump match the fill.
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

    private var weeklyBarChart: some View {
        let days = viewModel.last7Days
        let maxCount = max(days.map(\.count).max() ?? 1, 1)

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = index == days.count - 1
                let barHeight: CGFloat = day.count > 0
                    ? max(3, CGFloat(day.count) / CGFloat(maxCount) * 14)
                    : 2

                Capsule()
                    .fill(isToday ? StatsOverlayMetrics.primaryText : StatsOverlayMetrics.secondaryText)
                    .frame(width: StatsOverlayMetrics.miniChartBarThickness, height: barHeight)
            }
        }
        .frame(height: 14, alignment: .bottom)
    }

    private var averageLabel: some View {
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
        .font(StatsOverlayMetrics.sectionFont)
        .foregroundStyle(StatsOverlayMetrics.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Cup artwork + title + progress or achieved date for one achievement.
    private struct AchievementRow: View {
        let progress: AchievementProgress
        let showNewBadge: Bool
        let cupImage: () -> AnyView
        let onTap: () -> Void

        init(
            progress: AchievementProgress,
            showNewBadge: Bool,
            cupImage: @escaping () -> some View,
            onTap: @escaping () -> Void
        ) {
            self.progress = progress
            self.showNewBadge = showNewBadge
            self.cupImage = { AnyView(cupImage()) }
            self.onTap = onTap
        }

        private static let achievedDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
            return f
        }()

        var body: some View {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: 16) {
                    cupImage()
                        .frame(width: 56, height: 56)
                        .overlay(alignment: .topTrailing) {
                            if showNewBadge {
                                NewUpdateBadge()
                                    .offset(x: 2, y: -2)
                            }
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress.id.title)
                            .font(StatsOverlayMetrics.bodyFont)
                            .foregroundStyle(StatsOverlayMetrics.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if progress.isComplete {
                            achievedSubtitle
                        } else {
                            GeometryReader { geo in
                                let barWidth = geo.size.width
                                    * StatsOverlayMetrics.achievementProgressBarWidthFraction
                                HStack(alignment: .center, spacing: 10) {
                                    AchievementProgressBar(fraction: progress.progressFraction)
                                        .frame(width: barWidth)
                                    Text("\(progress.current)/\(progress.target)")
                                        .font(StatsOverlayMetrics.detailFont)
                                        .foregroundStyle(StatsOverlayMetrics.secondaryText)
                                        .fixedSize()
                                    Spacer(minLength: 0)
                                }
                            }
                            .frame(height: StatsOverlayMetrics.miniChartBarThickness)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(progress.id.title)
            .accessibilityHint("Show achievement details")
        }

        @ViewBuilder
        private var achievedSubtitle: some View {
            switch progress.unlockDisplay {
            case .inProgress:
                EmptyView()
            case .achieved(let date):
                Text("Achieved on \(Self.achievedDateFormatter.string(from: date))")
                    .font(StatsOverlayMetrics.detailFont)
                    .foregroundStyle(StatsOverlayMetrics.secondaryText)
            case .achievedLegacy:
                Text("Achieved")
                    .font(StatsOverlayMetrics.detailFont)
                    .foregroundStyle(StatsOverlayMetrics.secondaryText)
            }
        }
    }

    /// Horizontal progress track — same thickness as the mini 7-day chart bars.
    private struct AchievementProgressBar: View {
        let fraction: Double

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(StatsOverlayMetrics.secondaryText.opacity(0.35))
                    Capsule()
                        .fill(StatsOverlayMetrics.primaryText)
                        .frame(width: max(0, proxy.size.width * fraction))
                }
            }
            .frame(height: StatsOverlayMetrics.miniChartBarThickness)
        }
    }

    /// Achievement detail — paging carousel over the stats list.
    private struct AchievementDetailOverlay: View {
        let achievements: [AchievementProgress]
        let initialScrollID: AchievementID
        @Binding var scrollID: AchievementID?
        let screenSize: CGSize
        let safeAreaBottom: CGFloat
        let cupImage: (AchievementProgress) -> AnyView
        let onAchievementPageShown: (AchievementID) -> Void
        let onDismiss: () -> Void

        /// Hides the carousel until the first page is positioned without animation
        /// (avoids a visible slide from page 1 when opening the 2nd/3rd achievement).
        @State private var isScrollPositionReady = false

        private var selectedID: AchievementID {
            scrollID ?? initialScrollID
        }

        /// Matches the list-row text column so the detail progress bar reads the same width.
        private var progressTrackWidth: CGFloat {
            screenSize.width
                - StatsOverlayMetrics.horizontalPadding * 2
                - 56
                - 16
        }

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                Color.black
                    .opacity(AchievementDetailMetrics.scrimOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    carousel

                    pageIndicator
                        .padding(.top, 28)
                        .padding(.bottom, max(32, safeAreaBottom + 16))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    TapGesture().onEnded { onDismiss() }
                )
            }
            .onChange(of: scrollID) { _, newID in
                guard let newID else { return }
                onAchievementPageShown(newID)
            }
        }

        private var carousel: some View {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(achievements) { progress in
                        AchievementDetailPage(
                            progress: progress,
                            progressTrackWidth: progressTrackWidth,
                            cupImage: cupImage(progress)
                        )
                        .frame(width: screenSize.width)
                        .id(progress.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrollID, anchor: .center)
            .opacity(isScrollPositionReady ? 1 : 0)
            .onAppear(perform: applyInitialScrollPosition)
        }

        private func applyInitialScrollPosition() {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollID = initialScrollID
            }
            // One layout pass at opacity 0 so the target page is settled before reveal.
            DispatchQueue.main.async {
                isScrollPositionReady = true
            }
        }

        private var pageIndicator: some View {
            HStack(spacing: 6) {
                ForEach(achievements) { progress in
                    Circle()
                        .fill(
                            progress.id == selectedID
                                ? StatsOverlayMetrics.primaryText
                                : StatsOverlayMetrics.secondaryText.opacity(0.5)
                        )
                        .frame(width: 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: selectedID)
                }
            }
        }
    }

    /// Single page inside the achievement detail carousel.
    private struct AchievementDetailPage: View {
        let progress: AchievementProgress
        let progressTrackWidth: CGFloat
        let cupImage: AnyView

        private static let achievedDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
            return f
        }()

        var body: some View {
            VStack(spacing: AchievementDetailMetrics.cupToDetailsSpacing) {
                cupImage
                    .frame(
                        width: AchievementDetailMetrics.detailCupSize,
                        height: AchievementDetailMetrics.detailCupSize
                    )

                VStack(spacing: 6) {
                    Text(progress.id.title)
                        .font(StatsOverlayMetrics.bodyFont)
                        .foregroundStyle(StatsOverlayMetrics.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    detailFooter
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, StatsOverlayMetrics.horizontalPadding)
        }

        @ViewBuilder
        private var detailFooter: some View {
            if progress.isComplete {
                switch progress.unlockDisplay {
                case .inProgress:
                    EmptyView()
                case .achieved(let date):
                    Text("Achieved on \(Self.achievedDateFormatter.string(from: date))")
                        .font(StatsOverlayMetrics.detailFont)
                        .foregroundStyle(StatsOverlayMetrics.secondaryText)
                case .achievedLegacy:
                    Text("Achieved")
                        .font(StatsOverlayMetrics.detailFont)
                        .foregroundStyle(StatsOverlayMetrics.secondaryText)
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    AchievementProgressBar(fraction: progress.progressFraction)
                        .frame(
                            width: progressTrackWidth
                                * StatsOverlayMetrics.achievementProgressBarWidthFraction
                        )
                    Text("\(progress.current)/\(progress.target)")
                        .font(StatsOverlayMetrics.detailFont)
                        .foregroundStyle(StatsOverlayMetrics.secondaryText)
                        .fixedSize()
                }
                .frame(width: progressTrackWidth)
            }
        }
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
        .foregroundStyle(
            showStats
                ? StatsOverlayMetrics.secondaryText
                : (onWater ? theme.lastSipOnWater : theme.lastSipDehydrated)
        )
        .animation(.easeInOut(duration: 0.35), value: showStats)
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

    /// Primary "log a sip" button, rendered as a Liquid Glass circle so the
    /// water reads through it. Over water, `.glass` + dark scheme + white tint.
    /// When dehydrated on the default theme, the droplet is explicitly
    /// `waterColor` (blue) instead of the adaptive black glass glyph.
    private func logWaterButton(onWater: Bool) -> some View {
        Button {
            performAnimatedLogSip()
        } label: {
            Image(systemName: "drop.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(logDropForeground(onWater: onWater))
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .liquidGlassCircleStyle(onWater: onWater)
        .accessibilityLabel("I drank water")
        .animation(.easeInOut(duration: 0.35), value: onWater)
    }

    private func performAnimatedLogSip() {
        withAnimation(.easeInOut(duration: 0.5)) {
            viewModel.logWater()
        }
        sloshAmplitude = 10
        withAnimation(.interpolatingSpring(stiffness: 18, damping: 3)) {
            sloshAmplitude = 0
        }
        Self.sipSoundPlayer?.currentTime = 0
        Self.sipSoundPlayer?.play()
    }

    /// Droplet color for the log-sip glass button: white over water; default
    /// theme blue on the dehydrated canvas; other themes keep the adaptive glyph.
    private func logDropForeground(onWater: Bool) -> Color {
        if onWater { return .white }
        if theme.id == .default { return theme.waterColor }
        return .primary
    }

    // MARK: - Bottom control row (volume / sip / theme)

    /// Horizontal row of three buttons: sip-volume (left), log-sip (center,
    /// primary), theme-switch (right). The two flanking buttons are pushed to
    /// the leading/trailing edges (via `Spacer`s) while the center primary
    /// button stays horizontally centered — matching the spread layout in the
    /// design. The center button keeps the geometry reader so the water bump
    /// tracks it.
    private func controlRow(buttonsOnWater: Bool) -> some View {
        HStack(spacing: 0) {
            sipVolumeButton(onWater: buttonsOnWater)
                .opacity(showStats ? 0 : 1)
                .allowsHitTesting(!showStats)

            Spacer(minLength: 0)

            logWaterButton(onWater: buttonsOnWater)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named("root"))
                } action: { newFrame in
                    buttonFrame = newFrame
                }

            Spacer(minLength: 0)

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
            systemImage: "paintpalette",
            accessibilityLabel: "Change theme",
            onWater: onWater
        ) {
            showThemePicker = true
        }
    }

    /// Shared style for the two flanking Liquid Glass circle buttons. Over
    /// water, `.glass` + dark scheme + white tint. Sized as a 20pt glyph in a
    /// 20×20 label, `.large`.
    private func secondaryCircleButton(
        systemImage: String,
        accessibilityLabel: String,
        onWater: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(onWater ? .white : .primary)
                .frame(width: 20, height: 20)
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .liquidGlassCircleStyle(onWater: onWater)
        .accessibilityLabel(accessibilityLabel)
        .animation(.easeInOut(duration: 0.35), value: onWater)
    }
}

/// Resting Liquid Glass circle buttons: light `.glass` + light color scheme on
/// the dehydrated background (dark glyphs); over water, `.glass` + dark scheme
/// + white tint so the material reads dark and glyphs stay white. Both branches
/// pin an explicit `\.colorScheme` so the window-level status-bar trait flip
/// can't drag buttons into the wrong polarity.
/// `.glassProminent` was tried but paints an opaque white fill — do not use.
struct LiquidGlassCircleButtonStyle: ViewModifier {
    let onWater: Bool

    func body(content: Content) -> some View {
        if onWater {
            content
                .buttonStyle(.glass)
                .environment(\.colorScheme, .dark)
                .tint(.white)
        } else {
            content
                .buttonStyle(.glass)
                .environment(\.colorScheme, .light)
        }
    }
}

extension View {
    func liquidGlassCircleStyle(onWater: Bool) -> some View {
        modifier(LiquidGlassCircleButtonStyle(onWater: onWater))
    }
}

// MARK: - Sip Volume Sheet

struct SipVolumeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var volume: Int
    /// System color scheme captured directly from the scene's *screen* trait
    /// so it bypasses the window-level `overrideUserInterfaceStyle` trick
    /// `ContentView` uses for the status-bar adaptation (see comment on
    /// `.preferredColorScheme` below).
    @State private var systemScheme: ColorScheme = SipVolumeSheet.detectSystemScheme()
    let onSave: (Int) -> Void

    init(currentVolume: Int, onSave: @escaping (Int) -> Void) {
        _volume = State(initialValue: currentVolume)
        self.onSave = onSave
    }

    private var isAtMinimum: Bool { volume <= 70 }

    /// Reads the device's *system* light/dark preference, ignoring any
    /// `UIWindow.overrideUserInterfaceStyle` that may currently be active.
    /// `UIWindow.overrideUserInterfaceStyle` only mutates the window's own
    /// trait — the enclosing `UIWindowScene.screen.traitCollection` keeps
    /// reporting the unfiltered system value.
    private static func detectSystemScheme() -> ColorScheme {
        let style = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen.traitCollection.userInterfaceStyle ?? .light
        return style == .dark ? .dark : .light
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Spacer()

                HStack(spacing: 24) {
                    // Liquid Glass stepper controls — matches the sheet's
                    // glass save button and the gallery's glass chrome.
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            volume = max(70, volume - 10)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.blue)
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
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.blue)
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
        // Sync to the OS-level light/dark setting. The root view flips the
        // key window's `overrideUserInterfaceStyle` for the status-bar
        // adaptation trick, which would otherwise drag this sheet into the
        // wrong scheme. `detectSystemScheme()` queries the *screen* trait
        // (unaffected by the window override) so the sheet always matches
        // what the user picked in Settings, not what the app is overriding.
        .preferredColorScheme(systemScheme)
        .onAppear { systemScheme = Self.detectSystemScheme() }
        .onChange(of: scenePhase) { _, phase in
            // Catch the user toggling system Dark Mode while this sheet is
            // visible (e.g. swiping it down to the Control Center toggle).
            if phase == .active {
                systemScheme = Self.detectSystemScheme()
            }
        }
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

    /// Drives the bottom unlock sheet. Tapping the "Unlock <name>" pill on a
    /// locked theme sets this to true rather than committing the unlock
    /// directly — the sheet surfaces what the user gets + the disclaimer
    /// before they commit (and, in v1.5, before StoreKit takes over).
    @State private var showUnlockSheet: Bool = false

    private var selectedID: ThemeID { scrolledID ?? appliedID }
    private var selectedTheme: AppTheme { .forID(selectedID) }
    private var isSelectedApplied: Bool {
        selectedID == appliedID && AppIconCoordinator.isThemeIconAligned(appliedID)
    }
    private var isSelectedLocked: Bool { !unlockedIDs.contains(selectedID) }

    var body: some View {
        ZStack(alignment: .bottom) {
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

            unlockOverlay
        }
        .preferredColorScheme(.dark)
    }

    /// Shared spring for the unlock overlay — passed to
    /// `.animation(_:value: showUnlockSheet)` so open and dismiss use the
    /// same easing as each other and feel close to the system `.sheet` stack
    /// (`SipVolumeSheet`).
    private static let sheetSpring: Animation = .spring(response: 0.42, dampingFraction: 0.88)

    /// Custom bottom-anchored "unlock" sheet replacing what used to be a
    /// `.sheet(isPresented:)`. iOS 26's native sheets have two problems for
    /// this surface: (1) they reserve horizontal margins on larger devices,
    /// which broke the edge-to-edge feel of the gallery, and (2) the system
    /// applies a non-removable dim layer behind the sheet, which made
    /// `.ultraThinMaterial` sample dim-on-black instead of the gallery
    /// content beneath and rendered as a flat dark gray. Rendering our own
    /// overlay sidesteps both: the backdrop dims via `Color.black.opacity(...)`
    /// (tappable to dismiss), and the sheet card itself is just a
    /// `UnlockThemeSheet` with a shaped `.ultraThinMaterial` background that
    /// extends into the home-indicator safe area.
    ///
    /// Slide up / slide down matches the system `.sheet` used by
    /// `SipVolumeSheet`. We **don't** use `if showUnlockSheet { ... }` +
    /// `.transition(.move(edge: .bottom))` here — SwiftUI often fails to run
    /// removal transitions for multi-view `TupleView` branches inside a
    /// `ZStack`, so dismiss looked instant. Instead the overlay stays mounted,
    /// the dimmer animates `opacity`, and the card animates `offset(y:)` off
    /// the bottom of a `GeometryReader` — the same mechanical motion as
    /// Apple's sheet dismiss. All of it is tied to `showUnlockSheet` with a
    /// single `.animation(Self.sheetSpring, value: showUnlockSheet)` so every
    /// mutation site (`actionPill`, backdrop tap, `Unlock now`) gets identical
    /// easing without juggling `withAnimation` manually.
    private var unlockOverlay: some View {
        GeometryReader { geo in
            let hideOffset = max(geo.size.height, 1)

            ZStack(alignment: .bottom) {
                Color.black
                    .opacity(showUnlockSheet ? 0.55 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { showUnlockSheet = false }

                UnlockThemeSheet(themeID: selectedID) {
                    onUnlock(selectedID)
                    showUnlockSheet = false
                }
                .offset(y: showUnlockSheet ? 0 : hideOffset)
            }
            .animation(Self.sheetSpring, value: showUnlockSheet)
            .allowsHitTesting(showUnlockSheet)
        }
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
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                }
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .liquidGlassCircleStyle(onWater: true)
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
                        ThemePreviewCard(
                            themeID: id,
                            waveAnimationPaused: id != selectedID
                        )
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
                showUnlockSheet = true
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

/// Bottom-anchored purchase confirmation surfaced when the user taps the
/// "Unlock <name>" pill on a locked theme in `ThemeGalleryView`. Designed
/// to read like an App Store offer card: the theme name + "Theme" subtitle
/// header, a single large price token ("Free" during the v1.4 free
/// preview), a "You will get" perks list, a prominent CTA, and a small
/// disclaimer footer.
///
/// Rendered as a plain overlay inside `ThemeGalleryView` (not a `.sheet`)
/// so we get full edge-to-edge width on every device and so the background
/// material actually picks up the gallery cards underneath — see the
/// `unlockOverlay` comment for why the native sheet stack didn't work here.
///
/// In v1.5, when StoreKit 2 lands, the "Free" text + onUnlock closure will
/// be replaced with a real `Product` price + `purchase()` flow; the rest
/// of the layout (perks, disclaimer) can stay as-is.
private struct UnlockThemeSheet: View {
    let themeID: ThemeID
    let onUnlock: () -> Void

    /// What the user gets for unlocking. Mirrors the three theme-aware
    /// surfaces already shipped in v1.4 (main app palette + widget palette
    /// + alternate home-screen app icon).
    private var perks: [String] {
        let name = themeID.displayName
        return [
            "\(name) app interface x1",
            "\(name) widget interface x1",
            "\(name) app icon x1"
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(themeID.displayName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Theme")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.top, 32)

            Text("Free")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 22)

            VStack(spacing: 10) {
                Text("You will get")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                ForEach(perks, id: \.self) { perk in
                    Text(perk)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .padding(.top, 30)

            Spacer(minLength: 24)

            Button {
                onUnlock()
            } label: {
                Text("Unlock now")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .accessibilityLabel("Unlock \(themeID.displayName)")

            Text("\(themeID.displayName) is free until the next update. Unlock it now to keep lifetime access, even after the price goes back to normal.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 20)
                .padding(.top, 14)
        }
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .frame(height: 520)
        .background {
            // The rounded-rect material is applied as a background view
            // that itself ignores the bottom safe area, which is what
            // actually pushes the glass behind the home indicator. We
            // previously did `.background(.ultraThinMaterial) + .clipShape
            // + .ignoresSafeArea(edges: .bottom)` on the outer view; the
            // clip happened at the 520pt frame, then the safe-area expand
            // left a clipped-empty band at the bottom that showed the
            // backdrop dim through. Moving the shape into the background
            // slot and letting it ignore safe area keeps the content in
            // its 520pt frame while the material extends to the screen
            // edge.
            UnevenRoundedRectangle(
                topLeadingRadius: 36,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 36,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Single carousel card — theme name + tinted animated water preview.
/// Deliberately omits meniscus liquid glass (see `ThemePreviewWaterStack`).
private struct ThemePreviewCard: View {
    let themeID: ThemeID
    /// Only the centered carousel card animates; peek cards stay on a static frame.
    var waveAnimationPaused: Bool = false

    private var theme: AppTheme { .forID(themeID) }
    private let cornerRadius: CGFloat = 36
    private let waterFraction: CGFloat = 0.4

    var body: some View {
        GeometryReader { geo in
            let cardHeight = geo.size.height
            let waterHeight = cardHeight * waterFraction

            ZStack {
                theme.dehydratedBackground

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(themeID.displayName)
                            .font(themeID.previewTitleLatinFont)
                            .foregroundStyle(theme.headerPrimary)
                        Text(themeID.nameChinese)
                            .font(themeID.previewTitleChineseFont)
                            .foregroundStyle(theme.headerSecondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    TimelineView(.animation(paused: waveAnimationPaused)) { timeline in
                        let wavePhase = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 4) / 4
                        ThemePreviewWaterStack(
                            waterColor: themeID.previewWaterColor,
                            wavePhase: wavePhase,
                            amplitude: 4,
                            bumpHeight: 0
                        )
                    }
                    .frame(height: waterHeight)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private extension ThemeID {
    /// Latin theme name in `ThemePreviewCard`. Mirrors `headerTitleLatinFont`
    /// at 18pt so the carousel cards keep a stable, smaller optical size.
    var previewTitleLatinFont: Font {
        switch self {
        case .default:
            return .system(size: 18, weight: .medium, design: .default)
        case .kurosawa:
            return .custom("CrimsonText-SemiBold", size: 18)
        }
    }

    /// Chinese name beside the Latin title in `ThemePreviewCard`.
    var previewTitleChineseFont: Font {
        switch self {
        case .default:
            return previewTitleLatinFont
        case .kurosawa:
            return .system(size: 18, weight: .medium)
        }
    }

    /// Per-theme font for the Latin header title ("Aqua"/"Sip") shown top-left
    /// of `ContentView`. Legacy alias — prefer `headerTitleLatinFont`.
    var headerTitleFont: Font {
        switch self {
        case .default:
            // Matched to the sip-count number's 24pt rounded system font so
            // the two header elements share an optical baseline. Was 22pt
            // when Inter-Medium was assumed to be bundled (Inter has a
            // slightly higher x-height than system, which would have read
            // optically close to 24pt rounded). Inter isn't actually
            // bundled — `.custom("Inter-Medium", ...)` silently falls back
            // to the system font — so we were comparing system 22pt vs
            // system rounded 24pt, and the title visibly read smaller
            // (especially under the smallest Dynamic Type setting where
            // the 2pt delta isn't absorbed by any optical compensation).
            return .custom("Inter-Medium", size: 24)
        case .kurosawa:
            return .custom("CrimsonText-SemiBold", size: 24)
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

#Preview("Unlock Theme Sheet") {
    ZStack(alignment: .bottom) {
        LinearGradient(
            colors: [Color(red: 0.18, green: 0.36, blue: 0.78), Color(white: 0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        Color.black.opacity(0.55).ignoresSafeArea()

        UnlockThemeSheet(themeID: .kurosawa) {}
    }
    .preferredColorScheme(.dark)
}
