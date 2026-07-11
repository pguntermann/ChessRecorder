//
//  SwipeToDeleteRow.swift
//  Chess Recorder
//

import SwiftUI

struct SwipeToDeleteRowCornerRadii: Equatable {
    var topLeading: CGFloat = 0
    var topTrailing: CGFloat = 0
    var bottomTrailing: CGFloat = 0
    var bottomLeading: CGFloat = 0

    static let none = SwipeToDeleteRowCornerRadii()

    static func insetGroupedListRow(index: Int, count: Int, radius: CGFloat = 10) -> SwipeToDeleteRowCornerRadii {
        let isFirst = index == 0
        let isLast = index == count - 1
        return SwipeToDeleteRowCornerRadii(
            topLeading: isFirst ? radius : 0,
            topTrailing: isFirst ? radius : 0,
            bottomTrailing: isLast ? radius : 0,
            bottomLeading: isLast ? radius : 0
        )
    }

    var hasRounding: Bool {
        topLeading > 0 || topTrailing > 0 || bottomTrailing > 0 || bottomLeading > 0
    }
}

struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    var cornerRadii: SwipeToDeleteRowCornerRadii = .none
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0

    private let revealWidth: CGFloat = 88
    private let rowBackgroundColor = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                deleteBackground
            }

            slidingRow
        }
        .clipShape(rowClipShape)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var slidingRow: some View {
        rowClipShape
            .fill(rowBackgroundColor)
            .overlay(alignment: .leading) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .offset(x: offset)
    }

    private var rowClipShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadii.topLeading,
            bottomLeadingRadius: cornerRadii.bottomLeading,
            bottomTrailingRadius: cornerRadii.bottomTrailing,
            topTrailingRadius: cornerRadii.topTrailing,
            style: .continuous
        )
    }

    private var deleteBackground: some View {
        rowClipShape
            .fill(Color(uiColor: .systemRed))
            .mask(alignment: .trailing) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().frame(width: revealWidth)
                }
            }
            .overlay(alignment: .trailing) {
                Button {
                    performDelete(animated: true)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: revealWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if value.translation.width < 0 {
                    offset = max(-revealWidth, value.translation.width)
                } else if offset < 0 {
                    offset = min(0, -revealWidth + value.translation.width)
                }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    snapClosed()
                    return
                }

                let predicted = value.predictedEndTranslation.width
                if value.translation.width < -revealWidth * 1.25 || predicted < -revealWidth * 2.5 {
                    performDelete(animated: true)
                } else if offset < -revealWidth / 2 {
                    snapOpen()
                } else {
                    snapClosed()
                }
            }
    }

    private func snapOpen() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            offset = -revealWidth
        }
    }

    private func snapClosed() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            offset = 0
        }
    }

    private func performDelete(animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                offset = -400
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                onDelete()
                offset = 0
            }
        } else {
            onDelete()
            offset = 0
        }
    }
}
