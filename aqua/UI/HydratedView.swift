//
//  HydratedView.swift
//  aqua
//

import SwiftUI

struct HydratedView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aqua")
                .font(.custom("Inter-Medium", size: 22))
                .foregroundStyle(Color(white: 0.1))
            Text("飲")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.2, green: 0.55, blue: 0.9).ignoresSafeArea())
    }
}

#Preview {
    HydratedView()
}
