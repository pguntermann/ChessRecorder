//
//  OpeningService.swift
//  Chess Recorder
//

import ChessKit
import Foundation
import UIKit

struct OpeningDisplay: Equatable, Hashable {
    var eco: String
    var name: String

    static let starting = OpeningDisplay(eco: "A00", name: "Starting Position")
    static let unknown = OpeningDisplay(eco: "A00", name: "Unknown Opening")

    var label: String {
        "\(eco) · \(name)"
    }
}

/// A book continuation from a position: one legal move that lands on another known opening.
struct OpeningBookContinuation: Identifiable, Equatable, Hashable {
    let san: String
    let from: ChessPosition
    let to: ChessPosition
    let display: OpeningDisplay
    let fenAfter: String

    var id: String { fenAfter + "|" + san }
}

/// Gap where the played line left the opening book before rejoining at a later step.
struct OpeningBookOutOfBookGap: Equatable, Hashable {
    /// Number of plies that were outside the book.
    let plyCount: Int
    let startFullMoveNumber: Int
    let startIsWhiteMove: Bool
    let endFullMoveNumber: Int
    let endIsWhiteMove: Bool
    let firstSAN: String?
    let lastSAN: String?

    var startMoveLabel: String {
        Self.moveLabel(fullMove: startFullMoveNumber, isWhite: startIsWhiteMove)
    }

    var endMoveLabel: String {
        Self.moveLabel(fullMove: endFullMoveNumber, isWhite: endIsWhiteMove)
    }

    var summary: String {
        if plyCount <= 1 {
            if let firstSAN {
                return "Out of book · \(startMoveLabel) \(firstSAN)"
            }
            return "Out of book · \(startMoveLabel)"
        }
        if let firstSAN, let lastSAN {
            return "Out of book · \(startMoveLabel) \(firstSAN) … \(endMoveLabel) \(lastSAN)"
        }
        return "Out of book · \(startMoveLabel)–\(endMoveLabel) (\(plyCount) moves)"
    }

    static func moveLabel(fullMove: Int, isWhite: Bool) -> String {
        isWhite ? "\(fullMove)." : "\(fullMove)..."
    }
}

/// One step in the played opening progression up to the current position.
struct OpeningBookPathStep: Identifiable, Equatable, Hashable {
    /// Move that reached this opening label; `nil` for the starting position.
    let moveSAN: String?
    let display: OpeningDisplay
    let fen: String
    /// Squares of `moveSAN` for mini-board highlighting; `nil` at the start.
    let moveFrom: ChessPosition?
    let moveTo: ChessPosition?
    /// Full-move number of `moveSAN` (1-based); `nil` at the start.
    let fullMoveNumber: Int?
    /// Whether `moveSAN` was played by White; `nil` at the start.
    let isWhiteMove: Bool?
    /// When non-nil, the line left the book for these plies immediately before this step.
    let gapBefore: OpeningBookOutOfBookGap?

    var id: String {
        "\(fen)|\(moveSAN ?? "")|\(display.label)|\(fullMoveNumber.map(String.init) ?? "0")|\(gapBefore?.plyCount ?? 0)"
    }

    var moveNumberLabel: String? {
        guard let fullMoveNumber, let isWhiteMove else { return nil }
        return OpeningBookOutOfBookGap.moveLabel(fullMove: fullMoveNumber, isWhite: isWhiteMove)
    }

    init(
        moveSAN: String?,
        display: OpeningDisplay,
        fen: String,
        moveFrom: ChessPosition? = nil,
        moveTo: ChessPosition? = nil,
        fullMoveNumber: Int? = nil,
        isWhiteMove: Bool? = nil,
        gapBefore: OpeningBookOutOfBookGap? = nil
    ) {
        self.moveSAN = moveSAN
        self.display = display
        self.fen = fen
        self.moveFrom = moveFrom
        self.moveTo = moveTo
        self.fullMoveNumber = fullMoveNumber
        self.isWhiteMove = isWhiteMove
        self.gapBefore = gapBefore
    }
}

