//
//  ChessKitMapping.swift
//  Chess Recorder
//

import ChessKit
import Foundation

nonisolated enum ChessKitMapping {
    static func appPieceType(_ kind: Piece.Kind) -> PieceType {
        switch kind {
        case .pawn: .pawn
        case .knight: .knight
        case .bishop: .bishop
        case .rook: .rook
        case .queen: .queen
        case .king: .king
        }
    }

    static func kitKind(_ type: PieceType) -> Piece.Kind {
        switch type {
        case .pawn: .pawn
        case .knight: .knight
        case .bishop: .bishop
        case .rook: .rook
        case .queen: .queen
        case .king: .king
        }
    }

    static func appColor(_ color: Piece.Color) -> PieceColor {
        color == .white ? .white : .black
    }

    static func appPiece(from piece: Piece) -> ChessPiece {
        ChessPiece(type: appPieceType(piece.kind), color: appColor(piece.color))
    }

    static func appPosition(from square: Square) -> ChessPosition {
        ChessPosition(file: square.file.number - 1, rank: square.rank.value - 1)
    }

    static func kitSquare(from position: ChessPosition) -> Square {
        Square(position.notation)
    }

    static func appMove(from move: Move, legalMovesForDisambiguation: [Move] = []) -> ChessMove {
        let captures: Bool
        if case .capture = move.result {
            captures = true
        } else {
            captures = false
        }

        let castling: String?
        if case .castle = move.result {
            castling = move.san.contains("O-O-O") || move.san.contains("0-0-0") ? "O-O-O" : "O-O"
        } else {
            castling = nil
        }

        return ChessMove(
            san: san(for: move, legalMoves: legalMovesForDisambiguation),
            piece: appPieceType(move.piece.kind),
            from: appPosition(from: move.start),
            to: appPosition(from: move.end),
            captures: captures,
            isCheck: move.checkState == .check,
            isCheckmate: move.checkState == .checkmate,
            promotion: move.promotedPiece.map { appPieceType($0.kind) },
            castling: castling
        )
    }

    /// Replays `from`/`to` through ChessKit so SAN includes capture/file/rank disambiguation.
    ///
    /// ChessKit's PGN/SAN *parser* drops disambiguation letters before `x` (e.g. `Rdxd6` → `Rxd6`).
    /// Call this once on import / session restore — not on every PGN row render.
    /// Replaying squares regenerates moves; we then apply our own disambiguation (ChessKit's
    /// `Board.disambiguate` can also miss siblings for some captures).
    static func movesWithCanonicalSAN(_ moves: [ChessMove]) -> [ChessMove] {
        guard !moves.isEmpty else { return moves }
        let rebuilt = ChessGameBackgroundPreparation.prepareTransfer(
            from: moves,
            rebuildCanonicalSAN: true
        ).moves
        guard rebuilt.count == moves.count else { return moves }
        return rebuilt
    }

    /// Builds SAN with disambiguation derived from other legal moves to the same square.
    static func san(for move: Move, legalMoves: [Move]) -> String {
        if case .castle = move.result {
            return move.san
        }
        if move.piece.kind == .pawn || move.piece.kind == .king {
            return move.san
        }

        // Prefer squares alone — ChessKit Move.piece can reflect post-move square/state.
        let sameTargetSiblings = legalMoves.filter {
            $0.start != move.start
                && $0.end == move.end
                && $0.piece.kind == move.piece.kind
        }

        var disambiguation = ""
        if let existing = move.disambiguation, sameTargetSiblings.isEmpty {
            // ChessKit already computed disambiguation; keep it when our sibling scan misses.
            switch existing {
            case .byFile(let file): disambiguation = file.rawValue
            case .byRank(let rank): disambiguation = "\(rank.value)"
            case .bySquare(let square): disambiguation = square.notation
            }
        } else if !sameTargetSiblings.isEmpty {
            let fileConflict = sameTargetSiblings.contains { $0.start.file == move.start.file }
            let rankConflict = sameTargetSiblings.contains { $0.start.rank == move.start.rank }
            switch (fileConflict, rankConflict) {
            case (false, _):
                disambiguation = move.start.file.rawValue
            case (true, false):
                disambiguation = "\(move.start.rank.value)"
            case (true, true):
                disambiguation = move.start.notation
            }
        }

        let pieceLetter: String
        switch move.piece.kind {
        case .knight: pieceLetter = "N"
        case .bishop: pieceLetter = "B"
        case .rook: pieceLetter = "R"
        case .queen: pieceLetter = "Q"
        case .king: pieceLetter = "K"
        case .pawn: pieceLetter = ""
        }

        let capture: String
        if case .capture = move.result {
            capture = "x"
        } else {
            capture = ""
        }

        let promotion: String
        if let promoted = move.promotedPiece {
            switch promoted.kind {
            case .queen: promotion = "=Q"
            case .rook: promotion = "=R"
            case .bishop: promotion = "=B"
            case .knight: promotion = "=N"
            default: promotion = ""
            }
        } else {
            promotion = ""
        }

        let checkSuffix: String
        switch move.checkState {
        case .check: checkSuffix = "+"
        case .checkmate: checkSuffix = "#"
        case .none, .stalemate: checkSuffix = ""
        }

        return "\(pieceLetter)\(disambiguation)\(capture)\(move.end.notation)\(promotion)\(checkSuffix)"
    }

    static func pgnResult(from state: Board.State) -> PGNResult? {
        switch state {
        case .checkmate(let color):
            return color == .black ? .whiteWins : .blackWins
        case .draw:
            return .draw
        default:
            return nil
        }
    }

    static func drawStatusMessage(for reason: Board.State.DrawReason) -> String {
        switch reason {
        case .stalemate:
            return "Stalemate — draw"
        case .fiftyMoves:
            return "Draw — fifty-move rule"
        case .insufficientMaterial:
            return "Draw — insufficient material"
        case .repetition:
            return "Draw — threefold repetition"
        case .agreement:
            return "Draw — by agreement"
        }
    }

    static func normalizeSAN(_ notation: String) -> String {
        var cleaned = notation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0-0-0", with: "O-O-O", options: .caseInsensitive)
            .replacingOccurrences(of: "0-0", with: "O-O", options: .caseInsensitive)

        while let last = cleaned.last, "+#!?".contains(last) {
            cleaned.removeLast()
        }

        if cleaned.count >= 3,
           let last = cleaned.last,
           let pieceChar = String(last).lowercased().first,
           "nbrqk".contains(pieceChar) {
            let body = cleaned.dropLast()
            if let rankChar = body.last, rankChar.isNumber, !body.contains("=") {
                cleaned = String(body) + "=" + String(last).uppercased()
            }
        }

        if cleaned.count >= 2, cleaned.hasPrefix("o-o-o") || cleaned.hasPrefix("O-o-o") {
            cleaned = "O-O-O"
        } else if cleaned.lowercased() == "o-o" {
            cleaned = "O-O"
        }

        // Pawn captures use a lowercase file letter (bxc6). Do not treat leading "b" as bishop.
        if !isPawnFileCaptureSAN(cleaned),
           let first = cleaned.first,
           "nbrqk".contains(first.lowercased()),
           cleaned.count > 1,
           let second = cleaned.dropFirst().first,
           !second.isNumber {
            cleaned.replaceSubrange(cleaned.startIndex...cleaned.startIndex, with: String(first).uppercased())
        }

        return cleaned
    }

    /// True for pawn file captures such as `bxc6` or `exd5`.
    /// Pawns only capture on diagonally adjacent files, so `bxh6` is not a pawn capture.
    /// Uppercase leading letters (e.g. `Bxc4`) denote pieces, not pawn files.
    static func isPawnFileCaptureSAN(_ notation: String) -> Bool {
        guard notation.first?.isLowercase == true else { return false }

        let chars = Array(notation.lowercased())
        guard chars.count >= 4,
              chars[1] == "x",
              ("a"..."h").contains(chars[0]),
              ("a"..."h").contains(chars[2]),
              ("1"..."8").contains(chars[3]) else {
            return false
        }

        guard let fromFile = chars[0].asciiValue,
              let toFile = chars[2].asciiValue else {
            return false
        }

        return abs(Int(fromFile) - Int(toFile)) == 1
    }

    static func parseCoordinateMove(_ notation: String) -> (from: ChessPosition, to: ChessPosition, promotion: PieceType?)? {
        let cleaned = notation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "x" }

        var compact = cleaned

        if let first = compact.first, "nbrqk".contains(first) {
            compact.removeFirst()
        }

        compact = compact.replacingOccurrences(of: "x", with: "")

        guard compact.count == 4 || compact.count == 5 else { return nil }

        let fromString = String(compact.prefix(2))
        let toString = String(compact.dropFirst(2).prefix(2))

        guard let from = ChessPosition(notation: fromString),
              let to = ChessPosition(notation: toString) else {
            return nil
        }

        let promotion: PieceType?
        if compact.count == 5 {
            switch compact.last {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: return nil
            }
        } else {
            promotion = nil
        }

        return (from: from, to: to, promotion: promotion)
    }

    static func formatEnginePrincipalLineSAN(_ uciMoves: [String], fen: String) -> String {
        guard !uciMoves.isEmpty, let position = Position(fen: fen) else { return "—" }

        var board = Board(position: position)
        var sanMoves: [String] = []

        for uci in uciMoves {
            guard let components = engineMoveComponents(from: uci),
                  let from = ChessPosition(notation: components.from),
                  let to = ChessPosition(notation: components.to) else {
                return uciMoves.joined(separator: " ")
            }

            let fromSquare = kitSquare(from: from)
            let toSquare = kitSquare(from: to)

            guard var move = board.move(pieceAt: fromSquare, to: toSquare) else {
                return uciMoves.joined(separator: " ")
            }

            if case .promotion(let promotionMove) = board.state {
                let promotionKind = pieceKind(from: components.promotion) ?? .queen
                move = board.completePromotion(of: promotionMove, to: promotionKind)
            }

            sanMoves.append(move.san)
        }

        return sanMoves.joined(separator: " ")
    }

    static func engineMoveComponents(from uci: String) -> (from: String, to: String, promotion: String?)? {
        let chars = Array(uci)
        guard chars.count == 4 || chars.count == 5 else { return nil }

        let from = String(chars[0...1])
        let to = String(chars[2...3])
        let promotion = chars.count == 5 ? String(chars[4]) : nil
        return (from: from, to: to, promotion: promotion)
    }

    private static func pieceKind(from promotion: String?) -> Piece.Kind? {
        switch promotion?.lowercased() {
        case "q": .queen
        case "r": .rook
        case "b": .bishop
        case "n": .knight
        default: nil
        }
    }
}
