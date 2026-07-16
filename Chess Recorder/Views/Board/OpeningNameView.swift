//
//  OpeningNameView.swift
//  Chess Recorder
//

import SwiftUI

struct OpeningNameView: View {
    let display: OpeningDisplay
    let isVisible: Bool
    let isLoaded: Bool
    let isInBook: Bool
    var compact: Bool = false
    var onTap: (() -> Void)?

    private var reservedHeight: CGFloat {
        compact ? 28 : 40
    }

    private var showsLabel: Bool {
        isLoaded
    }

    private var isInteractive: Bool {
        showsLabel && onTap != nil
    }

    var body: some View {
        Group {
            if isVisible {
                Group {
                    if isInteractive {
                        Button(action: { onTap?() }) {
                            labelContent
                        }
                        .buttonStyle(.plain)
                    } else {
                        labelContent
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: reservedHeight)
                .opacity(showsLabel ? 1 : 0)
                .accessibilityHidden(!showsLabel)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(isInteractive ? .isButton : [])
                .accessibilityLabel(accessibilityLabelText)
                .accessibilityHint(isInteractive ? "Shows opening book lines from this position" : "")
            }
        }
    }

    private var labelContent: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: isInBook ? "book.fill" : "book")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(isInBook ? Color.accentColor : Color.secondary)

            Text(display.label)
                .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 1 : 2)
                .minimumScaleFactor(0.85)
        }
    }

    private var accessibilityLabelText: String {
        let bookState = isInBook ? "in book" : "left book"
        return "Opening \(display.name), ECO \(display.eco), \(bookState)"
    }
}