private struct EcoEntry: Decodable {
    let eco: String?
    let name: String?
}

private enum OpeningDataLoader {
    private final class BundleToken {}

    static func load() -> (base: [String: EcoEntry], interpolated: [String: EcoEntry]) {
        let decoder = JSONDecoder()
        return (
            base: loadDatabase(named: "eco_base", decoder: decoder),
            interpolated: loadDatabase(named: "eco_interpolated", decoder: decoder)
        )
    }

    private static func loadDatabase(named name: String, decoder: JSONDecoder) -> [String: EcoEntry] {
        // Bundle.main can be the test bundle under XCTest; use the app module bundle instead.
        let bundle = Bundle(for: BundleToken.self)
        guard let asset = NSDataAsset(name: name, bundle: bundle),
              let database = try? decoder.decode([String: EcoEntry].self, from: asset.data) else {
            return [:]
        }
        return database
    }
}

@Observable
@MainActor
final class OpeningService {
    static let maxContinuationsPerNode = 12
    static let maxTreeDepth = 8

    /// Common first / reply moves shown before rarer book sidelines.
    private static let preferredMoveOrder: [String: Int] = {
        let preferred = [
            "e4", "d4", "Nf3", "c4", "g3", "b3", "f4", "Nc3", "e3", "d3", "c3",
            "e5", "c5", "e6", "c6", "d5", "d6", "Nf6", "g6", "Nc6", "a6", "b6", "f5"
        ]
        return Dictionary(uniqueKeysWithValues: preferred.enumerated().map { ($1, $0) })
    }()

    private(set) var isLoaded = false
    private(set) var display = OpeningDisplay.starting
    /// True when the currently displayed board position is still a known book position.
    private(set) var isInBook = true
    /// FEN of the current board position when `isInBook`; otherwise nil.
    private(set) var currentBookFEN: String?
    /// Opening labels encountered along the played line up to the current position.
    private(set) var pathToCurrent: [OpeningBookPathStep] = [
        OpeningBookPathStep(moveSAN: nil, display: .starting, fen: Position.standard.fen)
    ]

    private var ecoBase: [String: EcoEntry] = [:]
    private var ecoInterpolated: [String: EcoEntry] = [:]
    /// Openings keyed by placement + side-to-move (ignores en passant / clocks).
    private var openingsByBookKey: [String: EcoEntry] = [:]

    /// Number of indexed book positions (for tests / diagnostics).
    var indexedBookPositionCount: Int {
        openingsByBookKey.count
    }

    func prepare() async {
        guard !isLoaded else { return }

        // Load on a background task that still resolves the app bundle via BundleToken.
        let loaded = await Task.detached(priority: .userInitiated) {
            OpeningDataLoader.load()
        }.value

        ecoBase = loaded.base
        ecoInterpolated = loaded.interpolated

        var indexed: [String: EcoEntry] = [:]
        for (fen, entry) in ecoBase {
            indexed[Self.bookKey(for: fen)] = entry
        }
        for (fen, entry) in ecoInterpolated {
            indexed[Self.bookKey(for: fen)] = entry
        }
        openingsByBookKey = indexed
        isLoaded = true
    }

    func refresh(game: ChessGame) {
        guard isLoaded else { return }

        let fen = game.fen()
        let path = buildPath(to: game)
        pathToCurrent = path

        if game.moves.isEmpty {
            display = .starting
            isInBook = true
            currentBookFEN = fen
            return
        }

        display = path.last?.display ?? openingDisplay(forFens: game.fensAfterMoves()) ?? .unknown
        if let match = lookupOpening(fen: fen) {
            display = match
            isInBook = true
            currentBookFEN = fen
        } else {
            isInBook = false
            currentBookFEN = nil
        }
    }

