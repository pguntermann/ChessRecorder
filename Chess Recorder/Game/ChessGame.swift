//
//  ChessGame.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import ChessKit
import Foundation

nonisolated enum PieceType: String, Sendable {
    case pawn = ""
    case knight = "N"
    case bishop = "B"
    case rook = "R"
    case queen = "Q"
    case king = "K"
}

nonisolated enum PieceColor: Sendable {
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

nonisolated struct ChessPosition: Equatable, Hashable, Sendable {
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

nonisolated struct ChessMove: Sendable {
    let san: String
    let piece: PieceType
    let from: ChessPosition
    let to: ChessPosition
    let captures: Bool
    let isCheck: Bool
    let isCheckmate: Bool
    let promotion: PieceType?
    let castling: String?
    let quality: MoveQuality?
    /// Centipawn loss vs best move for this ply (nil for book / unassessed / legacy).
    let centipawnLoss: Int?
    /// White-perspective evaluation after this move, in centipawns.
    /// Forced mates use ±(1000 + mate-in-N); delivered mate is ±1000 (chart edge ±10 pawns).
    let evaluationWhiteCentipawns: Int?
    /// Engine best move (SAN) from the position before this ply was played.
    let bestMoveSAN: String?

    var algebraicNotation: String { san }

    init(
        san: String,
        piece: PieceType,
        from: ChessPosition,
        to: ChessPosition,
        captures: Bool,
        isCheck: Bool,
        isCheckmate: Bool,
        promotion: PieceType?,
        castling: String?,
        quality: MoveQuality? = nil,
        centipawnLoss: Int? = nil,
        evaluationWhiteCentipawns: Int? = nil,
        bestMoveSAN: String? = nil
    ) {
        self.san = san
        self.piece = piece
        self.from = from
        self.to = to
        self.captures = captures
        self.isCheck = isCheck
        self.isCheckmate = isCheckmate
        self.promotion = promotion
        self.castling = castling
        self.quality = quality
        self.centipawnLoss = centipawnLoss
        self.evaluationWhiteCentipawns = evaluationWhiteCentipawns
        self.bestMoveSAN = bestMoveSAN
    }

    func matchesPositionally(_ other: ChessMove) -> Bool {
        // Compare squares/piece only — SAN may be rewritten when disambiguation is repaired.
        from == other.from
            && to == other.to
            && piece == other.piece
            && promotion == other.promotion
            && castling == other.castling
    }

    func withQuality(
        _ quality: MoveQuality?,
        centipawnLoss: Int? = nil,
        evaluationWhiteCentipawns: Int? = nil,
        bestMoveSAN: String? = nil
    ) -> ChessMove {
        ChessMove(
            san: san,
            piece: piece,
            from: from,
            to: to,
            captures: captures,
            isCheck: isCheck,
            isCheckmate: isCheckmate,
            promotion: promotion,
            castling: castling,
            quality: quality,
            centipawnLoss: centipawnLoss,
            evaluationWhiteCentipawns: evaluationWhiteCentipawns,
            bestMoveSAN: bestMoveSAN
        )
    }
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

struct TakebackAnimation: Equatable {
    let id: UUID
    let primary: AnimatedPieceMove
    let secondary: AnimatedPieceMove?
    let fadeInPieces: [AnimatedPieceMove]
}

@Observable
class ChessGame {
    private(set) var board: [[ChessPiece?]]
    private(set) var currentTurn: PieceColor = .white
    private(set) var moves: [ChessMove] = []
    private(set) var gameResult: PGNResult = .ongoing
    /// User-declared result (resignation/agreement) that persists across board syncs.
    @ObservationIgnored private var declaredResult: PGNResult?
    /// Terminal overlay text that persists when reviewing move history.
    @ObservationIgnored private var statusMessageOverride: String?
    /// Half-move count from the starting position to the viewed position (0 = start).
    private(set) var activePlyIndex: Int = 0
    var activeMoveAnimation: ActiveMoveAnimation?
    var activeTakebackAnimation: TakebackAnimation?

    @ObservationIgnored private var kitBoard: Board
    @ObservationIgnored private var kitGame: ChessKit.Game
    @ObservationIgnored private var currentIndex: MoveTree.Index
    @ObservationIgnored private var cachedLegalKitMoves: [Move]?

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

        if LegalMoveResolver.requiresExplicitSourceMatch(notation) {
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
    /// Returns the notation that matched, if any.
    @discardableResult
    func executeVoiceCandidates(_ candidates: [String], preferCaptures: Bool = false) -> String? {
        guard isAtLatestMove else { return nil }

        let legalMoves = enumerateLegalKitMoves()
        guard let matched = LegalMoveResolver.matchBest(
            candidates: candidates,
            among: legalMoves,
            preferCaptures: preferCaptures
        ) else {
            return nil
        }

        guard applyLegalMove(matched) else { return nil }
        return moves.last?.san
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

        let legalMoves = enumerateLegalKitMoves()
        guard var kitMove = kitBoard.move(pieceAt: start, to: end) else {
            return false
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = ChessKitMapping.kitKind(promotion ?? .queen)
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return finalizeMove(kitMove, animatedPiece: piece, legalMovesForDisambiguation: legalMoves)
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

    func clearTakebackAnimation(id: UUID) {
        guard activeTakebackAnimation?.id == id else { return }
        activeTakebackAnimation = nil
    }

    func resetGame() {
        kitBoard = Board()
        kitGame = ChessKit.Game()
        currentIndex = kitGame.startingIndex
        moves = []
        declaredResult = nil
        statusMessageOverride = nil
        gameResult = .ongoing
        activePlyIndex = 0
        activeMoveAnimation = nil
        activeTakebackAnimation = nil
        invalidateLegalMovesCache()
        syncBoardFromKit()
    }

    func declareResult(_ result: PGNResult) {
        guard result != .ongoing else { return }
        declaredResult = result
        gameResult = result
        statusMessageOverride = Self.declaredResultStatusMessage(for: result)
    }

    var isAtLatestMove: Bool {
        activePlyIndex >= moves.count
    }

    /// The move that led to the currently viewed position, if any.
    var moveAtActivePly: ChessMove? {
        guard activePlyIndex > 0, activePlyIndex <= moves.count else { return nil }
        return moves[activePlyIndex - 1]
    }

    var canGoBack: Bool {
        activePlyIndex > 0
    }

    var canGoForward: Bool {
        activePlyIndex < moves.count
    }

    var canGoToFirst: Bool {
        activePlyIndex > 0
    }

    var canGoToLatest: Bool {
        activePlyIndex < moves.count
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

    @discardableResult
    func goToFirstPosition() -> Bool {
        guard canGoToFirst else { return false }
        navigateTo(index: kitGame.startingIndex)
        return true
    }

    @discardableResult
    func goToPlyIndex(_ plyIndex: Int) -> Bool {
        guard plyIndex >= 0, plyIndex <= moves.count else { return false }

        var index = kitGame.startingIndex
        for _ in 0..<plyIndex {
            guard kitGame.moves.hasIndex(after: index) else { return false }
            index = kitGame.moves.index(after: index)
        }

        guard index != currentIndex else { return false }
        navigateTo(index: index)
        return true
    }

    func undoLastMove() -> Bool {
        guard canUndo else { return false }
        return truncateLastMainLineMove()
    }

    @discardableResult
    func loadMainLine(moves recordedMoves: [ChessMove]) -> Bool {
        if recordedMoves.isEmpty {
            resetGame()
            return true
        }
        return replayMainLine(recordedMoves)
    }

    /// Clears quality / CPL / eval on every ply (e.g. after a developer purge).
    func clearMoveAssessments() {
        guard moves.contains(where: {
            $0.quality != nil
                || $0.centipawnLoss != nil
                || $0.evaluationWhiteCentipawns != nil
                || $0.bestMoveSAN != nil
        }) else { return }
        moves = moves.map {
            $0.withQuality(nil, centipawnLoss: nil, evaluationWhiteCentipawns: nil, bestMoveSAN: nil)
        }
    }

    /// Builds a fully replayed game for staged archive activation (MainActor convenience).
    static func prepared(from moves: [ChessMove], result: PGNResult = .ongoing) -> ChessGame {
        let prepared = ChessGame()
        prepared.applyPreparedTransfer(ChessGameBackgroundPreparation.prepareTransfer(from: moves, result: result))
        return prepared
    }

    /// Applies a transfer produced by off-main `ChessGameBackgroundPreparation` (cheap snapshot restore).
    func applyPreparedTransfer(_ transfer: ChessGameBackgroundPreparation.Transfer) {
        restoreSnapshot(
            GameSnapshot(
                kitBoard: transfer.kitBoard,
                kitGame: transfer.kitGame,
                currentIndex: transfer.currentIndex,
                moves: transfer.moves,
                declaredResult: transfer.declaredResult,
                statusMessageOverride: transfer.statusMessageOverride,
                gameResult: transfer.gameResult,
                activePlyIndex: transfer.activePlyIndex
            )
        )
    }

    /// Replaces this game's main line with another game's replayed state.
    func replaceMainLine(with source: ChessGame) {
        restoreSnapshot(source.captureSnapshot())
    }

    var isGameOver: Bool {
        gameResult != .ongoing
    }

    var gameStatusMessage: String? {
        if isGameOver, let statusMessageOverride {
            return statusMessageOverride
        }

        return Self.statusMessage(from: kitBoard.state)
    }

    private static func statusMessage(from state: Board.State) -> String? {
        switch state {
        case .checkmate(let color):
            let winner = color == .black ? "White" : "Black"
            return "Checkmate — \(winner) wins"
        case .draw(let reason):
            return ChessKitMapping.drawStatusMessage(for: reason)
        default:
            return nil
        }
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

    private func navigateTo(index: MoveTree.Index) {
        guard let position = kitGame.positions[index] else { return }

        currentIndex = index
        kitBoard.update(position: position, resetPositionCounts: true)
        activeMoveAnimation = nil
        activeTakebackAnimation = nil
        syncBoardFromKit()
        refreshActivePlyIndex()
    }

    @discardableResult
    private func replayMainLine(_ recordedMoves: [ChessMove]) -> Bool {
        let snapshot = captureSnapshot()
        resetForMainLineReplay()

        var rebuiltMoves: [ChessMove] = []
        rebuiltMoves.reserveCapacity(recordedMoves.count)

        for recordedMove in recordedMoves {
            guard let kitMove = makeReplayKitMove(for: recordedMove) else {
                restoreSnapshot(snapshot)
                return false
            }
            currentIndex = kitGame.make(move: kitMove, from: currentIndex)
            // Keep archived SAN + assessments; don't rebuild notation on every load/switch.
            rebuiltMoves.append(recordedMove)
        }

        moves = rebuiltMoves
        activePlyIndex = rebuiltMoves.count
        invalidateLegalMovesCache()
        syncBoardFromKit()
        return true
    }

    private func resetForMainLineReplay() {
        kitBoard = Board()
        kitGame = ChessKit.Game()
        currentIndex = kitGame.startingIndex
        moves = []
        declaredResult = nil
        statusMessageOverride = nil
        gameResult = .ongoing
        activeMoveAnimation = nil
        activeTakebackAnimation = nil
        invalidateLegalMovesCache()
        activePlyIndex = 0
    }

    private func makeReplayKitMove(for recordedMove: ChessMove) -> Move? {
        if let move = makeReplayKitMove(
            from: recordedMove.from,
            to: recordedMove.to,
            promotion: recordedMove.promotion
        ) {
            return move
        }
        return makeReplayKitMoveFromSAN(recordedMove.san)
    }

    private func makeReplayKitMove(
        from: ChessPosition,
        to: ChessPosition,
        promotion: PieceType?
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

    private func makeReplayKitMoveFromSAN(_ notation: String) -> Move? {
        if let coordinateMove = ChessKitMapping.parseCoordinateMove(notation),
           let move = makeReplayKitMove(
            from: coordinateMove.from,
            to: coordinateMove.to,
            promotion: coordinateMove.promotion
           ) {
            return move
        }

        if LegalMoveResolver.requiresExplicitSourceMatch(notation) {
            return makeReplayKitMoveViaLegalMatch(notation)
        }

        let normalized = ChessKitMapping.normalizeSAN(notation)
        let position = kitBoard.position

        if let parsed = Move(san: normalized, position: position)
            ?? (ChessKitMapping.isPawnFileCaptureSAN(normalized)
                ? nil
                : Move(san: normalized.uppercased(), position: position)),
           let move = applyKitMoveOnBoard(parsed) {
            return move
        }

        return makeReplayKitMoveViaLegalMatch(notation)
    }

    private func makeReplayKitMoveViaLegalMatch(_ notation: String) -> Move? {
        let legalMoves = enumerateLegalKitMoves()
        guard let matched = LegalMoveResolver.match(notation: notation, among: legalMoves) else {
            return nil
        }
        return applyKitMoveOnBoard(matched)
    }

    private func applyKitMoveOnBoard(_ parsed: Move) -> Move? {
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

    /// Removes the last main-line move by rebuilding a shorter ChessKit tree from stored `Move`s.
    @discardableResult
    private func truncateLastMainLineMove() -> Bool {
        guard canUndo else { return false }

        let mainLineMoves = mainLineKitMoves()
        guard mainLineMoves.count == moves.count, !mainLineMoves.isEmpty else { return false }

        let boardBeforeUndo = board
        guard let undoneChessMove = moves.last else { return false }
        let undoneKitMove = mainLineMoves.last
        let truncatedMoves = Array(mainLineMoves.dropLast())
        guard let rebuilt = makeKitGame(mainLineMoves: truncatedMoves) else { return false }

        kitGame = rebuilt.game
        currentIndex = rebuilt.endIndex
        moves.removeLast()

        guard let parentPosition = kitGame.positions[currentIndex] else { return false }
        kitBoard.update(position: parentPosition, resetPositionCounts: true)
        activeMoveAnimation = nil
        invalidateLegalMovesCache()

        if declaredResult == nil {
            statusMessageOverride = nil
        }

        syncBoardFromKit()
        refreshActivePlyIndex()

        if let undoneKitMove,
           let takebackAnimation = makeTakebackAnimation(
               undoneChessMove: undoneChessMove,
               undoneKitMove: undoneKitMove,
               boardBeforeUndo: boardBeforeUndo
           ) {
            activeTakebackAnimation = takebackAnimation
        }

        return true
    }

    private func makeTakebackAnimation(
        undoneChessMove: ChessMove,
        undoneKitMove: Move,
        boardBeforeUndo: [[ChessPiece?]]
    ) -> TakebackAnimation? {
        guard let movingPiece = boardBeforeUndo[undoneChessMove.to.file][undoneChessMove.to.rank] else {
            return nil
        }

        let primary = AnimatedPieceMove(
            piece: movingPiece,
            from: undoneChessMove.to,
            to: undoneChessMove.from
        )

        var secondary: AnimatedPieceMove?
        if case .castle(let castling) = undoneKitMove.result {
            let rookEnd = ChessKitMapping.appPosition(from: castling.rookEnd)
            let rookStart = ChessKitMapping.appPosition(from: castling.rookStart)
            if let rook = boardBeforeUndo[rookEnd.file][rookEnd.rank] {
                secondary = AnimatedPieceMove(piece: rook, from: rookEnd, to: rookStart)
            }
        }

        var fadeInPieces: [AnimatedPieceMove] = []

        if let restingMover = board[undoneChessMove.from.file][undoneChessMove.from.rank] {
            fadeInPieces.append(
                AnimatedPieceMove(piece: restingMover, from: undoneChessMove.from, to: undoneChessMove.from)
            )
        }

        if case .castle(let castling) = undoneKitMove.result {
            let rookStart = ChessKitMapping.appPosition(from: castling.rookStart)
            if let rook = board[rookStart.file][rookStart.rank] {
                fadeInPieces.append(
                    AnimatedPieceMove(piece: rook, from: rookStart, to: rookStart)
                )
            }
        }

        if case .capture(let capturedPiece) = undoneKitMove.result {
            let captureSquare = ChessKitMapping.appPosition(from: capturedPiece.square)
            if let restored = board[captureSquare.file][captureSquare.rank] {
                fadeInPieces.append(
                    AnimatedPieceMove(piece: restored, from: captureSquare, to: captureSquare)
                )
            }
        }

        return TakebackAnimation(
            id: UUID(),
            primary: primary,
            secondary: secondary,
            fadeInPieces: fadeInPieces
        )
    }

    private func mainLineKitMoves() -> [Move] {
        var kitMoves: [Move] = []
        var index = kitGame.startingIndex

        while kitGame.moves.hasIndex(after: index) {
            let next = kitGame.moves.index(after: index)
            guard let move = kitGame.moves[next] else { break }
            kitMoves.append(move)
            index = next
        }

        return kitMoves
    }

    private func makeKitGame(mainLineMoves: [Move]) -> (game: ChessKit.Game, endIndex: MoveTree.Index)? {
        let startPosition = kitGame.startingPosition ?? .standard
        var game = ChessKit.Game(startingWith: startPosition, tags: kitGame.tags)
        var index = game.startingIndex

        for move in mainLineMoves {
            index = game.make(move: move, from: index)
        }

        guard game.positions[index] != nil else { return nil }
        return (game, index)
    }

    private struct GameSnapshot {
        let kitBoard: Board
        let kitGame: ChessKit.Game
        let currentIndex: MoveTree.Index
        let moves: [ChessMove]
        let declaredResult: PGNResult?
        let statusMessageOverride: String?
        let gameResult: PGNResult
        let activePlyIndex: Int
    }

    private func captureSnapshot() -> GameSnapshot {
        GameSnapshot(
            kitBoard: kitBoard,
            kitGame: kitGame,
            currentIndex: currentIndex,
            moves: moves,
            declaredResult: declaredResult,
            statusMessageOverride: statusMessageOverride,
            gameResult: gameResult,
            activePlyIndex: activePlyIndex
        )
    }

    private func restoreSnapshot(_ snapshot: GameSnapshot) {
        kitBoard = snapshot.kitBoard
        kitGame = snapshot.kitGame
        currentIndex = snapshot.currentIndex
        moves = snapshot.moves
        declaredResult = snapshot.declaredResult
        statusMessageOverride = snapshot.statusMessageOverride
        gameResult = snapshot.gameResult
        activePlyIndex = snapshot.activePlyIndex
        activeMoveAnimation = nil
        activeTakebackAnimation = nil
        invalidateLegalMovesCache()
        syncBoardFromKit()
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

        if LegalMoveResolver.requiresExplicitSourceMatch(notation) {
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

        let legalMoves = enumerateLegalKitMoves()
        guard var kitMove = kitBoard.move(pieceAt: parsed.start, to: parsed.end) else {
            return false
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = parsed.promotedPiece?.kind ?? .queen
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return commitReplayMove(kitMove, legalMovesForDisambiguation: legalMoves)
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
    private func commitReplayMove(
        _ kitMove: Move,
        legalMovesForDisambiguation: [Move] = []
    ) -> Bool {
        currentIndex = kitGame.make(move: kitMove, from: currentIndex)
        moves.append(
            ChessKitMapping.appMove(
                from: kitMove,
                legalMovesForDisambiguation: legalMovesForDisambiguation
            )
        )
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
        if let cachedLegalKitMoves {
            return cachedLegalKitMoves
        }

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

        cachedLegalKitMoves = moves
        return moves
    }

    private func applyParsedMove(_ parsed: Move) -> Bool {
        let from = ChessKitMapping.appPosition(from: parsed.start)
        guard let piece = pieceAt(from) else { return false }

        let legalMoves = enumerateLegalKitMoves()
        guard var kitMove = kitBoard.move(pieceAt: parsed.start, to: parsed.end) else {
            return false
        }

        if case .promotion(let promoMove) = kitBoard.state {
            let kind = parsed.promotedPiece?.kind ?? .queen
            kitMove = kitBoard.completePromotion(of: promoMove, to: kind)
        }

        return finalizeMove(kitMove, animatedPiece: piece, legalMovesForDisambiguation: legalMoves)
    }

    private func finalizeMove(
        _ kitMove: Move,
        animatedPiece: ChessPiece,
        legalMovesForDisambiguation: [Move] = []
    ) -> Bool {
        guard isAtLatestMove else { return false }

        currentIndex = kitGame.make(move: kitMove, from: currentIndex)
        moves.append(
            ChessKitMapping.appMove(
                from: kitMove,
                legalMovesForDisambiguation: legalMovesForDisambiguation
            )
        )
        invalidateLegalMovesCache()
        syncBoardFromKit()
        refreshActivePlyIndex()
        setAnimation(for: kitMove, piece: animatedPiece)
        return true
    }

    private func invalidateLegalMovesCache() {
        cachedLegalKitMoves = nil
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

        guard currentIndex == kitGame.moves.endIndex else { return }

        if let declaredResult {
            gameResult = declaredResult
            return
        }

        if let detectedResult = ChessKitMapping.pgnResult(from: kitBoard.state) {
            gameResult = detectedResult
            if detectedResult.isFinal {
                statusMessageOverride = Self.statusMessage(from: kitBoard.state)
            }
            return
        }

        if !gameResult.isFinal {
            gameResult = .ongoing
        }
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
