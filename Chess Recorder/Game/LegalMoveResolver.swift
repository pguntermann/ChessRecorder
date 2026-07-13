//
//  LegalMoveResolver.swift
//  Chess Recorder
//

import ChessKit
import Foundation

enum LegalMoveResolver {

    private static let confusedFileGroups: [Set<Character>] = [
        ["e", "g", "a"],
        ["c", "e"],
        ["b", "d"]
    ]

    /// Alternate square notations when a file letter may have been misheard (e.g. g3 → e3).
    static func squareNotationVariants(for notation: String) -> [String] {
        let lowered = notation.lowercased()
        guard lowered.count == 2,
              let file = lowered.first,
              let rank = lowered.last,
              "abcdefgh".contains(file),
              "12345678".contains(rank) else {
            return []
        }

        return confusedTargetFiles(for: file).map { String($0) + String(rank) }
    }

    /// True when SAN names a specific source file, rank, or square (e.g. Nbxd7, Rfd1).
    static func requiresExplicitSourceMatch(_ notation: String) -> Bool {
        guard let intent = parseIntent(ChessKitMapping.normalizeSAN(notation)) else { return false }
        if case .piece(_, _, let disambiguation, _, _) = intent {
            return disambiguation != nil
        }
        return false
    }

    /// Finds a legal move matching spoken notation, using the same destinations as touch input.
    static func match(
        notation: String,
        among legalMoves: [Move],
        allowConfusedFiles: Bool = true
    ) -> Move? {
        let normalized = ChessKitMapping.normalizeSAN(notation)

        if let move = exactMatch(normalized, among: legalMoves) {
            return move
        }

        if let intent = parseIntent(normalized),
           let move = match(intent: intent, among: legalMoves, allowConfusedFiles: allowConfusedFiles) {
            return move
        }

        return nil
    }

    /// Picks the best legal move for a ranked list of spoken candidates.
    static func matchBest(
        candidates: [String],
        among legalMoves: [Move],
        preferCaptures: Bool = false
    ) -> Move? {
        if preferCaptures {
            for candidate in candidates {
                if let move = match(notation: candidate, among: legalMoves, allowConfusedFiles: true),
                   isCapture(move) {
                    return move
                }
            }
            for candidate in candidates {
                if let move = match(notation: candidate, among: legalMoves, allowConfusedFiles: true),
                   !isCapture(move) {
                    return move
                }
            }
            return nil
        }

        for candidate in candidates {
            if let move = match(notation: candidate, among: legalMoves, allowConfusedFiles: true) {
                return move
            }
        }
        return nil
    }

    // MARK: - Matching

    private static func exactMatch(_ notation: String, among legalMoves: [Move]) -> Move? {
        let lowered = notation.lowercased()
        return legalMoves.first { move in
            move.san.lowercased() == lowered
                || move.lan.lowercased() == lowered
                || coordinateNotation(for: move).lowercased() == lowered
        }
    }

    private static func match(
        intent: Intent,
        among legalMoves: [Move],
        allowConfusedFiles: Bool
    ) -> Move? {
        switch intent {
        case .castling(let queenside):
            return unique(legalMoves.filter { move in
                guard case .castle = move.result else { return false }
                let san = move.san.uppercased()
                if queenside {
                    return san.contains("O-O-O")
                }
                return san.contains("O-O") && !san.contains("O-O-O")
            })

        case .coordinate(let from, let to, let promotion):
            let effectivePromotion = promotion ?? defaultPromotion(for: to)
            return unique(legalMoves.filter { move in
                ChessKitMapping.appPosition(from: move.start) == from
                    && ChessKitMapping.appPosition(from: move.end) == to
                    && promotionKind(for: move) == effectivePromotion
            })

        case .pawn(let to, let captureFile, let promotion):
            let effectivePromotion = promotion ?? defaultPromotion(for: to)
            return matchPieceLike(
                kind: .pawn,
                to: to,
                disambiguation: captureFile.map { .byFile($0) },
                capture: captureFile != nil,
                promotion: effectivePromotion,
                among: legalMoves,
                allowConfusedFiles: allowConfusedFiles
            )

        case .piece(let kind, let to, let disambiguation, let capture, let promotion):
            return matchPieceLike(
                kind: kind,
                to: to,
                disambiguation: disambiguation,
                capture: capture,
                promotion: promotion,
                among: legalMoves,
                allowConfusedFiles: allowConfusedFiles
            )
        }
    }