    /// Builds the sequence of distinct opening labels reached along the main line to `game`'s current ply.
    /// Out-of-book stretches are recorded as `gapBefore` on the step that rejoins the book.
    func buildPath(to game: ChessGame) -> [OpeningBookPathStep] {
        guard isLoaded else { return [] }

        let fens = game.fenSequenceFromStart()
        let moves = Array(game.moves.prefix(max(fens.count - 1, 0)))
        var steps: [OpeningBookPathStep] = []
        var lastDisplay: OpeningDisplay?
        /// First fen index that left the book since the last in-book position.
        var outOfBookStartIndex: Int?

        for (index, fen) in fens.enumerated() {
            let match: OpeningDisplay?
            if index == 0 {
                match = lookupOpening(fen: fen) ?? .starting
            } else {
                match = lookupOpening(fen: fen)
            }

            guard let match else {
                if outOfBookStartIndex == nil, index > 0 {
                    outOfBookStartIndex = index
                }
                continue
            }

            let gapBefore: OpeningBookOutOfBookGap?
            if let gapStart = outOfBookStartIndex, gapStart <= index - 1 {
                gapBefore = Self.outOfBookGap(
                    fromPlyIndex: gapStart,
                    toPlyIndex: index - 1,
                    moves: moves
                )
            } else {
                gapBefore = nil
            }
            outOfBookStartIndex = nil

            // Collapse consecutive identical labels, but always keep a step after leaving the book.
            if match == lastDisplay, gapBefore == nil {
                continue
            }

            let moveSAN: String?
            let moveFrom: ChessPosition?
            let moveTo: ChessPosition?
            let fullMoveNumber: Int?
            let isWhiteMove: Bool?
            if index == 0 {
                moveSAN = nil
                moveFrom = nil
                moveTo = nil
                fullMoveNumber = nil
                isWhiteMove = nil
            } else if index - 1 < moves.count {
                let move = moves[index - 1]
                moveSAN = move.san
                moveFrom = move.from
                moveTo = move.to
                fullMoveNumber = (index + 1) / 2
                isWhiteMove = index % 2 == 1
            } else {
                moveSAN = nil
                moveFrom = nil
                moveTo = nil
                fullMoveNumber = nil
                isWhiteMove = nil
            }

            steps.append(
                OpeningBookPathStep(
                    moveSAN: moveSAN,
                    display: match,
                    fen: fen,
                    moveFrom: moveFrom,
                    moveTo: moveTo,
                    fullMoveNumber: fullMoveNumber,
                    isWhiteMove: isWhiteMove,
                    gapBefore: gapBefore
                )
            )
            lastDisplay = match
        }

        if steps.isEmpty {
            steps = [OpeningBookPathStep(moveSAN: nil, display: .starting, fen: fens.first ?? fenFallback)]
        }
        return steps
    }

    /// `plyIndex` is the fen-sequence index after that ply (1 = after White's first move).
    private static func outOfBookGap(
        fromPlyIndex: Int,
        toPlyIndex: Int,
        moves: [ChessMove]
    ) -> OpeningBookOutOfBookGap {
        let start = max(fromPlyIndex, 1)
        let end = max(toPlyIndex, start)
        let firstMoveIndex = start - 1
        let lastMoveIndex = end - 1
        return OpeningBookOutOfBookGap(
            plyCount: end - start + 1,
            startFullMoveNumber: (start + 1) / 2,
            startIsWhiteMove: start % 2 == 1,
            endFullMoveNumber: (end + 1) / 2,
            endIsWhiteMove: end % 2 == 1,
            firstSAN: moves.indices.contains(firstMoveIndex) ? moves[firstMoveIndex].san : nil,
            lastSAN: moves.indices.contains(lastMoveIndex) ? moves[lastMoveIndex].san : nil
        )
    }

    private var fenFallback: String {
        Position.standard.fen
    }

    func opening(for moves: [ChessMove]) -> OpeningDisplay? {
        guard isLoaded, !moves.isEmpty else { return nil }

        let replayGame = ChessGame()
        guard replayGame.loadMainLine(moves: moves) else { return nil }
        return openingDisplay(forFens: replayGame.fensAfterMoves())
    }

    func ecoCode(for moves: [ChessMove]) -> String? {
        opening(for: moves)?.eco
    }

