//
//  ContentView.swift
//  aqua
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = WaterStateViewModel()

    private static let waterBlue = Color(red: 0.2, green: 0.55, blue: 0.9)
    private static let dehydratedGrey = Color(red: 0.95, green: 0.95, blue: 0.95)

    var body: some View {
        GeometryReader { geometry in
            let waterHeight = geometry.size.height * viewModel.hydrationLevel
            let statusBarBottom = geometry.safeAreaInsets.top
            let waterCoversStatusBar = waterHeight > (geometry.size.height - statusBarBottom)

            ZStack(alignment: .bottom) {
                // Full-screen layer: extends under status bar so water can cover it
                ZStack(alignment: .bottom) {
                    Self.dehydratedGrey
                    waterFillView(screenHeight: geometry.size.height)
                }
                .ignoresSafeArea()

                // Content: sticky header + body, padded below status bar
                VStack(spacing: 0) {
                    stickyHeader
                    hydrationVisual
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    logWaterButton
                    lastLogText
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, geometry.safeAreaInsets.top + 40)
            }
            .preferredColorScheme(waterCoversStatusBar ? .dark : .light)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var stickyHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.hydrationLevel > 0 ? "Aqua" : "Sip")
                .font(.custom("Inter-Medium", size: 22))
                .foregroundStyle(Color(white: 0.1))
            Text("飲")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func waterFillView(screenHeight: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 0)
            Self.waterBlue
                .frame(height: screenHeight * viewModel.hydrationLevel)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .animation(.easeInOut(duration: 0.25), value: viewModel.hydrationLevel)
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

    private var lastLogText: some View {
        Group {
            if let date = SharedStorage.lastWaterLogTime {
                Text("Last drank: \(Self.formatLastDrank(date))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Last drank: —")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
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
            viewModel.logWater()
        } label: {
            Text("Drink")
                .font(.custom("Inter-Medium", size: 22))
                .foregroundStyle(viewModel.isFullyDehydrated ? Self.waterBlue : Color.primary)
                .padding(.horizontal, 48)
                .padding(.vertical, 16)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("I drank water")
    }
}

#Preview {
    ContentView()
}
