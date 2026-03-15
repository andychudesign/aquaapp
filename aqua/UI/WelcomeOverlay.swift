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

// MARK: - Story progress bar

private struct StoryBar: View {
    var segmentCount: Int
    var currentSegment: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<segmentCount, id: \.self) { i in
                Capsule()
                    .fill(i <= currentSegment ? Color(white: 0.2) : Color(white: 0.8))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Full-screen welcome flow

struct WelcomeView: View {
    var onComplete: () -> Void

    @State private var page = 0
    @State private var waterFilled = false
    @State private var contentVisible = false

    private static let waterBlue = Color(red: 0.2, green: 0.55, blue: 0.9)
    private static let warmBg = Color(red: 0.98, green: 0.96, blue: 0.92)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Self.warmBg.ignoresSafeArea()

                if page == 0 {
                    firstPage(geo: geo)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                } else {
                    secondPage(geo: geo)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Page 1 → 2 (water fill animation)

    private func firstPage(geo: GeometryProxy) -> some View {
        let safeTop = geo.safeAreaInsets.top

        return ZStack(alignment: .bottom) {
            Self.warmBg

            // Water rising from bottom
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
                StoryBar(segmentCount: 2, currentSegment: 0)
                    .padding(.top, safeTop + 10)

                Spacer()

                // "Sip 飲" header — moves up when water fills
                headerText
                    .offset(y: waterFilled ? -geo.size.height * 0.15 : geo.size.height * 0.05)

                if contentVisible {
                    Text("Sipping aqua every 2 hours to stay hydrated!")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .offset(y: -geo.size.height * 0.08)
                        .transition(.opacity)
                }

                Spacer()

                if contentVisible {
                    VStack(spacing: 0) {
                        Text("每兩個鐘,見字飲水")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))

                        Spacer().frame(height: geo.size.height * 0.26)

                        Button {
                            withAnimation(.spring(duration: 0.5)) {
                                page = 1
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
                    .transition(.opacity)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 1.8)) {
                    waterFilled = true
                }
                withAnimation(.easeIn(duration: 0.6).delay(1.4)) {
                    contentVisible = true
                }
            }
        }
    }

    // MARK: Page 3 (widget mockup)

    private func secondPage(geo: GeometryProxy) -> some View {
        let safeTop = geo.safeAreaInsets.top

        return VStack(spacing: 0) {
            StoryBar(segmentCount: 2, currentSegment: 1)
                .padding(.top, safeTop + 10)

            Spacer().frame(height: geo.size.height * 0.06)

            headerText

            Spacer().frame(height: 12)

            Text("Don't be silly, use the widget ;)")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)

            Spacer().frame(height: geo.size.height * 0.04)

            phoneMockup
                .frame(maxHeight: geo.size.height * 0.5)

            Spacer()

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
                .foregroundStyle(Self.waterBlue)
        }
    }

    // MARK: Phone mockup for page 3

    private var phoneMockup: some View {
        ZStack {
            // Phone body
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Color(white: 0.08))

            // Screen
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.55, blue: 0.75),
                            Color(red: 0.25, green: 0.45, blue: 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(4)
                .overlay {
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(.black)
                            .frame(width: 72, height: 22)
                            .padding(.top, 12)

                        Spacer()

                        widgetGalleryCard
                            .padding(.horizontal, 16)

                        Spacer()
                    }
                    .padding(4)
                }
        }
        .frame(width: 210, height: 430)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

    private var widgetGalleryCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Self.waterBlue)
                Text("Sippy")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(white: 0.75))
            }

            Text("Aqua")
                .font(.system(size: 17, weight: .bold))

            Text("Track your hydration.\nTap Drink to log water.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Widget preview tile
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Self.waterBlue)
                .frame(width: 110, height: 110)
                .overlay {
                    VStack(alignment: .leading) {
                        HStack(spacing: 2) {
                            Text("Aqua")
                                .font(.system(size: 9, weight: .medium))
                            Text("水")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "drop.fill")
                                .font(.system(size: 12))
                                .padding(7)
                                .background(Circle().fill(.white.opacity(0.25)))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
        )
    }
}

#Preview {
    WelcomeView { }
}
