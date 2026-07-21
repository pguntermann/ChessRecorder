//
//  GamePhaseClassifier.swift
//  Chess Recorder
//
//  CARA-inspired opening / middlegame / endgame detection from FENs + book exit.
//  Pure piece-count rules — no LucidEngine / Stockfish dependency.
//

import Foundation

enum GamePhaseKind: String, Equatable, Sendable {
    case opening = "Opening"
    case middlegame = "Middlegame"
    case endgame = "Endgame"
}

/// Specific endgame family from material (CARA rule set).
enum EndgameType: String, Equatable, Sendable {
    case pawn = "Pawn"
    case minorPiece = "Minor Piece"
    case twoMinorPiece = "Two Minor Piece"
    case rookPlusTwoMinor = "Rook + Two Minor Piece"
    case rookUnequalMinors = "Rook vs Rook (Unequal Minors)"
    case rookVsMinor = "Rook vs Minor Piece"
    case rook = "Rook"
    case doubleRook = "Double Rook"
    case rookPlusMinor = "Rook + Minor Piece"
    case heavyPiece = "Heavy Piece"
    case asymmetricHeavy = "Asymmetric Heavy Piece"
    case queen = "Queen"
    case queenPlusTwoMinor = "Queen + Two Minor Piece"
    case strongImbalance = "Strong Material Imbalance"
    case transitional = "Transitional"
    case generic = "Endgame"

    /// Full label for summary overview and related UI.
    var displayName: String { rawValue }

    /// Shorter board-chrome label — abbreviated from `displayName`, not a separate nickname.
    var shortDisplayName: String {
        switch self {
        case .pawn: return "Pawn"
        case .minorPiece: return "Minor Piece"
        case .twoMinorPiece: return "Two Minors"
        case .rookPlusTwoMinor: return "R+2 Minors"
        case .rookUnequalMinors: return "Unequal Minors"
        case .rookVsMinor: return "Rook vs Minor"
        case .rook: return "Rook"
        case .doubleRook: return "Double Rook"
        case .rookPlusMinor: return "Rook + Minor"
        case .heavyPiece: return "Heavy Piece"
        case .asymmetricHeavy: return "Asym. Heavy"
        case .queen: return "Queen"
        case .queenPlusTwoMinor: return "Queen + 2 Minors"
        case .strongImbalance: return "Mat. Imbalance"
        case .transitional: return "Transitional"
        case .generic: return "Endgame"
        }
    }
}

struct GamePhaseInfo: Equatable, Sendable {
    let kind: GamePhaseKind
    let endgameType: EndgameType?

    /// Trailing chrome capsule for every phase (including Opening) so row height stays stable
    /// when the opening-name setting is off.
    var bubbleText: String? {
        switch kind {
        case .opening:
            return GamePhaseKind.opening.rawValue
        case .middlegame:
            return GamePhaseKind.middlegame.rawValue
        case .endgame:
            guard let endgameType else { return GamePhaseKind.endgame.rawValue }
            if endgameType == .generic || endgameType == .transitional {
                return endgameType.shortDisplayName
            }
            return "\(GamePhaseKind.endgame.rawValue) · \(endgameType.shortDisplayName)"
        }
    }
}

struct GamePhaseBoundaries: Equatable, Sendable {
    /// First fen-sequence index that is middlegame (`nil` = never leaves opening).
    var middlegameStartPly: Int?
    /// First fen-sequence index that is endgame (`nil` = no endgame).
    var endgameStartPly: Int?

    static let empty = GamePhaseBoundaries(middlegameStartPly: nil, endgameStartPly: nil)
}

/// Side piece counts from a FEN placement (kings ignored for material).
struct PhasePieceCounts: Equatable, Sendable {
    var queens: Int = 0
    var rooks: Int = 0
    var bishops: Int = 0
    var knights: Int = 0
    var pawns: Int = 0

    var minors: Int { bishops + knights }
    var nonPawnMaterial: Int { queens * 9 + rooks * 5 + bishops * 3 + knights * 3 }
}

enum GamePhaseClassifier {
    /// Default opening length in plies (~15 full moves) when no non-pawn capture occurs.
    static let defaultOpeningPlies = 30

    /// Consecutive plies with the same endgame family before the phase cut (≈2 full moves).
    static let endgameStabilityPlies = 4

    // MARK: - Public API

