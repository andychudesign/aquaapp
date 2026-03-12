//
//  ContentView.swift
//  aqua
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = WaterStateViewModel()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                hydrationVisual
                Spacer(minLength: 0)
                logWaterButton
                lastLogText
                    .padding(.top, 16)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.95, green: 0.95, blue: 0.95).ignoresSafeArea())
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
                .foregroundStyle(.white)
                .padding(.horizontal, 48)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(Color(red: 0.4, green: 0.55, blue: 0.75))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I drank water")
    }
}

#Preview {
    ContentView()
}
