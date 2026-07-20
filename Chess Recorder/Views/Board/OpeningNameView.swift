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

    /// Below this width, skip the leading balance twin so the opening keeps room to truncate.
    private static let opticalBalanceMinWidth: CGFloat = 360

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
                GeometryReader { geometry in
                    rowContent(availableWidth: geometry.size.width)
                        .frame(width: geometry.size.width, height: reservedHeight)
                }
                .frame(maxWidth: .infinity)
                .frame(height: reservedHeight)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func rowContent(availableWidth: CGFloat) -> some View {
        if showsOpeningLabel {
            let phaseText = phaseBubbleText.map(displayedPhaseText(for:))
            let useOpticalBalance = phaseText != nil
                && availableWidth >= Self.opticalBalanceMinWidth

            HStack(spacing: compact ? 8 : 10) {
                if useOpticalBalance, let phaseText {
                    phaseCapsule(phaseText)
                        .opacity(0)
                        .accessibilityHidden(true)
                }

                openingLabel
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
                    .layoutPriority(0)

                if let phaseText {
                    phaseCapsule(phaseText)
                }
            }
        } else if let phaseBubbleText {
            phaseCapsule(displayedPhaseText(for: phaseBubbleText))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// On narrow chrome, drop the redundant "Endgame · " prefix — the capsule already reads as phase.
    private func displayedPhaseText(for text: String) -> String {
        let prefix = "Endgame · "
        if compact, text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }

    private func phaseCapsule(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .accessibilityLabel("Game phase \(text)")
    }

    @ViewBuilder
    private var openingLabel: some View {
        // Book + name stay one unit, centered in the flexible slot (don’t expand the text
        // alone — that parks the book on the leading edge).
        let content = HStack(spacing: compact ? 4 : 6) {
            Image(systemName: isInBook ? "book.fill" : "book")
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(isInBook ? Color.accentColor : Color.secondary)

            Text(display.label)
                .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
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