    static func pieceCounts(fen: String) -> (white: PhasePieceCounts, black: PhasePieceCounts) {
        let placement = fen.prefix(while: { $0 != " " })
        var white = PhasePieceCounts()
        var black = PhasePieceCounts()
        for ch in placement {
            switch ch {
            case "Q": white.queens += 1
            case "q": black.queens += 1
            case "R": white.rooks += 1
            case "r": black.rooks += 1
            case "B": white.bishops += 1
            case "b": black.bishops += 1
            case "N": white.knights += 1
            case "n": black.knights += 1
            case "P": white.pawns += 1
            case "p": black.pawns += 1
            default: break
            }
        }
        return (white, black)
    }

    static func classifyEndgame(white: PhasePieceCounts, black: PhasePieceCounts) -> EndgameType? {
        let wQ = white.queens, wR = white.rooks, wB = white.bishops, wN = white.knights
        let bQ = black.queens, bR = black.rooks, bB = black.bishops, bN = black.knights
        let wMinors = white.minors, bMinors = black.minors
        let wNP = white.nonPawnMaterial, bNP = black.nonPawnMaterial

        if wQ == 0, wR == 0, wB == 0, wN == 0, bQ == 0, bR == 0, bB == 0, bN == 0 {
            return .pawn
        }
        if wQ == 0, wR == 0, bQ == 0, bR == 0,
           wMinors <= 1, bMinors <= 1, wNP <= 6, bNP <= 6 {
            return .minorPiece
        }
        if wQ == 0, wR == 0, bQ == 0, bR == 0,
           wMinors == 2, bMinors == 2, wNP <= 6, bNP <= 6 {
            return .twoMinorPiece
        }
        if wQ == 0, bQ == 0, wR == 1, bR == 1,
           wMinors == 2, bMinors == 2, wNP <= 11, bNP <= 11 {
            return .rookPlusTwoMinor
        }
        if wQ == 0, bQ == 0, wR == 1, bR == 1 {
            if wMinors == 2, bMinors == 1, wNP <= 14, bNP <= 10 { return .rookUnequalMinors }
            if wMinors == 1, bMinors == 2, wNP <= 10, bNP <= 14 { return .rookUnequalMinors }
        }
        if wQ == 0, bQ == 0,
           ((wR == 1 && bR == 0 && bMinors == 1 && wMinors == 0)
            || (bR == 1 && wR == 0 && wMinors == 1 && bMinors == 0)),
           wNP <= 8, bNP <= 8 {
            return .rookVsMinor
        }
        // More specific rook families before the general rook rule (NP ≤ 10 would absorb them).
        if wQ == 0, bQ == 0, wR == 2, bR == 2,
           wMinors <= 1, bMinors <= 1, wNP <= 15, bNP <= 15 {
            return .doubleRook
        }
        if wQ == 0, bQ == 0, (wR > 0 || bR > 0),
           wMinors <= 1, bMinors <= 1, wNP <= 13, bNP <= 13,
           wNP > 10 || bNP > 10 {
            return .rookPlusMinor
        }
        if wQ == 0, bQ == 0, (wR > 0 || bR > 0),
           wMinors <= 1, bMinors <= 1, wNP <= 10, bNP <= 10 {
            return .rook
        }
        if wQ > 0, bQ > 0, wR > 0, bR > 0,
           wMinors <= 1, bMinors <= 1, wMinors == bMinors,
           wNP <= 15, bNP <= 15 {
            return .heavyPiece
        }
        if wQ > 0, bQ > 0, wMinors <= 1, bMinors <= 1 {
            if wR > 0, bR > 0,
               (wMinors == 0 && bMinors <= 1) || (bMinors == 0 && wMinors <= 1) {
                let wOK = (wMinors == 0 && wNP <= 14) || (wMinors <= 1 && wNP <= 17)
                let bOK = (bMinors == 0 && bNP <= 14) || (bMinors <= 1 && bNP <= 17)
                if wOK, bOK { return .asymmetricHeavy }
            } else if (wR > 0 && bR == 0) || (wR == 0 && bR > 0) {
                let wOK = wR == 0
                    ? wNP <= 12
                    : (wMinors == 0 && wNP <= 14) || (wMinors <= 1 && wNP <= 17)
                let bOK = bR == 0
                    ? bNP <= 12
                    : (bMinors == 0 && bNP <= 14) || (bMinors <= 1 && bNP <= 17)
                if wOK, bOK { return .asymmetricHeavy }
            }
        }
        if (wQ > 0 || bQ > 0), wR == 0, bR == 0,
           wMinors <= 1, bMinors <= 1, wNP <= 12, bNP <= 12 {
            return .queen
        }
        if wQ > 0, bQ > 0, wR == 0, bR == 0,
           wMinors == 2, bMinors == 2, wNP <= 15, bNP <= 15 {
            return .queenPlusTwoMinor
        }
        if (wNP <= 8 && bNP <= 30) || (bNP <= 8 && wNP <= 30) {
            return .strongImbalance
        }
        if wNP <= 15, bNP <= 15 {
            return (wQ > 0 || bQ > 0) ? .transitional : .generic
        }
        return nil
    }

