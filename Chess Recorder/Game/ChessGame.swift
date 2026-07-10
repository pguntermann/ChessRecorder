//
//  ChessGame.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import ChessKit
import Foundation

enum PieceType: String {
    case pawn = ""
    case knight = "N"
    case bishop = "B"
    case rook = "R"
    case queen = "Q"
    case king = "K"
}

enum PieceColor {
    case white, black

    var opposite: PieceColor {
        self == .white ? .black : .white
    }
}

struct ChessPiece: Identifiable, Equatable {
    let id = UUID()
    let type: PieceType
    let color: PieceColor

    static func == (lhs: ChessPiece, rhs: ChessPiece) -> Bool {
        lhs.type == rhs.type && lhs.color == rhs.color
    }

    var imageName: String {
        let colorPrefix = color == .white ? "w" : "b"
        let pieceName: String
        switch type {
        case .pawn: pieceName = "p"
        case .knight: pieceName = "n"
        case .bishop: pieceName = "b"
        case .rook: pieceName = "r"
        case .queen: pieceName = "q"
        case .king: pieceName = "k"
        }
        return "\(colorPrefix)\(pieceName)"
    }
}

struct ChessPosition: Equatable, Hashable {
    let file: Int  // 0-7 (a-h)
    let rank: Int  // 0-7 (1-8)

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    init?(notation: String) {
        guard notation.count == 2 else { return nil }
        let chars = Array(notation.lowercased())
        guard let fileChar = chars.first,
              let rankChar = chars.last,
              let fileIndex = "abcdefgh".firstIndex(of: fileChar),
              let rank = Int(String(rankChar)) else {
            return nil
        }
        self.file = "abcdefgh".distance(from: "abcdefgh".startIndex, to: fileIndex)
        self.rank = rank - 1
    }

    var notation: String {
        let files = "abcdefgh"
        let fileChar = files[files.index(files.startIndex, offsetBy: file)]
        return "\(fileChar)\(rank + 1)"
    }
}

struct ChessMove {
    let san: String
    let piece: PieceType
    let from: ChessPosition
    let to: ChessPosition
    let captures: Bool
    let isCheck: Bool
    let isCheckmate: Bool
    let promotion: PieceType?
    let castling: String?

    var algebraicNotation: String { san }
}

struct AnimatedPieceMove: Equatable {
    let piece: ChessPiece
    let from: ChessPosition
    let to: ChessPosition
}

struct ActiveMoveAnimation: Equatable {
    let id: UUID
    let primary: AnimatedPieceMove
    let secondary: AnimatedPieceMove?
}

@Observable
class ChessGame {
    private(set) var board: [[ChessPiece?]]
    private(set) var currentTurn: PieceColor = .white
    private(set) var moves: [ChessMove] = []
    private(set) var gameResult: PGNResult = .ongoing
    /// Half-move count from the starting position to the viewed position (0 = start).
    private(set) var activePlyIndex: Int = 0
    var activeMoveAnimation: ActiveMoveAnimation?

    @ObservationIgnored private var kitBoard: Board
    @ObservationIgnored private var kitGame: ChessKit.Game
    @ObservationIgnored private var currentIndex: MoveTree.Index

    init() {
        let game = ChessKit.Game()
        kitBoard = Board()
        kitGame = game
        currentIndex = game.startingIndex
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        syncBoardFromKit()
    }

    func pieceAt(_ position: ChessPosition) -> ChessPiece? {
        guard position.file >= 0, position.file < 8,
              position.rank >= 0, position.rank < 8 else {
            return nil
        }
        return board[position.file][position.rank]
    }

