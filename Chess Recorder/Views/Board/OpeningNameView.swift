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
    /// Middlegame / endgame / opening capsule beside the opening name.
    var phaseBubbleText: String? = nil
    var compact: Bool = false
    var onTap: (() -> Void)?

    private var reservedHeight: CGFloat {
        compact ? 28 : 40
    }

    private var showsOpeningLabel: Bool {
        isVisible && isLoaded
    }

    private var showsPhaseBubble: Bool {
        phaseBubbleText != nil
    }

    private var showsRow: Bool {
        showsOpeningLabel || showsPhaseBubble
    }

    private var isInteractive: Bool {
        showsOpeningLabel && onTap != nil
    }

    var body: some View {
        Group {
            if showsRow {
                rowContent
                    .frame(maxWidth: .infinity)
                    .frame(height: reservedHeight)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        if showsOpeningLabel {
            // Invisible leading twin keeps the opening optically centered when a phase capsule is present.
            HStack(spacing: compact ? 8 : 10) {
                if let phaseBubbleText {
                    phaseCapsule(phaseBubbleText)
                        .opacity(0)
                        .accessibilityHidden(true)
                }

                openingLabel
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .layoutPriority(0)

                if let phaseBubbleText {
                    phaseCapsule(phaseBubbleText)
                        .layoutPriority(1)
                }
            }
        } else if let phaseBubbleText {
            phaseCapsule(phaseBubbleText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func phaseCapsule(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Game phase \(text)")
    }

    @ViewBuilder
    private var openingLabel: some View {
        let content = HStack(spacing: compact ? 4 : 6) {
            Image(systemName: isInBook ? "book.fill" : "book")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(isInBook ? Color.accentColor : Color.secondary)

            Text(display.label)
                .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(isInteractive ? "Shows opening book lines from this position" : "")

        if isInteractive {
            Button(action: { onTap?() }) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private var accessibilityLabelText: String {
        let bookState = isInBook ? "in book" : "left book"
        return "Opening \(display.name), ECO \(display.eco), \(bookState)"
    }
}
