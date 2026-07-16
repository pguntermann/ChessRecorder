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
                                    isCurrent: index == pathToCurrent.count - 1 && isInBook
                                )
                            }
                        } label: {
                            currentOpeningHeader
                        }
                    } else {
                        currentOpeningHeader
                    }
                } footer: {
                    if pathToCurrent.count > 1 {
                        Text("Expand to see how opening names changed along the played line.")
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let moveSAN = step.moveSAN {
                Text(moveSAN)
                    .font(.body.monospaced().weight(.semibold))
                    .frame(minWidth: 44, alignment: .leading)
            } else {
                Image(systemName: "flag")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.display.eco)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(step.display.name)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isCurrent {
                Text("Now")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let current = isCurrent ? ", current" : ""
        if let moveSAN = step.moveSAN {
            return "\(moveSAN), \(step.display.name), ECO \(step.display.eco)\(current)"
        }
        return "\(step.display.name), ECO \(step.display.eco)\(current)"
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
