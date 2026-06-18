//
//  WelcomeOverlay.swift
//  aqua
//

import SwiftUI

// MARK: - Wave shape for welcome water edge

private struct WelcomeWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return path }

        path.move(to: .zero)
        path.addLine(to: CGPoint(x: w, y: 0))

        for x in stride(from: w, through: 0, by: -1) {
            let t = x / w
            let y = h * (0.35 + 0.45 * sin(t * .pi))
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Continuous progress bar

private struct ProgressBar: View {
    var progress: Double
    var onWater: Bool
    var theme: AppTheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Dehydrated track/fill are theme-driven so the bar stays
                // legible in Dark Mode (the dark palette's `headerPrimary` is
                // light, inverting the near-black fill that would otherwise
                // vanish on the dark backdrop). The light-mode look is
                // effectively unchanged (near-black fill on a faint track).
                Capsule()
                    .fill(onWater ? Color.white.opacity(0.35) : theme.headerPrimary.opacity(0.18))
                Capsule()
                    .fill(onWater ? Color.white : theme.headerPrimary)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(width: 200, height: 3)
    }
}

// MARK: - Full-screen welcome flow

struct WelcomeView: View {
    let theme: AppTheme
    var onComplete: () -> Void

    @State private var phase = 0
    @State private var progress: Double = 0.03
    @State private var waterFraction: CGFloat = 0
    @State private var descriptionsVisible = false

    private var onWater: Bool { phase >= 2 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                theme.dehydratedBackground.ignoresSafeArea()

                ZStack(alignment: .top) {
                    theme.waterColor
                    if waterFraction < 1 {
                        WelcomeWaveShape()
                            .fill(theme.dehydratedBackground)
                            .frame(height: 14)
                    }
                }
                .frame(height: geo.size.height * waterFraction)
                .clipped()

                // Foreground content
                VStack(spacing: 0) {
                    ProgressBar(progress: progress, onWater: onWater, theme: theme)
                        .padding(.top, 78)
                        .animation(.easeInOut(duration: 0.8), value: onWater)

                    // Header at fixed position from top
                    Spacer().frame(height: geo.size.height * 0.06)

                    headerText(onWater: onWater)
                        .offset(y: phase >= 1 ? 0 : geo.size.height * 0.3)
                        .animation(.easeInOut(duration: 0.8), value: onWater)

                    // Middle content — both always in layout, toggled with opacity
                    ZStack {
                        // Phase 0 & 1: descriptions
                        VStack(spacing: 16) {
                            Text("Sipping aqua every 2 hours to stay hydrated")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Text("每兩個鐘,見字飲水")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.5))
                        }
                        .padding(.top, 20)
                        .opacity(descriptionsVisible && phase < 2 ? 1 : 0)

                        // Phase 2: widget content
                        VStack(spacing: 0) {
                            Spacer()

                            VStack(spacing: 8) {
                                Text("Use the widget, so you won't get dried out ;)")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))

                                Text("用widget,隨時睇住")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                            Spacer()

                            Image("WidgetScreenshot")
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                                .padding(.horizontal, 24)
                                .frame(maxHeight: geo.size.height * 0.45)
                                .offset(y: -20)
                        }
                        .opacity(phase >= 2 ? 1 : 0)
                    }
                    .frame(maxHeight: .infinity)

                    // Persistent button
                    Button {
                        if phase < 2 {
                            withAnimation(.easeInOut(duration: 1.2)) {
                                waterFraction = 1.0
                                progress = 1.0
                                phase = 2
                            }
                        } else {
                            onComplete()
                        }
                    } label: {
                        Text(onWater ? "Start Sipping" : "Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 14)
                            .background(
                                Capsule().fill(onWater ? theme.buttonBackgroundOnWater : theme.waterColor)
                            )
                            .animation(.easeInOut(duration: 0.8), value: onWater)
                    }
                    .opacity(descriptionsVisible ? 1 : 0)

                    Spacer().frame(height: 50)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 1.8)) {
                    phase = 1
                    waterFraction = 0.13
                    progress = 0.5
                }
                withAnimation(.easeIn(duration: 0.6).delay(1.4)) {
                    descriptionsVisible = true
                }
            }
        }
    }

    // MARK: Shared header

    private func headerText(onWater: Bool) -> some View {
        HStack(spacing: 6) {
            Text("Sip")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(onWater ? theme.headerPrimaryOnWater : theme.headerPrimary)
            Text("飲")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(theme.welcomeAccent)
        }
    }
}

#Preview {
    WelcomeView(theme: .default) { }
}
