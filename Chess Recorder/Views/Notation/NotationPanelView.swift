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
    /// Games with unassessed moves and/or queued assessment work.
    var incompleteAssessmentGameIDs: Set<UUID> = []
    var showMoveAssessments: Bool = false
    var assessmentColors: MoveAssessmentColors = .defaults
    var assessmentColorsCacheKey: String = ""
    var boardAppearance: MiniChessBoardAppearance = .default
    let engineAnalysisVisible: Bool
    let engineAnalysisUseAlgebraicNotation: Bool
    @Bindable var engineAnalysis: EngineAnalysisService
    var onClearPGN: (() -> Void)?
    var onImportPGN: ((String) throws -> Int)?
    var onActivateGame: ((UUID) -> Void)?
    var onDeleteGame: ((UUID) -> Void)?
    var onGameTagsEdited: (() -> Void)?

    @State private var exportItem: ShareablePGNExport?
    @State private var gamePendingTagEdit: RecordedGame?
    @State private var showingPGNImport = false
    @State private var cachedFullPGN = ""
    @State private var cachedRows: [UUID: GameRowPresentation] = [:]
    @State private var presentationCacheKey = ""
    @State private var cachedContentRevision: UInt64 = 0
    @State private var cachedActiveGameID: UUID?
    @State private var cachedHighlightKey = ""

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
                    Text("Notation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if onImportPGN != nil {
                        Button {
                            showingPGNImport = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.subheadline)
                                .imageScale(.medium)
                        }
                        .accessibilityLabel("Import PGN")
                        .padding(.leading, 4)
                    }

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
                    // LazyVStack keeps off-screen archived games from paying layout cost.
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(pgnArchive.games) { recordedGame in
                            let isActiveGame = recordedGame.id == pgnArchive.activeGameID
                            SwipeToDeleteRow {
                                onDeleteGame?(recordedGame.id)
                            } content: {
                                GamePGNRowView(
                                    recordedGame: recordedGame,
                                    presentation: cachedRows[recordedGame.id],
                                    hideHeaderTags: hidePGNHeaderTags,
                                    isActive: isActiveGame,
                                    showMoveHighlight: isActiveGame,
                                    assessingMoveIndex: activeAssessment?.gameID == recordedGame.id
                                        ? activeAssessment?.moveIndex
                                        : nil,
                                    hasIncompleteAssessment: showMoveAssessments
                                        && incompleteAssessmentGameIDs.contains(recordedGame.id),
                                    showMoveAssessments: showMoveAssessments,
                                    showAccuracySummary: showAccuracySummary,
                                    assessmentColors: assessmentColors,
                                    boardAppearance: boardAppearance,
                                    // Freeze ply props on inactive rows so they don't redraw on navigation.
                                    activePlyIndex: isActiveGame ? game.activePlyIndex : recordedGame.moves.count,
                                    isAtLatestMove: isActiveGame ? game.isAtLatestMove : true,
                                    contentRevision: pgnArchive.contentRevision(for: recordedGame.id),
                                    onActivate: { onActivateGame?(recordedGame.id) }
                                )
                                // Keep stable identity so the accuracy sheet isn't dismissed when
                                // contentRevision bumps during in-flight assessment.
                                .equatable()
                                .contextMenu {
                                    Button {
                                        copyGameToClipboard(recordedGame)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }

                                    Button {
                                        shareGame(recordedGame)
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }

                                    Button {
                                        gamePendingTagEdit = recordedGame
                                    } label: {
                                        Label("Edit PGN Tags", systemImage: "pencil")
                                    }
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
                                hasIncompleteAssessment: showMoveAssessments
                                    && game.moves.contains(where: { $0.quality == nil }),
                                showMoveAssessments: showMoveAssessments,
                                showAccuracySummary: showAccuracySummary,
                                assessmentColors: assessmentColors,
                                boardAppearance: boardAppearance,
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
        .sheet(item: $gamePendingTagEdit) { recordedGame in
            EditPGNTagsSheet(
                roundTitle: "Round \(recordedGame.round)",
                metadata: recordedGame.metadata,
                date: recordedGame.date
            ) { metadata, date in
                pgnArchive.updateGameTags(id: recordedGame.id, metadata: metadata, date: date)
                onGameTagsEdited?()
            }
        }
        .sheet(isPresented: $showingPGNImport) {
            PGNImportSheet { pgn in
                guard let onImportPGN else { return 0 }
                return try onImportPGN(pgn)
            }
        }
        #endif
    }

    private var presentationInvalidationKey: String {
        PGNPresentationBuilder.cacheKey(
            contentRevision: pgnArchive.contentRevision,
            gameCount: pgnArchive.games.count,
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

        let highlightKey = showMoveAssessments
            ? "assessed"
            : "\(game.activePlyIndex)|\(game.isAtLatestMove)"

        var rebuildIDs = Set<UUID>()

        let contentChanged = pgnArchive.contentRevision != cachedContentRevision
        if contentChanged {
            rebuildIDs.formUnion(pgnArchive.consumeMutatedGameIDs())
            cachedContentRevision = pgnArchive.contentRevision
        }

        if cachedActiveGameID != pgnArchive.activeGameID {
            if let cachedActiveGameID {
                rebuildIDs.insert(cachedActiveGameID)
            }
            if let activeID = pgnArchive.activeGameID {
                rebuildIDs.insert(activeID)
            }
            cachedActiveGameID = pgnArchive.activeGameID
        }

        // Non-assessed mode paints highlight in attributed text — only the active game needs it.
        if !showMoveAssessments,
           highlightKey != cachedHighlightKey,
           let activeID = pgnArchive.activeGameID {
            rebuildIDs.insert(activeID)
        }
        cachedHighlightKey = highlightKey

        // First populate or unknown dirty set → rebuild everything present.
        if presentationCacheKey.isEmpty || (contentChanged && rebuildIDs.isEmpty) {
            rebuildIDs = Set(pgnArchive.games.map(\.id))
        }

        presentationCacheKey = key
        cachedRows = PGNPresentationBuilder.mergeRows(
            existing: cachedRows,
            rebuildIDs: rebuildIDs,
            games: pgnArchive.games,
            activeGameID: pgnArchive.activeGameID,
            activePlyIndex: game.activePlyIndex,
            isAtLatestMove: game.isAtLatestMove,
            hidePGNHeaderTags: hidePGNHeaderTags,
            activeAssessment: activeAssessment,
            showMoveAssessments: showMoveAssessments,
            assessmentColors: assessmentColors
        )
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
            showMoveHighlight: true,
            buildHighlightedMovetext: !showMoveAssessments,
            includeAssessmentSymbols: showMoveAssessments
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

    private func copyGameToClipboard(_ recordedGame: RecordedGame) {
        let pgn = PGNExportService.pgn(
            for: recordedGame,
            includeAssessmentSymbols: includeMoveAssessmentSymbolsInExport
        )
        #if os(iOS)
        UIPasteboard.general.string = pgn
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pgn, forType: .string)
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

    private func shareGame(_ recordedGame: RecordedGame) {
        let pgn = PGNExportService.pgn(
            for: recordedGame,
            includeAssessmentSymbols: includeMoveAssessmentSymbolsInExport
        )
        do {
            let url = try PGNExportService.writeTemporaryFile(
                content: pgn,
                filenamePrefix: "ChessRecorder-R\(recordedGame.round)"
            )
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

private struct GamePGNRowView: View, Equatable {
    let recordedGame: RecordedGame
    let presentation: GameRowPresentation?
    var hideHeaderTags: Bool = true
    let isActive: Bool
    let showMoveHighlight: Bool
    var assessingMoveIndex: Int? = nil
    var hasIncompleteAssessment: Bool = false
    var showMoveAssessments: Bool = false
    var showAccuracySummary: Bool = true
    var assessmentColors: MoveAssessmentColors = .defaults
    var boardAppearance: MiniChessBoardAppearance = .default
    var activePlyIndex: Int = 0
    var isAtLatestMove: Bool = true
    var contentRevision: UInt64 = 0
    var onActivate: (() -> Void)? = nil

    @State private var showingAccuracySummary = false

    static func == (lhs: GamePGNRowView, rhs: GamePGNRowView) -> Bool {
        // Intentionally omit `presentation` — AttributedString equality is O(moves).
        // `contentRevision` covers movetext/quality invalidation.
        lhs.recordedGame.id == rhs.recordedGame.id
            && lhs.recordedGame.moves.count == rhs.recordedGame.moves.count
            && lhs.recordedGame.result == rhs.recordedGame.result
            && lhs.recordedGame.round == rhs.recordedGame.round
            && lhs.recordedGame.eco == rhs.recordedGame.eco
            && lhs.recordedGame.date == rhs.recordedGame.date
            && lhs.recordedGame.metadata == rhs.recordedGame.metadata
            && lhs.recordedGame.isReviewOnly == rhs.recordedGame.isReviewOnly
            && lhs.recordedGame.summaryTitle == rhs.recordedGame.summaryTitle
            && lhs.hideHeaderTags == rhs.hideHeaderTags
            && lhs.isActive == rhs.isActive
            && lhs.showMoveHighlight == rhs.showMoveHighlight
            && lhs.assessingMoveIndex == rhs.assessingMoveIndex
            && lhs.hasIncompleteAssessment == rhs.hasIncompleteAssessment
            && lhs.showMoveAssessments == rhs.showMoveAssessments
            && lhs.showAccuracySummary == rhs.showAccuracySummary
            && lhs.assessmentColors == rhs.assessmentColors
            && lhs.boardAppearance == rhs.boardAppearance
            && lhs.activePlyIndex == rhs.activePlyIndex
            && lhs.isAtLatestMove == rhs.isAtLatestMove
            && lhs.contentRevision == rhs.contentRevision
    }

    private var isAssessingMoves: Bool {
        assessingMoveIndex != nil
    }

    /// Token layout is expensive (one view per ply). Only the live/assessing game needs it;
    /// archived games render a single cached Text.
    private var usesAssessedTokenLayout: Bool {
        (showMoveAssessments || isAssessingMoves) && (isActive || isAssessingMoves)
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
                } else if hasIncompleteAssessment {
                    Image(systemName: "hourglass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Move assessment incomplete")
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onActivate?() }

            if let accuracySummary {
                HStack(alignment: .center, spacing: 0) {
                    GameAccuracyCompactTable(summary: accuracySummary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate?() }

                    Button {
                        showingAccuracySummary = true
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accuracyAccessibilityLabel(accuracySummary))
                    .accessibilityHint("Shows accuracy details")
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }

            Group {
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
                    Text(
                        presentation?.plainMovetext
                            ?? PGNFormatter.movetext(
                                from: recordedGame.moves,
                                result: recordedGame.result,
                                includeAssessmentSymbols: showMoveAssessments
                            )
                    )
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onActivate?() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            Rectangle()
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .sheet(isPresented: $showingAccuracySummary) {
            GameAccuracySummarySheet(
                summary: accuracySummary ?? GameAccuracySummary(moves: recordedGame.moves),
                recordedGame: recordedGame,
                roundTitle: "Round \(recordedGame.round)",
                result: recordedGame.result,
                whiteName: GameAccuracySummarySheet.playerDisplayName(
                    from: recordedGame.metadata.white,
                    fallback: GameAccuracySummary.Side.white.label
                ),
                blackName: GameAccuracySummarySheet.playerDisplayName(
                    from: recordedGame.metadata.black,
                    fallback: GameAccuracySummary.Side.black.label
                ),
                assessmentColors: assessmentColors,
                boardAppearance: boardAppearance
            )
            // Refresh sheet contents when assessments arrive; keep row identity stable
            // so `showingAccuracySummary` is not reset (which would dismiss the sheet).
            .id(contentRevision)
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
                    PGNMoveNumberToken(
                        number: index / 2 + 1,
                        isDimmed: showMoveHighlight && !isAtLatestMove && index >= activePlyIndex
                    )
                    .equatable()
                }

                PGNMoveSANToken(
                    text: move.algebraicNotation + (
                        showMoveAssessments ? (move.quality?.annotationSymbol ?? "") : ""
                    ),
                    isActiveMove: showMoveHighlight && activePlyIndex > 0 && index == activePlyIndex - 1,
                    isDimmed: showMoveHighlight && !isAtLatestMove && index >= activePlyIndex,
                    isAssessing: index == assessingMoveIndex,
                    underlineColor: {
                        guard showMoveAssessments,
                              let quality = move.quality,
                              quality.showsAssessmentDecoration else { return nil }
                        return assessmentColors.underlineColor(for: quality)
                    }()
                )
                .equatable()
            }

            if result != .ongoing {
                Text(result.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PGNMoveNumberToken: View, Equatable {
    let number: Int
    let isDimmed: Bool

    var body: some View {
        Text("\(number).")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(isDimmed ? AnyShapeStyle(.secondary.opacity(0.45)) : AnyShapeStyle(.secondary))
    }
}

private struct PGNMoveSANToken: View, Equatable {
    let text: String
    let isActiveMove: Bool
    let isDimmed: Bool
    let isAssessing: Bool
    let underlineColor: Color?

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(isActiveMove ? .semibold : .regular)
            .foregroundStyle(isDimmed ? AnyShapeStyle(.secondary.opacity(0.45)) : AnyShapeStyle(.primary))
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
                } else if let underlineColor {
                    Capsule()
                        .fill(underlineColor.opacity(isDimmed ? 0.45 : 1))
                        .frame(height: 2.5)
                        .padding(.horizontal, 1)
                        .offset(y: 2)
                }
            }
            .padding(.bottom, (isAssessing || underlineColor != nil) ? 3 : 0)
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

    struct Cache {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for size in cache.sizes {
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

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        if cache.sizes.count != subviews.count {
            cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        }

        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = cache.sizes[index]
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
