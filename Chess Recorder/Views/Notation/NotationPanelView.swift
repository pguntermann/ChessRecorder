//
//  NotationPanelView.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import SwiftUI

private struct ShareablePGNExport: Identifiable {
    let id = UUID()
    let url: URL
}

struct NotationPanelView: View {
    let game: ChessGame
    @Bindable var pgnArchive: PGNArchive
    let defaultMetadata: PGNMetadata
    var hidePGNHeaderTags: Bool = true
    var includeMoveAssessmentSymbolsInExport: Bool = false
    var showAccuracySummary: Bool = true
    var activeAssessment: MoveAssessmentProgress?
    var showMoveAssessments: Bool = false
    var assessmentColors: MoveAssessmentColors = .defaults
    var assessmentColorsCacheKey: String = ""
    let engineAnalysisVisible: Bool
    let engineAnalysisUseAlgebraicNotation: Bool
    @Bindable var engineAnalysis: EngineAnalysisService
    var onClearPGN: (() -> Void)?
    var onActivateGame: ((UUID) -> Void)?
    var onDeleteGame: ((UUID) -> Void)?

    @State private var exportItem: ShareablePGNExport?
    @State private var cachedFullPGN = ""
    @State private var cachedRows: [UUID: GameRowPresentation] = [:]
    @State private var presentationCacheKey = ""

    private var hasAnyPGNContent: Bool {
        !pgnArchive.games.isEmpty || !game.moves.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engineAnalysisVisible {
                EngineAnalysisSectionView(
                    game: game,
                    useAlgebraicNotation: engineAnalysisUseAlgebraicNotation,
                    analysisService: engineAnalysis
                )

                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PGN Notation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        copyPGNToClipboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline)
                            .imageScale(.medium)
                    }
                    .disabled(!hasAnyPGNContent)

                    Button {
                        sharePGN()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .imageScale(.medium)
                    }
                    .disabled(!hasAnyPGNContent)

                    Button {
                        onClearPGN?()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.subheadline)
                            .imageScale(.medium)
                    }
                    .disabled(!hasAnyPGNContent)
                }

                if hasAnyPGNContent {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(pgnArchive.games) { recordedGame in
                            SwipeToDeleteRow {
                                onDeleteGame?(recordedGame.id)
                            } content: {
                                GamePGNRowView(
                                    recordedGame: recordedGame,
                                    presentation: cachedRows[recordedGame.id],
                                    hideHeaderTags: hidePGNHeaderTags,
                                    isActive: recordedGame.id == pgnArchive.activeGameID,
                                    showMoveHighlight: recordedGame.id == pgnArchive.activeGameID,
                                    assessingMoveIndex: activeAssessment?.gameID == recordedGame.id
                                        ? activeAssessment?.moveIndex
                                        : nil,
                                    showMoveAssessments: showMoveAssessments,
                                    showAccuracySummary: showAccuracySummary,
                                    assessmentColors: assessmentColors,
                                    activePlyIndex: game.activePlyIndex,
                                    isAtLatestMove: game.isAtLatestMove
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onActivateGame?(recordedGame.id)
                                }
                            }
                        }

                        if pgnArchive.games.isEmpty, !game.moves.isEmpty {
                            GamePGNRowView(
                                recordedGame: RecordedGame(
                                    moves: game.moves,
                                    round: 1,
                                    result: game.gameResult,
                                    metadata: defaultMetadata
                                ),
                                presentation: fallbackActiveRowPresentation(),
                                hideHeaderTags: hidePGNHeaderTags,
                                isActive: true,
                                showMoveHighlight: true,
                                assessingMoveIndex: nil,
                                showMoveAssessments: showMoveAssessments,
                                showAccuracySummary: showAccuracySummary,
                                assessmentColors: assessmentColors,
                                activePlyIndex: game.activePlyIndex,
                                isAtLatestMove: game.isAtLatestMove
                            )
                        }
                    }
                } else {
                    Text("No games yet")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
        }
        .onAppear {
            refreshPresentationCacheIfNeeded()
        }
        .onChange(of: presentationInvalidationKey) { _, _ in
            refreshPresentationCacheIfNeeded()
        }
        #if os(iOS)
        .sheet(item: $exportItem, onDismiss: cleanupExport) { item in
            ShareSheet(items: [item.url])
        }
        #endif
    }

    private var presentationInvalidationKey: String {
        PGNPresentationBuilder.cacheKey(
            games: pgnArchive.games,
            activeGameID: pgnArchive.activeGameID,
            activePlyIndex: game.activePlyIndex,
            isAtLatestMove: game.isAtLatestMove,
            hidePGNHeaderTags: hidePGNHeaderTags,
            activeAssessment: activeAssessment,
            showMoveAssessments: showMoveAssessments,
            assessmentColorsCacheKey: assessmentColorsCacheKey
        )
    }

    private func refreshPresentationCacheIfNeeded() {
        let key = presentationInvalidationKey
        guard key != presentationCacheKey else { return }
        presentationCacheKey = key
        let builtRows = PGNPresentationBuilder.build(
            games: pgnArchive.games,
            activeGameID: pgnArchive.activeGameID,
            activePlyIndex: game.activePlyIndex,
            isAtLatestMove: game.isAtLatestMove,
            hidePGNHeaderTags: hidePGNHeaderTags,
            activeAssessment: activeAssessment,
            showMoveAssessments: showMoveAssessments,
            assessmentColors: assessmentColors
        )
        cachedRows = builtRows
    }

    private func fallbackActiveRowPresentation() -> GameRowPresentation {
        return PGNPresentationBuilder.rowPresentation(
            for: RecordedGame(
                moves: game.moves,
                round: 1,
                result: game.gameResult,
                metadata: defaultMetadata
            ),
            eco: nil,
            activePlyIndex: game.activePlyIndex,
            isAtLatestMove: game.isAtLatestMove,
            showMoveHighlight: true
        )
    }

    private func copyPGNToClipboard() {
        cachedFullPGN = PGNExportService.fullPGN(
            for: pgnArchive,
            includeAssessmentSymbols: includeMoveAssessmentSymbolsInExport
        )
        #if os(iOS)
        UIPasteboard.general.string = cachedFullPGN
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cachedFullPGN, forType: .string)
        #endif
    }

    private func sharePGN() {
        cachedFullPGN = PGNExportService.fullPGN(
            for: pgnArchive,
            includeAssessmentSymbols: includeMoveAssessmentSymbolsInExport
        )
        guard !cachedFullPGN.isEmpty else { return }
        do {
            let url = try PGNExportService.writeTemporaryFile(content: cachedFullPGN)
            exportItem = ShareablePGNExport(url: url)
        } catch {
            print("PGN export failed: \(error.localizedDescription)")
        }
    }

    private func cleanupExport() {
        if let exportItem {
            try? FileManager.default.removeItem(at: exportItem.url)
        }
        exportItem = nil
    }
}

