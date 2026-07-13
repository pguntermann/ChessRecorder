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
    static func cacheKey(
        games: [RecordedGame],
        activeGameID: UUID?,
        activePlyIndex: Int,
        isAtLatestMove: Bool,
        metadata: PGNMetadata,
        hidePGNHeaderTags: Bool
    ) -> String {
        let gameSignature = games.map {
            "\($0.id.uuidString):\($0.moves.count):\($0.result.rawValue):\($0.round):\($0.eco ?? "")"
        }.joined(separator: "|")
        return "\(gameSignature)|\(activeGameID?.uuidString ?? "none")|\(activePlyIndex)|\(isAtLatestMove)|\(metadata)|\(hidePGNHeaderTags)"
    }

    static func build(
        games: [RecordedGame],
        activeGameID: UUID?,
        activePlyIndex: Int,
        isAtLatestMove: Bool,
        metadata: PGNMetadata,
        hidePGNHeaderTags: Bool
    ) -> [UUID: GameRowPresentation] {
        var rows: [UUID: GameRowPresentation] = [:]

        _ = metadata
        _ = hidePGNHeaderTags

        for game in games.reversed() where !game.moves.isEmpty {
            rows[game.id] = rowPresentation(
                for: game,
                eco: game.eco,
                activePlyIndex: activePlyIndex,
                isAtLatestMove: isAtLatestMove,
                showMoveHighlight: game.id == activeGameID
            )
        }

        return rows
    }

    static func rowPresentation(
        for game: RecordedGame,
        eco: String?,
        activePlyIndex: Int,
        isAtLatestMove: Bool,
        showMoveHighlight: Bool
    ) -> GameRowPresentation {
        GameRowPresentation(
            eco: eco,
            highlightedMovetext: highlightedMovetext(
                moves: game.moves,
                result: game.result,
                activePlyIndex: activePlyIndex,
                isAtLatestMove: isAtLatestMove,
                showMoveHighlight: showMoveHighlight
            ),
            plainMovetext: PGNFormatter.movetext(from: game.moves, result: game.result)
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