    @discardableResult
    func executeSAN(_ notation: String) -> Bool {
        guard isAtLatestMove else { return false }

        if let coordinateMove = ChessKitMapping.parseCoordinateMove(notation) {
            if performMove(
                from: coordinateMove.from,
                to: coordinateMove.to,
                promotion: coordinateMove.promotion
            ) {
                return true
            }
            return executeLegalMatch(notation: notation)
        }

        let normalized = ChessKitMapping.normalizeSAN(notation)
        let position = kitBoard.position

        if let parsed = Move(san: normalized, position: position)
            ?? (ChessKitMapping.isPawnFileCaptureSAN(normalized)
                ? nil
                : Move(san: normalized.uppercased(), position: position)) {
            if applyParsedMove(parsed) {
                return true
            }
        }

        return executeLegalMatch(notation: notation)
    }

    /// Tries spoken move candidates against the current legal moves (same path as touch input).
    @discardableResult
    func executeVoiceCandidates(_ candidates: [String]) -> Bool {
        guard isAtLatestMove else { return false }

        for notation in candidates {
            if executeSAN(notation) {
                return true
            }
        }

        let legalMoves = enumerateLegalKitMoves()
        guard let matched = LegalMoveResolver.matchBest(candidates: candidates, among: legalMoves) else {
            return false
        }

        return applyLegalMove(matched)
    }

