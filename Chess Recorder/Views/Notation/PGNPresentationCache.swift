//
//  PGNPresentationCache.swift
//  Chess Recorder
//

import SwiftUI

struct GameRowPresentation: Equatable {
    let eco: String?
    let highlightedMovetext: AttributedString
    let plainMovetext: String
}

@MainActor
enum PGNPresentationBuilder {
    /// Cheap invalidation key. Relies on `PGNArchive.contentRevision` instead of scanning
    /// every archived game on each SwiftUI body evaluation.
    ///
    /// When move assessments are shown, ply highlight is handled by token views directly, so
    /// `activePlyIndex` is omitted and attributed highlight rebuilds are skipped.
    static func cacheKey(
        contentRevision: UInt64,
        gameCount: Int,
        activeGameID: UUID?,
        activePlyIndex: Int,
        isAtLatestMove: Bool,
        hidePGNHeaderTags: Bool,
        activeAssessment: MoveAssessmentProgress?,
        showMoveAssessments: Bool,
        assessmentColorsCacheKey: String
    ) -> String {
        let assessmentKey = activeAssessment.map { "\($0.gameID.uuidString):\($0.moveIndex)" } ?? "none"
        // Assessed token layout paints highlight from live ply props — no attributed rebuild.
        let highlightKey = showMoveAssessments
            ? "assessed"
            : "\(activePlyIndex)|\(isAtLatestMove)"
        return "\(contentRevision)|\(gameCount)|\(activeGameID?.uuidString ?? "none")|\(highlightKey)|\(hidePGNHeaderTags)|\(assessmentKey)|\(showMoveAssessments)|\(assessmentColorsCacheKey)"
    }

    static func build(
        games: [RecordedGame],
        activeGameID: UUID?,
        activePlyIndex: Int,
        isAtLatestMove: Bool,
        hidePGNHeaderTags: Bool,
        activeAssessment: MoveAssessmentProgress?,
        showMoveAssessments: Bool,
        assessmentColors: MoveAssessmentColors
    ) -> [UUID: GameRowPresentation] {
        mergeRows(
            existing: [:],
            rebuildIDs: Set(games.map(\.id)),
            games: games,
            activeGameID: activeGameID,
            activePlyIndex: activePlyIndex,
            isAtLatestMove: isAtLatestMove,
            hidePGNHeaderTags: hidePGNHeaderTags,
            activeAssessment: activeAssessment,
            showMoveAssessments: showMoveAssessments,
            assessmentColors: assessmentColors
        )
    }

    /// Keeps cached rows for unchanged games; rebuilds only `rebuildIDs` (and drops removed games).
    static func mergeRows(
        existing: [UUID: GameRowPresentation],
        rebuildIDs: Set<UUID>,
        games: [RecordedGame],
        activeGameID: UUID?,
        activePlyIndex: Int,
        isAtLatestMove: Bool,
        hidePGNHeaderTags: Bool,
        activeAssessment: MoveAssessmentProgress?,
        showMoveAssessments: Bool,
        assessmentColors: MoveAssessmentColors
    ) -> [UUID: GameRowPresentation] {
        _ = hidePGNHeaderTags
        _ = assessmentColors
        _ = activeAssessment

        let currentIDs = Set(games.map(\.id))
        var rows = existing.filter { currentIDs.contains($0.key) }

        for game in games where !game.moves.isEmpty && rebuildIDs.contains(game.id) {
            rows[game.id] = rowPresentation(
                for: game,
                eco: game.eco,
                activePlyIndex: activePlyIndex,
                isAtLatestMove: isAtLatestMove,
                showMoveHighlight: game.id == activeGameID,
                buildHighlightedMovetext: !showMoveAssessments,
                includeAssessmentSymbols: showMoveAssessments
            )
        }

        // Drop empty games that no longer have presentation.
        for game in games where game.moves.isEmpty {
            rows.removeValue(forKey: game.id)
        }

        return rows
    }

    static func rowPresentation(
        for game: RecordedGame,
        eco: String?,
        activePlyIndex: Int,
        isAtLatestMove: Bool,
        showMoveHighlight: Bool,
        buildHighlightedMovetext: Bool = true,
        includeAssessmentSymbols: Bool = false
    ) -> GameRowPresentation {
        let plain = PGNFormatter.movetext(
            from: game.moves,
            result: game.result,
            includeAssessmentSymbols: includeAssessmentSymbols
        )
        let highlighted: AttributedString
        if buildHighlightedMovetext {
            highlighted = Self.highlightedMovetext(
                moves: game.moves,
                result: game.result,
                activePlyIndex: activePlyIndex,
                isAtLatestMove: isAtLatestMove,
                showMoveHighlight: showMoveHighlight
            )
        } else {
            highlighted = AttributedString(plain)
        }

        return GameRowPresentation(
            eco: eco,
            highlightedMovetext: highlighted,
            plainMovetext: plain
        )
    }

    static func highlightedMovetext(
        moves: [ChessMove],
        result: PGNResult,
        activePlyIndex: Int,
        isAtLatestMove: Bool,
        showMoveHighlight: Bool
    ) -> AttributedString {
        guard showMoveHighlight else {
            return AttributedString(PGNFormatter.movetext(from: moves, result: result))
        }

        var text = AttributedString()
        let activeMoveIndex = activePlyIndex > 0 ? activePlyIndex - 1 : nil

        for (index, move) in moves.enumerated() {
            if index % 2 == 0 {
                var moveNumber = AttributedString("\(index / 2 + 1). ")
                moveNumber.foregroundColor = moveColor(
                    for: index,
                    isMoveNumber: true,
                    activePlyIndex: activePlyIndex,
                    isAtLatestMove: isAtLatestMove
                )
                text.append(moveNumber)
            }

            var san = AttributedString(move.algebraicNotation)
            san.foregroundColor = moveColor(
                for: index,
                isMoveNumber: false,
                activePlyIndex: activePlyIndex,
                isAtLatestMove: isAtLatestMove
            )

            if index == activeMoveIndex {
                san.font = .system(.caption, design: .monospaced).bold()
                san.backgroundColor = Color.accentColor.opacity(0.25)
            }

            text.append(san)
            text.append(AttributedString(" "))
        }

        if result != .ongoing {
            var resultText = AttributedString(result.rawValue)
            resultText.foregroundColor = .secondary
            text.append(resultText)
        }

        return text
    }

    private static func moveColor(
        for index: Int,
        isMoveNumber: Bool,
        activePlyIndex: Int,
        isAtLatestMove: Bool
    ) -> Color {
        if !isAtLatestMove && index >= activePlyIndex {
            return .secondary.opacity(0.45)
        }
        return isMoveNumber ? .secondary : .primary
    }
}