    static func classifyEndgame(fen: String) -> EndgameType? {
        let counts = pieceCounts(fen: fen)
        return classifyEndgame(white: counts.white, black: counts.black)
    }

    /// First fen index after a capture of N/B/R/Q (0 = start never).
    static func firstNonPawnCapturePly(fenSequence: [String]) -> Int? {
        guard fenSequence.count >= 2 else { return nil }
        for index in 1..<fenSequence.count {
            if lostNonPawn(from: fenSequence[index - 1], to: fenSequence[index]) {
                return index
            }
        }
        return nil
    }

    /// First ply where the same endgame family holds for `endgameStabilityPlies` in a row.
    /// A run that reaches the final ply may qualify with one fewer ply (unfinished settling).
    static func firstStableEndgameStartPly(in fenSequence: [String]) -> Int? {
        guard fenSequence.count > 1 else { return nil }

        let required = endgameStabilityPlies
        let terminalRequired = max(2, required - 1)
        let lastPly = fenSequence.count - 1
        var runStart: Int?
        var runType: EndgameType?
        var runLength = 0

        for ply in 1..<fenSequence.count {
            if let type = classifyEndgame(fen: fenSequence[ply]) {
                if type == runType {
                    runLength += 1
                } else {
                    runStart = ply
                    runType = type
                    runLength = 1
                }
                let touchesEnd = ply == lastPly
                let threshold = touchesEnd ? terminalRequired : required
                if runLength >= threshold, let runStart {
                    return runStart
                }
            } else {
                runStart = nil
                runType = nil
                runLength = 0
            }
        }
        return nil
    }

    static func boundaries(
        fenSequence: [String],
        lastInBookPly: Int
    ) -> GamePhaseBoundaries {
        guard !fenSequence.isEmpty else { return .empty }

        let cappedBook = min(max(0, lastInBookPly), fenSequence.count - 1)
        let capturePly = firstNonPawnCapturePly(fenSequence: fenSequence)

        let middlegameStart: Int
        if let capturePly {
            middlegameStart = max(cappedBook + 1, capturePly)
        } else {
            middlegameStart = max(cappedBook + 1, defaultOpeningPlies)
        }

        var endgameStart: Int? = firstStableEndgameStartPly(in: fenSequence)

        let midPly = middlegameStart < fenSequence.count ? middlegameStart : nil
        // Opening can collapse straight into endgame (early mass trades) — omit a middlegame
        // marker that would otherwise sit after the endgame cut.
        if let endPly = endgameStart, let midPly, endPly <= midPly {
            return GamePhaseBoundaries(middlegameStartPly: nil, endgameStartPly: endPly)
        }

        return GamePhaseBoundaries(
            middlegameStartPly: midPly,
            endgameStartPly: endgameStart
        )
    }

    static func phase(
        atPly ply: Int,
        fen: String,
        boundaries: GamePhaseBoundaries
    ) -> GamePhaseInfo {
        if let endStart = boundaries.endgameStartPly, ply >= endStart {
            return GamePhaseInfo(kind: .endgame, endgameType: classifyEndgame(fen: fen))
        }
        if let midStart = boundaries.middlegameStartPly, ply >= midStart {
            return GamePhaseInfo(kind: .middlegame, endgameType: nil)
        }
        return GamePhaseInfo(kind: .opening, endgameType: nil)
    }

    /// Chart / PDF phase markers (ply indices into `fenSequence`).
    static func phaseTransitions(
        fenSequence: [String],
        lastInBookPly: Int
    ) -> [(kind: GamePhaseKind, ply: Int)] {
        let bounds = boundaries(fenSequence: fenSequence, lastInBookPly: lastInBookPly)
        var result: [(GamePhaseKind, Int)] = []
        if let mid = bounds.middlegameStartPly {
            result.append((.middlegame, mid))
        }
        if let end = bounds.endgameStartPly {
            result.append((.endgame, end))
        }
        return result
    }

    // MARK: - Private

    private static func lostNonPawn(from before: String, to after: String) -> Bool {
        let a = pieceCounts(fen: before)
        let b = pieceCounts(fen: after)
        func lost(_ x: PhasePieceCounts, _ y: PhasePieceCounts) -> Bool {
            y.queens < x.queens || y.rooks < x.rooks
                || y.bishops < x.bishops || y.knights < x.knights
        }
        return lost(a.white, b.white) || lost(a.black, b.black)
    }
}
