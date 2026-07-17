//
//  OpeningBookSheet.swift
//  Chess Recorder
//

import SwiftUI

struct OpeningBookSheet: View {
    @Environment(\.dismiss) private var dismiss

    let rootDisplay: OpeningDisplay
    let rootFEN: String?
    let isInBook: Bool
    let pathToCurrent: [OpeningBookPathStep]
    let miniBoardSide: CGFloat
    let boardOrientation: BoardOrientation
    let moveHighlightColor: Color
    let openingService: OpeningService

    @State private var isPathExpanded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if pathToCurrent.count > 1 {
                        DisclosureGroup(isExpanded: $isPathExpanded) {
                            ForEach(Array(pathToCurrent.enumerated()), id: \.element.id) { index, step in
                                OpeningBookPathStepRow(
                                    step: step,
                                    isCurrent: index == pathToCurrent.count - 1 && isInBook,
                                    miniBoardSide: miniBoardSide,
                                    boardOrientation: boardOrientation,
                                    moveHighlightColor: moveHighlightColor,
                                    openingService: openingService
                                )
                            }
                        } label: {
                            currentOpeningHeader
                        }
                    } else {
                        currentOpeningHeader
                    }
                } header: {
                    Text("Lines until here")
                } footer: {
                    if pathToCurrent.count > 1 {
                        Text("Open a played opening to browse book continuations from that position. Gaps mark where the game left and later rejoined the book.")
                    }
                }

                if isInBook, let rootFEN {
                    Section {
                        OpeningBookTreeNodeView(
                            fen: rootFEN,
                            display: rootDisplay,
                            moveSAN: nil,
                            moveFrom: nil,
                            moveTo: nil,
                            depth: 0,
                            initiallyExpanded: true,
                            miniBoardSide: miniBoardSide,
                            boardOrientation: boardOrientation,
                            moveHighlightColor: moveHighlightColor,
                            openingService: openingService
                        )
                    } header: {
                        Text("Lines from here")
                    } footer: {
                        Text("Expand a move to drill into further book continuations. Up to \(OpeningService.maxContinuationsPerNode) moves are shown per position.")
                    }
                } else {
                    Section {
                        Text("No book continuations from the current position. Navigate back into a known opening to browse lines.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Opening Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var currentOpeningHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rootDisplay.label)
                .font(.headline)
            Text(isInBook ? "Still in the opening book" : "Left the opening book")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct OpeningBookPathStepRow: View {
    let step: OpeningBookPathStep
    let isCurrent: Bool
    let miniBoardSide: CGFloat
    let boardOrientation: BoardOrientation
    let moveHighlightColor: Color
    let openingService: OpeningService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let gap = step.gapBefore {
                OpeningBookGapRow(gap: gap)
            }

            NavigationLink {
                OpeningBookPositionLinesView(
                    display: step.display,
                    fen: step.fen,
                    miniBoardSide: miniBoardSide,
                    boardOrientation: boardOrientation,
                    moveHighlightColor: moveHighlightColor,
                    openingService: openingService
                )
            } label: {
                pathStepLabel
            }
        }
        .padding(.vertical, 2)
    }

    private var pathStepLabel: some View {
        HStack(alignment: .center, spacing: 8) {
            moveColumn

            VStack(alignment: .leading, spacing: 2) {
                Text(step.display.eco)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(step.display.name)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if isCurrent {
                    Text("Now")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 4)

            MiniChessBoardView(
                fen: step.fen,
                side: miniBoardSide,
                orientation: boardOrientation,
                highlightedFrom: step.moveFrom,
                highlightedTo: step.moveTo,
                highlightColor: moveHighlightColor
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var moveColumn: some View {
        if let moveSAN = step.moveSAN {
            VStack(alignment: .leading, spacing: 1) {
                if let moveNumberLabel = step.moveNumberLabel {
                    Text(moveNumberLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(moveSAN)
                    .font(.body.monospaced().weight(.semibold))
            }
            .frame(minWidth: 52, alignment: .leading)
        } else {
            Image(systemName: "flag")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .leading)
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let gap = step.gapBefore {
            parts.append(gap.summary)
        }
        if let moveNumberLabel = step.moveNumberLabel, let moveSAN = step.moveSAN {
            parts.append("\(moveNumberLabel) \(moveSAN)")
        } else if let moveSAN = step.moveSAN {
            parts.append(moveSAN)
        }
        parts.append("\(step.display.name), ECO \(step.display.eco)")
        if isCurrent {
            parts.append("current")
        }
        parts.append("browse book lines")
        return parts.joined(separator: ", ")
    }
}

/// Dedicated screen for browsing book continuations from a path position.
/// Keeps nested disclosure trees out of the path list (avoids List outline collapse).
private struct OpeningBookPositionLinesView: View {
    let display: OpeningDisplay
    let fen: String
    let miniBoardSide: CGFloat
    let boardOrientation: BoardOrientation
    let moveHighlightColor: Color
    let openingService: OpeningService

    var body: some View {
        List {
            Section {
                OpeningBookTreeNodeView(
                    fen: fen,
                    display: display,
                    moveSAN: nil,
                    moveFrom: nil,
                    moveTo: nil,
                    depth: 0,
                    initiallyExpanded: true,
                    miniBoardSide: miniBoardSide,
                    boardOrientation: boardOrientation,
                    moveHighlightColor: moveHighlightColor,
                    openingService: openingService
                )
            } header: {
                Text("Book lines")
            } footer: {
                Text("Expand a move to drill into further book continuations from this played position.")
            }
        }
        .navigationTitle(display.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OpeningBookGapRow: View {
    let gap: OpeningBookOutOfBookGap

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.caption.weight(.semibold))
            Text(gap.summary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gap.summary)
    }
}

private struct OpeningBookTreeNodeView: View {
    let fen: String
    let display: OpeningDisplay
    let moveSAN: String?
    let moveFrom: ChessPosition?
    let moveTo: ChessPosition?
    let depth: Int
    var initiallyExpanded: Bool = false
    let miniBoardSide: CGFloat
    let boardOrientation: BoardOrientation
    let moveHighlightColor: Color
    let openingService: OpeningService

    @State private var isExpanded: Bool
    @State private var children: [OpeningBookContinuation]?
    @State private var didLoadChildren = false

    init(
        fen: String,
        display: OpeningDisplay,
        moveSAN: String?,
        moveFrom: ChessPosition?,
        moveTo: ChessPosition?,
        depth: Int,
        initiallyExpanded: Bool = false,
        miniBoardSide: CGFloat,
        boardOrientation: BoardOrientation,
        moveHighlightColor: Color,
        openingService: OpeningService
    ) {
        self.fen = fen
        self.display = display
        self.moveSAN = moveSAN
        self.moveFrom = moveFrom
        self.moveTo = moveTo
        self.depth = depth
        self.initiallyExpanded = initiallyExpanded
        self.miniBoardSide = miniBoardSide
        self.boardOrientation = boardOrientation
        self.moveHighlightColor = moveHighlightColor
        self.openingService = openingService
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var canExpandFurther: Bool {
        depth < OpeningService.maxTreeDepth
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if !canExpandFurther {
                Text("Maximum depth reached")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let children {
                if children.isEmpty {
                    Text("No further book moves")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(children) { child in
                        OpeningBookTreeNodeView(
                            fen: child.fenAfter,
                            display: child.display,
                            moveSAN: child.san,
                            moveFrom: child.from,
                            moveTo: child.to,
                            depth: depth + 1,
                            miniBoardSide: miniBoardSide,
                            boardOrientation: boardOrientation,
                            moveHighlightColor: moveHighlightColor,
                            openingService: openingService
                        )
                    }
                }
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                if let moveSAN {
                    Text(moveSAN)
                        .font(.body.monospaced().weight(.semibold))
                        .frame(minWidth: 44, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(display.eco)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(display.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if moveSAN != nil {
                    MiniChessBoardView(
                        fen: fen,
                        side: miniBoardSide,
                        orientation: boardOrientation,
                        highlightedFrom: moveFrom,
                        highlightedTo: moveTo,
                        highlightColor: moveHighlightColor
                    )
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
        .onChange(of: isExpanded) { _, expanded in
            loadChildrenIfNeeded(expanded: expanded)
        }
        .onAppear {
            loadChildrenIfNeeded(expanded: isExpanded)
        }
    }

    private var accessibilityLabel: String {
        if let moveSAN {
            return "\(moveSAN), \(display.name), ECO \(display.eco)"
        }
        return "\(display.name), ECO \(display.eco)"
    }

    private func loadChildrenIfNeeded(expanded: Bool) {
        guard expanded, canExpandFurther, !didLoadChildren else { return }
        didLoadChildren = true
        children = openingService.continuations(from: fen)
    }
}