private struct GamePGNRowView: View {
    let recordedGame: RecordedGame
    let presentation: GameRowPresentation?
    var hideHeaderTags: Bool = true
    let isActive: Bool
    let showMoveHighlight: Bool
    var assessingMoveIndex: Int? = nil
    var showMoveAssessments: Bool = false
    var showAccuracySummary: Bool = true
    var assessmentColors: MoveAssessmentColors = .defaults
    var activePlyIndex: Int = 0
    var isAtLatestMove: Bool = true

    @State private var showingAccuracySummary = false

    private var isAssessingMoves: Bool {
        assessingMoveIndex != nil
    }

    private var usesAssessedTokenLayout: Bool {
        showMoveAssessments || isAssessingMoves
    }

    private var accuracySummary: GameAccuracySummary? {
        guard showMoveAssessments, showAccuracySummary else { return nil }
        let summary = GameAccuracySummary(moves: recordedGame.moves)
        return summary.hasContent ? summary : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(recordedGame.summaryTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive ? .primary : .secondary)

                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                if recordedGame.isReviewOnly {
                    Text("Review")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                if isAssessingMoves {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Assessing move quality")
                }

                Spacer()
            }

            if let accuracySummary {
                Button {
                    showingAccuracySummary = true
                } label: {
                    HStack(alignment: .center, spacing: 6) {
                        Spacer(minLength: 0)
                        GameAccuracyCompactTable(summary: accuracySummary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accuracyAccessibilityLabel(accuracySummary))
                .accessibilityHint("Shows accuracy details")
            }

            if !hideHeaderTags {
                Text(PGNFormatter.headers(
                    round: recordedGame.round,
                    result: recordedGame.result,
                    metadata: recordedGame.metadata,
                    date: recordedGame.date,
                    eco: presentation?.eco
                ))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if recordedGame.moves.isEmpty {
                Text("No moves yet")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if usesAssessedTokenLayout {
                PGNAssessedMovetextView(
                    moves: recordedGame.moves,
                    result: recordedGame.result,
                    showMoveHighlight: showMoveHighlight,
                    activePlyIndex: activePlyIndex,
                    isAtLatestMove: isAtLatestMove,
                    assessingMoveIndex: assessingMoveIndex,
                    showMoveAssessments: showMoveAssessments,
                    assessmentColors: assessmentColors
                )
            } else if showMoveHighlight, let presentation {
                Text(presentation.highlightedMovetext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(presentation?.plainMovetext ?? PGNFormatter.movetext(from: recordedGame.moves, result: recordedGame.result))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            Rectangle()
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .sheet(isPresented: $showingAccuracySummary) {
            GameAccuracySummarySheet(
                summary: GameAccuracySummary(moves: recordedGame.moves),
                roundTitle: "Round \(recordedGame.round)",
                assessmentColors: assessmentColors
            )
        }
    }

    private func accuracyAccessibilityLabel(_ summary: GameAccuracySummary) -> String {
        var parts: [String] = []
        if summary.white.hasContent {
            parts.append("White \(summary.white.compactLabel)")
        }
        if summary.black.hasContent {
            parts.append("Black \(summary.black.compactLabel)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct GameAccuracyCompactTable: View {
    @Environment(\.colorScheme) private var colorScheme

    let summary: GameAccuracySummary

    private var columns: [GameAccuracySummary.CompactTableColumn] {
        summary.compactTableColumns
    }

    private var rows: [(side: GameAccuracySummary.Side, stats: GameAccuracySummary.SideStats)] {
        var result: [(GameAccuracySummary.Side, GameAccuracySummary.SideStats)] = []
        if summary.white.hasContent {
            result.append((.white, summary.white))
        }
        if summary.black.hasContent {
            result.append((.black, summary.black))
        }
        return result
    }

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                Color.clear
                    .frame(width: 12, height: 12)
                    .gridColumnAlignment(.center)
                ForEach(columns, id: \.title) { column in
                    Text(column.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 28)
                        .gridColumnAlignment(.center)
                }
            }

            ForEach(rows, id: \.side) { row in
                GridRow {
                    sideSwatch(row.side)
                        .gridColumnAlignment(.center)
                    ForEach(columns, id: \.title) { column in
                        Text(column.value(for: row.stats))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28)
                            .gridColumnAlignment(.center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func sideSwatch(_ side: GameAccuracySummary.Side) -> some View {
        // White fills look larger (irradiation); inset the fill so both share the same outer edge.
        ZStack {
            Circle()
                .fill(sideFill(side))
                .padding(side == .white ? 0.75 : 0)
            Circle()
                .strokeBorder(Color.primary.opacity(0.35), lineWidth: 0.5)
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }

    private func sideFill(_ side: GameAccuracySummary.Side) -> Color {
        switch side {
        case .white:
            return colorScheme == .dark ? Color(white: 0.92) : Color(white: 0.95)
        case .black:
            return colorScheme == .dark ? Color(white: 0.06) : Color.black
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if summary.white.hasContent {
            parts.append("White \(summary.white.compactLabel)")
        }
        if summary.black.hasContent {
            parts.append("Black \(summary.black.compactLabel)")
        }
        return parts.joined(separator: ", ")
    }
}

private struct PGNAssessedMovetextView: View {
    let moves: [ChessMove]
    let result: PGNResult
    let showMoveHighlight: Bool
    let activePlyIndex: Int
    let isAtLatestMove: Bool
    let assessingMoveIndex: Int?
    let showMoveAssessments: Bool
    let assessmentColors: MoveAssessmentColors

    var body: some View {
        PGNWrappingLayout(spacing: 4) {
            ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                if index % 2 == 0 {
                    Text("\(index / 2 + 1).")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(tokenColor(for: index, isMoveNumber: true))
                }

                moveToken(move: move, index: index)
            }

            if result != .ongoing {
                Text(result.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moveToken(move: ChessMove, index: Int) -> some View {
        let activeMoveIndex = showMoveHighlight && activePlyIndex > 0 ? activePlyIndex - 1 : nil
        let isActiveMove = index == activeMoveIndex
        let isDimmed = showMoveHighlight && !isAtLatestMove && index >= activePlyIndex
        let quality = showMoveAssessments ? move.quality : nil
        let displayText = move.algebraicNotation + (quality?.annotationSymbol ?? "")
        let showsDecoration = quality?.showsAssessmentDecoration == true
        let isAssessing = index == assessingMoveIndex

        return Text(displayText)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(isActiveMove ? .semibold : .regular)
            .foregroundStyle(tokenColor(for: index, isMoveNumber: false))
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background {
                if isActiveMove {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.25))
                }
            }
            .overlay(alignment: .bottom) {
                if isAssessing {
                    DottedUnderline()
                        .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 1.5]))
                        .frame(height: 1.5)
                        .padding(.horizontal, 1)
                        .offset(y: 2)
                } else if showsDecoration, let quality {
                    Capsule()
                        .fill(
                            assessmentColors.underlineColor(for: quality)
                                .opacity(isDimmed ? 0.45 : 1)
                        )
                        .frame(height: 2.5)
                        .padding(.horizontal, 1)
                        .offset(y: 2)
                }
            }
            .padding(.bottom, (isAssessing || showsDecoration) ? 3 : 0)
    }

    private func tokenColor(for index: Int, isMoveNumber: Bool) -> Color {
        if showMoveHighlight && !isAtLatestMove && index >= activePlyIndex {
            return .secondary.opacity(0.45)
        }
        return isMoveNumber ? .secondary : .primary
    }
}

private struct DottedUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

/// Simple left-to-right wrapping layout for PGN move tokens.
private struct PGNWrappingLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            width = max(width, x + size.width)
            x += size.width + spacing
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