    func ecoCode(for game: ChessGame) -> String? {
        guard isLoaded, !game.moves.isEmpty else { return nil }
        return openingDisplay(forFens: game.fensAfterMoves())?.eco
    }

    /// True when the position after a move is a known opening/book position.
    func isBookPosition(fen: String) -> Bool {
        guard isLoaded else { return false }
        return openingsByBookKey[Self.bookKey(for: fen)] != nil
            || ecoInterpolated[fen] != nil
            || ecoBase[fen] != nil
    }

    func opening(forFEN fen: String) -> OpeningDisplay? {
        lookupOpening(fen: fen)
    }

    /// Legal moves from `fen` that land on another known book position, capped for UI.
    func continuations(
        from fen: String,
        limit: Int = OpeningService.maxContinuationsPerNode
    ) -> [OpeningBookContinuation] {
        guard isLoaded, let position = Position(fen: fen) else { return [] }

        var results: [OpeningBookContinuation] = []
        let board = Board(position: position)
        let side = board.position.sideToMove

        for piece in board.position.pieces where piece.color == side {
            let start = piece.square
            for end in board.legalMoves(forPieceAt: start) {
                var trial = board
                guard let move = trial.move(pieceAt: start, to: end) else { continue }

                if case .promotion = trial.state {
                    for kind in [Piece.Kind.queen, .rook, .bishop, .knight] {
                        var promotionBoard = board
                        guard promotionBoard.move(pieceAt: start, to: end) != nil else { continue }
                        guard case .promotion(let promotionMove) = promotionBoard.state else { continue }
                        let completed = promotionBoard.completePromotion(of: promotionMove, to: kind)
                        if let continuation = bookContinuation(after: completed, on: promotionBoard) {
                            results.append(continuation)
                        }
                    }
                } else {
                    if let continuation = bookContinuation(after: move, on: trial) {
                        results.append(continuation)
                    }
                }
            }
        }

        return Array(
            results
                .sorted { lhs, rhs in
                    let leftRank = Self.preferredMoveOrder[Self.normalizedSAN(lhs.san)] ?? Int.max
                    let rightRank = Self.preferredMoveOrder[Self.normalizedSAN(rhs.san)] ?? Int.max
                    if leftRank != rightRank {
                        return leftRank < rightRank
                    }
                    if lhs.display.eco != rhs.display.eco {
                        return lhs.display.eco < rhs.display.eco
                    }
                    return lhs.san < rhs.san
                }
                .prefix(max(limit, 0))
        )
    }

    private static func normalizedSAN(_ san: String) -> String {
        san.trimmingCharacters(in: CharacterSet(charactersIn: "+#"))
    }

    private func bookContinuation(after move: Move, on board: Board) -> OpeningBookContinuation? {
        let fenAfter = board.position.fen
        guard let display = lookupOpening(fen: fenAfter) else { return nil }
        return OpeningBookContinuation(
            san: move.san,
            from: ChessKitMapping.appPosition(from: move.start),
            to: ChessKitMapping.appPosition(from: move.end),
            display: display,
            fenAfter: fenAfter
        )
    }

    private func openingDisplay(forFens fens: [String]) -> OpeningDisplay? {
        var lastKnown: OpeningDisplay?
        for fen in fens {
            if let match = lookupOpening(fen: fen) {
                lastKnown = match
            }
        }
        return lastKnown
    }

    private func lookupOpening(fen: String) -> OpeningDisplay? {
        if let entry = ecoInterpolated[fen] ?? ecoBase[fen] {
            return display(from: entry)
        }
        return openingsByBookKey[Self.bookKey(for: fen)].flatMap(display(from:))
    }

    private func display(from entry: EcoEntry) -> OpeningDisplay? {
        guard let eco = entry.eco,
              let name = entry.name,
              !eco.isEmpty,
              !name.isEmpty else {
            return nil
        }
        return OpeningDisplay(eco: eco, name: name)
    }

    /// Placement + side-to-move, ignoring en passant and clocks.
    private static func bookKey(for fen: String) -> String {
        let fields = fen.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return fen }
        return "\(fields[0]) \(fields[1])"
    }
}