    private static func matchPieceLike(
        kind: Piece.Kind,
        to: Square,
        disambiguation: Move.Disambiguation?,
        capture: Bool,
        promotion: Piece.Kind?,
        among legalMoves: [Move],
        allowConfusedFiles: Bool
    ) -> Move? {
        let exact = filterMoves(
            kind: kind,
            to: to,
            disambiguation: disambiguation,
            capture: capture,
            promotion: promotion,
            among: legalMoves
        )
        if let move = unique(exact) {
            return move
        }

        guard allowConfusedFiles, disambiguation == nil else { return nil }

        var confusedMatches: [Move] = []
        for alternateFile in confusedTargetFiles(for: Character(to.file.rawValue)) {
            let alternateSquare = Square("\(alternateFile)\(to.rank.value)")
            confusedMatches.append(contentsOf: filterMoves(
                kind: kind,
                to: alternateSquare,
                disambiguation: nil,
                capture: capture,
                promotion: promotion,
                among: legalMoves
            ))
        }

        return resolveConfusedFileMatches(confusedMatches)
    }

    private static func filterMoves(
        kind: Piece.Kind,
        to: Square,
        disambiguation: Move.Disambiguation?,
        capture: Bool,
        promotion: Piece.Kind?,
        among legalMoves: [Move]
    ) -> [Move] {
        legalMoves.filter { move in
            move.piece.kind == kind
                && move.end == to
                && satisfiesDisambiguation(move, disambiguation)
                && isCapture(move) == capture
                && promotionKind(for: move) == promotion
        }
    }

    private static func unique(_ moves: [Move]) -> Move? {
        guard !moves.isEmpty else { return nil }
        let starts = Set(moves.map(\.start))
        guard starts.count == 1 else { return nil }
        return moves.first
    }

