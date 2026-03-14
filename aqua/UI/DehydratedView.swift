//
//  DehydratedView.swift
//  aqua
//

import SwiftUI

struct DehydratedView: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DehydratedView()
        .background(Color(white: 0.97))
}
