//
//  ChessGameBackgroundPreparation.swift
//  Chess Recorder
//
//  ChessKit main-line replay that opts out of default MainActor isolation so game-switch
//  preparation can run on a background executor without hopping back to the UI thread.
//

import ChessKit
import Foundation

nonisolated enum ChessGameBackgroundPreparation {
    /// Value-type snapshot of a fully replayed game. Safe to hand across executors.
    struct Transfer: @unchecked Sendable {
        let kitBoard: Board
        let kitGame: ChessKit.Game
        let currentIndex: MoveTree.Index
        let moves: [ChessMove]
        let declaredResult: PGNResult?
        let statusMessageOverride: String?
        let gameResult: PGNResult
        let activePlyIndex: Int
    }

    static func prepareTransfer(
        from recordedMoves: [ChessMove],
        result: PGNResult = .ongoing,
        rebuildCanonicalSAN: Bool = false
    ) -> Transfer {
        var kitBoard = Board()
        var kitGame = ChessKit.Game()
        var currentIndex = kitGame.startingIndex
        var rebuiltMoves: [ChessMove] = []
        rebuiltMoves.reserveCapacity(recordedMoves.count)

        for recordedMove in recordedMoves {
            // Legal-move enumeration is only needed when repairing capture disambiguation SAN.
            // Game switch / prefetch / board load keep archived moves (SAN + assessments) as-is.
            let legalMoves = rebuildCanonicalSAN
                ? enumerateLegalKitMoves(kitBoard: kitBoard)
                : []
            guard let kitMove = makeReplayKitMove(
                for: recordedMove,
                kitBoard: &kitBoard
            ) else {
                // Match ChessGame.loadMainLine failure semantics: return empty rather than partial.
                return emptyTransfer()
            }
            currentIndex = kitGame.make(move: kitMove, from: currentIndex)
            if rebuildCanonicalSAN {
                var canonical = ChessKitMapping.appMove(
                    from: kitMove,
                    legalMovesForDisambiguation: legalMoves
                )
                if let quality = recordedMove.quality {
                    canonical = canonical.withQuality(
                        quality,
                        centipawnLoss: recordedMove.centipawnLoss,
                        evaluationWhiteCentipawns: recordedMove.evaluationWhiteCentipawns,
                        bestMoveSAN: recordedMove.bestMoveSAN
                    )
                }
                rebuiltMoves.append(canonical)
            } else {
                rebuiltMoves.append(recordedMove)
            }
        }

        var declaredResult: PGNResult?
        var statusMessageOverride: String?
        var gameResult: PGNResult = .ongoing
        if result != .ongoing {
            declaredResult = result
            gameResult = result
            statusMessageOverride = declaredResultStatusMessage(for: result)
        }

        return Transfer(
            kitBoard: kitBoard,
            kitGame: kitGame,
            currentIndex: currentIndex,
            moves: rebuiltMoves,
            declaredResult: declaredResult,
            statusMessageOverride: statusMessageOverride,
            gameResult: gameResult,
            activePlyIndex: rebuiltMoves.count
        )
    }

    /// FEN after each ply (including the starting position). Skips legal-move enumeration
    /// and MoveTree updates — use for assessment queueing, not for SAN repair.
    static func fenSequence(from recordedMoves: [ChessMove]) -> [String] {
        var kitBoard = Board()
        var fens: [String] = [kitBoard.position.fen]
        fens.reserveCapacity(recordedMoves.count + 1)

        for recordedMove in recordedMoves {
            guard makeReplayKitMove(for: recordedMove, kitBoard: &kitBoard) != nil else {
                return []
            }
            fens.append(kitBoard.position.fen)
        }
        return fens
    }

    private static func emptyTransfer() -> Transfer {
        let kitGame = ChessKit.Game()
        return Transfer(
            kitBoard: Board(),
            kitGame: kitGame,
            currentIndex: kitGame.startingIndex,
            moves: [],
            declaredResult: nil,
            statusMessageOverride: nil,
            gameResult: .ongoing,
            activePlyIndex: 0
        )
    }

    private static func declaredResultStatusMessage(for result: PGNResult) -> String {
        switch result {
        case .whiteWins:
            return "White wins — 1-0"
        case .blackWins:
            return "Black wins — 0-1"
        case .draw:
            return "Draw — ½-½"
        case .ongoing:
            return ""
        }
    }

    private static func makeReplayKitMove(
        for recordedMove: ChessMove,
        kitBoard: inout Board
    ) -> Move? {
        if let move = makeReplayKitMove(
            from: recordedMove.from,
            to: recordedMove.to,
            promotion: recordedMove.promotion,
            kitBoard: &kitBoard
        ) {
            return move
        }
        return makeReplayKitMoveFromSAN(recordedMove.san, kitBoard: &kitBoard)
    }

    private static func makeReplayKitMove(
        from: ChessPosition,
        to: ChessPosition,
        promotion: PieceType?,
        kitBoard: inout Board
    ) -> Move? {
        let start = ChessKitMapping.kitSquare(from: from)
        let end = ChessKitMapping.kitSquare(from: to)
        guard kitBoard.position.piece(at: start) != nil else { return nil }

        guard var kitMove = kitBoard.move(pieceAt: start, to: end) else {
            return nil
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = ChessKitMapping.kitKind(promotion ?? .queen)
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return kitMove
    }

    private static func makeReplayKitMoveFromSAN(
        _ notation: String,
        kitBoard: inout Board
    ) -> Move? {
        if let coordinateMove = ChessKitMapping.parseCoordinateMove(notation),
           let move = makeReplayKitMove(
            from: coordinateMove.from,
            to: coordinateMove.to,
            promotion: coordinateMove.promotion,
            kitBoard: &kitBoard
           ) {
            return move
        }

        if LegalMoveResolver.requiresExplicitSourceMatch(notation) {
            return makeReplayKitMoveViaLegalMatch(notation, kitBoard: &kitBoard)
        }

        let normalized = ChessKitMapping.normalizeSAN(notation)
        let position = kitBoard.position

        if let parsed = Move(san: normalized, position: position)
            ?? (ChessKitMapping.isPawnFileCaptureSAN(normalized)
                ? nil
                : Move(san: normalized.uppercased(), position: position)),
           let move = applyKitMoveOnBoard(parsed, kitBoard: &kitBoard) {
            return move
        }

        return makeReplayKitMoveViaLegalMatch(notation, kitBoard: &kitBoard)
    }

    private static func makeReplayKitMoveViaLegalMatch(
        _ notation: String,
        kitBoard: inout Board
    ) -> Move? {
        let legalMoves = enumerateLegalKitMoves(kitBoard: kitBoard)
        guard let matched = LegalMoveResolver.match(notation: notation, among: legalMoves) else {
            return nil
        }
        return applyKitMoveOnBoard(matched, kitBoard: &kitBoard)
    }

    private static func applyKitMoveOnBoard(
        _ parsed: Move,
        kitBoard: inout Board
    ) -> Move? {
        guard kitBoard.position.piece(at: parsed.start) != nil else { return nil }

        guard var kitMove = kitBoard.move(pieceAt: parsed.start, to: parsed.end) else {
            return nil
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = parsed.promotedPiece?.kind ?? .queen
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return kitMove
    }

    private static func enumerateLegalKitMoves(kitBoard: Board) -> [Move] {
        var moves: [Move] = []
        let position = kitBoard.position
        let side = position.sideToMove

        for piece in position.pieces where piece.color == side {
            let start = piece.square
            for end in kitBoard.legalMoves(forPieceAt: start) {
                var probe = kitBoard
                guard let move = probe.move(pieceAt: start, to: end) else { continue }

                if case .promotion = probe.state {
                    for kind in [Piece.Kind.queen, .rook, .bishop, .knight] {
                        var promotionBoard = kitBoard
                        guard promotionBoard.move(pieceAt: start, to: end) != nil else { continue }
                        guard case .promotion(let promotionMove) = promotionBoard.state else { continue }
                        moves.append(promotionBoard.completePromotion(of: promotionMove, to: kind))
                    }
                } else {
                    moves.append(move)
                }
            }
        }

        return moves
    }
}