    /// Accept a single match, or several moves that share the same destination square.
    private static func resolveConfusedFileMatches(_ moves: [Move]) -> Move? {
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }
        let destinations = Set(moves.map(\.end))
        guard destinations.count == 1 else { return nil }
        return moves[0]
    }

    private static func satisfiesDisambiguation(_ move: Move, _ disambiguation: Move.Disambiguation?) -> Bool {
        guard let disambiguation else { return true }
        switch disambiguation {
        case .byFile(let file):
            return move.start.file == file
        case .byRank(let rank):
            return move.start.rank == rank
        case .bySquare(let square):
            return move.start == square
        }
    }

    private static func isCapture(_ move: Move) -> Bool {
        if case .capture = move.result { return true }
        return false
    }

    private static func promotionKind(for move: Move) -> Piece.Kind? {
        move.promotedPiece?.kind
    }

    private static func defaultPromotion(for square: Square) -> Piece.Kind? {
        guard square.rank.value == 1 || square.rank.value == 8 else { return nil }
        return .queen
    }

    private static func defaultPromotion(for position: ChessPosition) -> Piece.Kind? {
        guard position.rank == 0 || position.rank == 7 else { return nil }
        return .queen
    }

    private static func coordinateNotation(for move: Move) -> String {
        move.start.notation + move.end.notation
    }

    private static func confusedTargetFiles(for file: Character) -> [Character] {
        guard let group = confusedFileGroups.first(where: { $0.contains(file) }) else { return [] }
        return group.filter { $0 != file }
    }

    // MARK: - Parsing

    private enum Intent {
        case castling(queenside: Bool)
        case coordinate(from: ChessPosition, to: ChessPosition, promotion: Piece.Kind?)
        case pawn(to: Square, captureFile: Square.File?, promotion: Piece.Kind?)
        case piece(
            kind: Piece.Kind,
            to: Square,
            disambiguation: Move.Disambiguation?,
            capture: Bool,
            promotion: Piece.Kind?
        )
    }

    private static func parseIntent(_ notation: String) -> Intent? {
        let lowered = notation.lowercased()

        if lowered == "o-o" || lowered == "0-0" {
            return .castling(queenside: false)
        }
        if lowered == "o-o-o" || lowered == "0-0-0" {
            return .castling(queenside: true)
        }

        if let coordinate = ChessKitMapping.parseCoordinateMove(notation) {
            let promotion = coordinate.promotion.map(ChessKitMapping.kitKind)
            return .coordinate(from: coordinate.from, to: coordinate.to, promotion: promotion)
        }

        if ChessKitMapping.isPawnFileCaptureSAN(notation),
           let capture = parsePawnCapture(notation) {
            return .pawn(to: capture.to, captureFile: capture.file, promotion: capture.promotion)
        }

        if let pawn = parsePawnMove(notation) {
            return .pawn(to: pawn.to, captureFile: nil, promotion: pawn.promotion)
        }

        if let piece = parsePieceMove(notation) {
            return .piece(
                kind: piece.kind,
                to: piece.to,
                disambiguation: piece.disambiguation,
                capture: piece.capture,
                promotion: piece.promotion
            )
        }

        return nil
    }

    private static func parsePawnMove(_ notation: String) -> (to: Square, promotion: Piece.Kind?)? {
        var cleaned = notation.lowercased()
        let promotion = parsePromotion(&cleaned)
        guard cleaned.count == 2, isValidSquareNotation(cleaned) else { return nil }
        return (Square(cleaned), promotion)
    }

    private static func parsePawnCapture(_ notation: String) -> (file: Square.File, to: Square, promotion: Piece.Kind?)? {
        var cleaned = notation.lowercased()
        let promotion = parsePromotion(&cleaned)
        let target = String(cleaned.suffix(2))
        guard cleaned.count == 4,
              cleaned[cleaned.index(cleaned.startIndex, offsetBy: 1)] == "x",
              let file = Square.File(rawValue: String(cleaned.first!)),
              isValidSquareNotation(target) else {
            return nil
        }
        return (file, Square(target), promotion)
    }

    private static func parsePieceMove(
        _ notation: String
    ) -> (kind: Piece.Kind, to: Square, disambiguation: Move.Disambiguation?, capture: Bool, promotion: Piece.Kind?)? {
        var cleaned = notation
        guard let first = cleaned.first,
              let kind = pieceKind(for: first) else {
            return nil
        }

        cleaned.removeFirst()
        var capture = false
        if cleaned.contains("x") {
            capture = true
            cleaned = cleaned.replacingOccurrences(of: "x", with: "")
        }

        let promotion = parsePromotion(&cleaned)
        let targetNotation = String(cleaned.suffix(2))
        guard cleaned.count >= 2,
              isValidSquareNotation(targetNotation) else {
            return nil
        }
        let target = Square(targetNotation)

        let disambiguationText = String(cleaned.dropLast(2))
        let disambiguation: Move.Disambiguation?
        switch disambiguationText.count {
        case 0:
            disambiguation = nil
        case 1:
            let char = disambiguationText.first!
            if let file = Square.File(rawValue: String(char)), "abcdefgh".contains(char) {
                disambiguation = .byFile(file)
            } else if let rank = Int(String(char)) {
                disambiguation = .byRank(Square.Rank(rank))
            } else {
                return nil
            }
        case 2:
            guard isValidSquareNotation(disambiguationText) else { return nil }
            disambiguation = .bySquare(Square(disambiguationText))
        default:
            return nil
        }

        return (kind, target, disambiguation, capture, promotion)
    }

    private static func pieceKind(for character: Character) -> Piece.Kind? {
        Piece.Kind(rawValue: String(character).uppercased())
    }

    private static func isValidSquareNotation(_ notation: String) -> Bool {
        guard notation.count == 2,
              let file = notation.first,
              let rank = notation.last else {
            return false
        }
        return "abcdefgh".contains(file) && "12345678".contains(rank)
    }

    private static func parsePromotion(_ notation: inout String) -> Piece.Kind? {
        guard let equalsIndex = notation.firstIndex(of: "=") else { return nil }
        let pieceChar = notation[notation.index(after: equalsIndex)...].first
        notation = String(notation[..<equalsIndex])
        guard let pieceChar else { return nil }
        return Piece.Kind(rawValue: String(pieceChar).uppercased())
    }
}
