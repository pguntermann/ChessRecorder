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
    var compact: Bool = false

    private var reservedHeight: CGFloat {
        compact ? 28 : 40
    }

    private var showsLabel: Bool {
        isLoaded && hasMoves
    }

    var body: some View {
        Group {
            if isVisible {
                Text(display.label)
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.85)
                    .opacity(showsLabel ? 1 : 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: reservedHeight)
                    .accessibilityHidden(!showsLabel)
                    .accessibilityLabel("Opening \(display.name), ECO \(display.eco)")
            }
        }
    }
}
