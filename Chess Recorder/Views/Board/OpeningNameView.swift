//
//  OpeningNameView.swift
//  Chess Recorder
//

import SwiftUI

struct OpeningNameView: View {
    let display: OpeningDisplay
    let isVisible: Bool
    let isLoaded: Bool
    let hasMoves: Bool

    private static let reservedHeight: CGFloat = 40

    private var showsLabel: Bool {
        isLoaded && hasMoves
    }

    var body: some View {
        Group {
            if isVisible {
                Text(display.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .opacity(showsLabel ? 1 : 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.reservedHeight)
                    .accessibilityHidden(!showsLabel)
                    .accessibilityLabel("Opening \(display.name), ECO \(display.eco)")
            }
        }
    }
}
