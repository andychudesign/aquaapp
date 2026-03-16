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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(white: 0.82))
                Capsule()
                    .fill(Color(white: 0.15))
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(width: 200, height: 3)
    }
}

// MARK: - Full-screen welcome flow

struct WelcomeView: View {
    var onComplete: () -> Void

    @State private var phase = 0
    @State private var progress: Double = 0.03
    @State private var waterFilled = false
    @State private var descriptionsVisible = false

    private static let waterBlue = Color(red: 0.2, green: 0.55, blue: 0.9)
    private static let warmBg = Color(red: 0.98, green: 0.96, blue: 0.92)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Self.warmBg.ignoresSafeArea()

                // Water background layer
                ZStack(alignment: .top) {
                    Self.waterBlue
                    WelcomeWaveShape()
                        .fill(Self.warmBg)
                        .frame(height: 14)
                }
                .frame(height: waterFilled ? geo.size.height * 0.55 : 0)
                .clipped()

                // Foreground content
                VStack(spacing: 0) {
                    ProgressBar(progress: progress)
                        .padding(.top, 78)

                    ZStack {
                        if phase < 2 {
                            waterPhaseContent(geo: geo)
                                .transition(.opacity)
                        } else {
                            widgetPhaseContent(geo: geo)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 1.8)) {
                    phase = 1
                    waterFilled = true
                    progress = 0.5
                }
                withAnimation(.easeIn(duration: 0.6).delay(1.4)) {
                    descriptionsVisible = true
                }
            }
        }
    }

    // MARK: Phase 0 & 1 — Water fill

    private func waterPhaseContent(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()

            headerText
                .offset(y: phase >= 1 ? -geo.size.height * 0.15 : geo.size.height * 0.05)

            if descriptionsVisible {
                VStack(spacing: 64) {
                    Text("Sipping aqua every 2 hours to stay hydrated")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Text("每兩個鐘,見字飲水")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .offset(y: -50)
            }

            Spacer()

            if descriptionsVisible {
                Button {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        waterFilled = false
                        progress = 1.0
                    }
                    withAnimation(.easeInOut(duration: 0.6).delay(0.3)) {
                        phase = 2
                    }
                } label: {
                    Text("Next")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.white.opacity(0.25)))
                }

                Spacer().frame(height: 50)
            }
        }
    }

    // MARK: Phase 2 — Widget

    private func widgetPhaseContent(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: geo.size.height * 0.06)

            headerText

            Spacer().frame(height: 12)

            Text("Don't be silly, use the widget ;)")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)

            Spacer().frame(height: 20)

            Image("WidgetScreenshot")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            Button(action: onComplete) {
                Text("Get Started")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Self.waterBlue))
            }

            Spacer().frame(height: 50)
        }
    }

    // MARK: Shared header

    private var headerText: some View {
        HStack(spacing: 6) {
            Text("Sip")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(white: 0.1))
            Text("飲")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color(red: 0, green: 0.208, blue: 0.925))
        }
    }
}

#Preview {
    WelcomeView { }
}