    @discardableResult
    func performMove(
        from: ChessPosition,
        to: ChessPosition,
        promotion: PieceType? = nil
    ) -> Bool {
        guard isAtLatestMove else { return false }

        let start = ChessKitMapping.kitSquare(from: from)
        let end = ChessKitMapping.kitSquare(from: to)
        guard let piece = pieceAt(from) else { return false }

        guard var kitMove = kitBoard.move(pieceAt: start, to: end) else {
            return false
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = ChessKitMapping.kitKind(promotion ?? .queen)
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return finalizeMove(kitMove, animatedPiece: piece)
    }

    func legalDestinations(from: ChessPosition) -> [ChessPosition] {
        let square = ChessKitMapping.kitSquare(from: from)
        return kitBoard.legalMoves(forPieceAt: square).map {
            ChessKitMapping.appPosition(from: $0)
        }
    }

    func requiresPromotion(from: ChessPosition, to: ChessPosition) -> Bool {
        guard let piece = pieceAt(from), piece.type == .pawn else { return false }
        let promotionRank = piece.color == .white ? 7 : 0
        guard to.rank == promotionRank else { return false }
        let start = ChessKitMapping.kitSquare(from: from)
        let end = ChessKitMapping.kitSquare(from: to)
        return kitBoard.canMove(pieceAt: start, to: end)
    }

    func clearMoveAnimation(id: UUID) {
        guard activeMoveAnimation?.id == id else { return }
        activeMoveAnimation = nil
    }

    func resetGame() {
        kitBoard = Board()
        kitGame = ChessKit.Game()
        currentIndex = kitGame.startingIndex
        moves = []
        gameResult = .ongoing
        activePlyIndex = 0
        activeMoveAnimation = nil
        syncBoardFromKit()
    }

    var isAtLatestMove: Bool {
        currentIndex == kitGame.moves.endIndex
    }

    var canGoBack: Bool {
        kitGame.moves.hasIndex(before: currentIndex)
    }

    var canGoForward: Bool {
        kitGame.moves.hasIndex(after: currentIndex)
    }

    var canUndo: Bool {
        isAtLatestMove && !moves.isEmpty
    }

    @discardableResult
    func goToPreviousPosition() -> Bool {
        guard canGoBack else { return false }
        navigateTo(index: kitGame.moves.index(before: currentIndex))
        return true
    }

    @discardableResult
    func goToNextPosition() -> Bool {
        guard canGoForward else { return false }
        navigateTo(index: kitGame.moves.index(after: currentIndex))
        return true
    }

    @discardableResult
    func goToLatestPosition() -> Bool {
        guard !isAtLatestMove else { return false }
        navigateTo(index: kitGame.moves.endIndex)
        return true
    }

    func undoLastMove() -> Bool {
        guard canUndo else { return false }
        return replayMainLine(Array(moves.dropLast().map(\.san)))
    }

    var isGameOver: Bool {
        gameResult != .ongoing
    }

    var gameStatusMessage: String? {
        switch kitBoard.state {
        case .checkmate(let color):
            let winner = color == .black ? "White" : "Black"
            return "Checkmate — \(winner) wins"
        case .draw(let reason):
            return ChessKitMapping.drawStatusMessage(for: reason)
        default:
            return nil
        }
    }

    private func navigateTo(index: MoveTree.Index) {
        guard let position = kitGame.positions[index] else { return }

        currentIndex = index
        kitBoard.update(position: position, resetPositionCounts: true)
        activeMoveAnimation = nil
        syncBoardFromKit()
        refreshActivePlyIndex()
    }

    @discardableResult
    private func replayMainLine(_ sans: [String]) -> Bool {
        kitBoard = Board()
        kitGame = ChessKit.Game()
        currentIndex = kitGame.startingIndex
        moves = []
        gameResult = .ongoing
        activeMoveAnimation = nil
        syncBoardFromKit()
        activePlyIndex = 0

        for san in sans {
            guard applyReplaySAN(san) else {
                resetGame()
                return false
            }
        }
        return true
    }

    @discardableResult
    private func applyReplaySAN(_ notation: String) -> Bool {
        if let coordinateMove = ChessKitMapping.parseCoordinateMove(notation) {
            if applyReplayMove(
                from: coordinateMove.from,
                to: coordinateMove.to,
                promotion: coordinateMove.promotion
            ) {
                return true
            }
            return executeLegalMatchForReplay(notation: notation)
        }

        let normalized = ChessKitMapping.normalizeSAN(notation)
        let position = kitBoard.position

        if let parsed = Move(san: normalized, position: position)
            ?? (ChessKitMapping.isPawnFileCaptureSAN(normalized)
                ? nil
                : Move(san: normalized.uppercased(), position: position)),
           applyParsedMoveForReplay(parsed) {
            return true
        }

        return executeLegalMatchForReplay(notation: notation)
    }

    @discardableResult
    private func applyReplayMove(
        from: ChessPosition,
        to: ChessPosition,
        promotion: PieceType? = nil
    ) -> Bool {
        let start = ChessKitMapping.kitSquare(from: from)
        let end = ChessKitMapping.kitSquare(from: to)
        guard pieceAt(from) != nil else { return false }

        guard var kitMove = kitBoard.move(pieceAt: start, to: end) else {
            return false
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = ChessKitMapping.kitKind(promotion ?? .queen)
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return commitReplayMove(kitMove)
    }

    @discardableResult
    private func applyParsedMoveForReplay(_ parsed: Move) -> Bool {
        let from = ChessKitMapping.appPosition(from: parsed.start)
        guard pieceAt(from) != nil else { return false }

        guard var kitMove = kitBoard.move(pieceAt: parsed.start, to: parsed.end) else {
            return false
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = parsed.promotedPiece?.kind ?? .queen
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return commitReplayMove(kitMove)
    }

    @discardableResult
    private func executeLegalMatchForReplay(notation: String) -> Bool {
        let legalMoves = enumerateLegalKitMoves()
        guard let matched = LegalMoveResolver.match(notation: notation, among: legalMoves) else {
            return false
        }
        return applyParsedMoveForReplay(matched)
    }

    @discardableResult
    private func commitReplayMove(_ kitMove: Move) -> Bool {
        currentIndex = kitGame.make(move: kitMove, from: currentIndex)
        moves.append(ChessKitMapping.appMove(from: kitMove))
        syncBoardFromKit()
        refreshActivePlyIndex()
        return true
    }

    private func refreshActivePlyIndex() {
        var count = 0
        var index = kitGame.startingIndex
        while index != currentIndex {
            guard kitGame.moves.hasIndex(after: index) else { break }
            index = kitGame.moves.index(after: index)
            count += 1
        }
        activePlyIndex = count
    }

    func fen() -> String {
        kitBoard.position.fen
    }

    /// FEN strings after each move on the main line, in order.
    func fensAfterMoves() -> [String] {
        var fens: [String] = []
        var index = kitGame.startingIndex

        while index != currentIndex {
            let next = index.next
            guard let position = kitGame.positions[next] else { break }
            fens.append(position.fen)
            index = next
        }

        return fens
    }

    /// Starting position followed by each position after a move — used for phase detection.
    func fenSequenceFromStart() -> [String] {
        guard let startFEN = kitGame.positions[kitGame.startingIndex]?.fen else {
            return [fen()]
        }
        return [startFEN] + fensAfterMoves()
    }

    // MARK: - ChessKit integration

    @discardableResult
    private func executeLegalMatch(notation: String) -> Bool {
        let legalMoves = enumerateLegalKitMoves()
        guard let matched = LegalMoveResolver.match(notation: notation, among: legalMoves) else {
            return false
        }
        return applyLegalMove(matched)
    }

    @discardableResult
    private func applyLegalMove(_ move: Move) -> Bool {
        performMove(
            from: ChessKitMapping.appPosition(from: move.start),
            to: ChessKitMapping.appPosition(from: move.end),
            promotion: move.promotedPiece.map { ChessKitMapping.appPieceType($0.kind) }
        )
    }

    private func enumerateLegalKitMoves() -> [Move] {
        var moves: [Move] = []
        let side = kitBoard.position.sideToMove

        for piece in kitBoard.position.pieces where piece.color == side {
            let start = piece.square
            for end in kitBoard.legalMoves(forPieceAt: start) {
                var trialBoard = kitBoard
                guard let move = trialBoard.move(pieceAt: start, to: end) else { continue }

                if case .promotion = trialBoard.state {
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

    private func applyParsedMove(_ parsed: Move) -> Bool {
        let from = ChessKitMapping.appPosition(from: parsed.start)
        guard let piece = pieceAt(from) else { return false }

        guard var kitMove = kitBoard.move(pieceAt: parsed.start, to: parsed.end) else {
            return false
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = parsed.promotedPiece?.kind ?? .queen
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return finalizeMove(kitMove, animatedPiece: piece)
    }

    private func finalizeMove(_ kitMove: Move, animatedPiece: ChessPiece) -> Bool {
        guard isAtLatestMove else { return false }

        currentIndex = kitGame.make(move: kitMove, from: currentIndex)
        moves.append(ChessKitMapping.appMove(from: kitMove))
        syncBoardFromKit()
        refreshActivePlyIndex()
        setAnimation(for: kitMove, piece: animatedPiece)
        return true
    }

    private func syncBoardFromKit() {
        for file in 0..<8 {
            for rank in 0..<8 {
                board[file][rank] = nil
            }
        }

        for piece in kitBoard.position.pieces {
            let position = ChessKitMapping.appPosition(from: piece.square)
            board[position.file][position.rank] = ChessKitMapping.appPiece(from: piece)
        }

        currentTurn = ChessKitMapping.appColor(kitBoard.position.sideToMove)
        gameResult = ChessKitMapping.pgnResult(from: kitBoard.state) ?? .ongoing
    }

    private func setAnimation(for move: Move, piece: ChessPiece) {
        let from = ChessKitMapping.appPosition(from: move.start)
        let to = ChessKitMapping.appPosition(from: move.end)

        var secondary: AnimatedPieceMove?
        if case .castle(let castling) = move.result {
            if let rook = kitBoard.position.piece(at: castling.rookEnd) {
                secondary = AnimatedPieceMove(
                    piece: ChessKitMapping.appPiece(from: rook),
                    from: ChessKitMapping.appPosition(from: castling.rookStart),
                    to: ChessKitMapping.appPosition(from: castling.rookEnd)
                )
            }
        }

        activeMoveAnimation = ActiveMoveAnimation(
            id: UUID(),
            primary: AnimatedPieceMove(piece: piece, from: from, to: to),
            secondary: secondary
        )
    }
}
