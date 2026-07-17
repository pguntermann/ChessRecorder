//
//  EngineAnalysisEngine.swift
//  Chess Recorder
//

import Foundation
import CStockfish
import LucidEngine

/// Serial owner of the Stockfish/LucidEngine instance. All searches run here, off the main actor.
actor EngineAnalysisEngine {
    private let engine: LucidEngine
    private(set) var isPrepared = false

    init(configuration: EngineConfiguration) {
        engine = LucidEngine(configuration: configuration)
    }

    func prepare() async throws {
        guard !isPrepared else { return }
        try await engine.start()
        isPrepared = true
    }

    func shutdown() async {
        stopSearch()
        guard isPrepared else { return }
        await engine.shutdown()
        isPrepared = false
    }

    func stopSearch() {
        // Assessment owns the global Stockfish search while classifying moves.
        guard !StockfishSearchLock.isAssessmentSessionActive else { return }
        sf_stop_search()
    }

    func evaluate(fen: String, depth: Int) async throws -> PositionAssessment {
        try await engine.evaluate(fen: fen, depth: depth)
    }
}

struct AnalysisSnapshot: Sendable {
    let fen: String
    let sideToMove: PieceColor
    let fenSequence: [String]
}

enum EngineAnalysisDisplayBuilder {
    static let maxDepth = 100

    static func currentPhase(fens: [String]) -> EngineGamePhase {
        guard fens.count >= 2 else { return .opening }

        let phases = GamePhaseDetector.detect(fens: fens)
        let moveNumber = fens.count - 1

        if let endgame = phases.endgame, endgame.contains(moveNumber) {
            return .endgame
        }
        if let middlegame = phases.middlegame, middlegame.contains(moveNumber) {
            return .middlegame
        }
        if let opening = phases.opening, opening.contains(moveNumber) {
            return .opening
        }
        return .opening
    }

    static func makeDisplay(
        assessment: PositionAssessment,
        fen: String,
        sideToMove: PieceColor,
        gamePhase: EngineGamePhase,
        statusMessage: String
    ) -> EngineAnalysisDisplay {
        let whiteScore = whitePerspectiveScore(assessment.score, sideToMove: sideToMove)
        let wdl = WinProbabilityCalculator.calculate(score: whiteScore)

        return EngineAnalysisDisplay(
            evaluationText: formatEvaluation(assessment.score, sideToMove: sideToMove),
            evaluationBarWhiteFraction: evaluationBarWhiteFraction(assessment.score, sideToMove: sideToMove),
            winProbability: WinProbabilityDisplay(wdl: wdl),
            gamePhase: gamePhase,
            principalLineUCI: formatPrincipalLineUCI(assessment.principalVariation.map(\.uci)),
            principalLineSAN: ChessKitMapping.formatEnginePrincipalLineSAN(
                assessment.principalVariation.map(\.uci),
                fen: fen
            ),
            nextMoveArrow: arrowMove(from: assessment.principalVariation.first?.uci),
            statusMessage: statusMessage
        )
    }

    static func initialDepth(targetDepth: Int, unlimited: Bool) -> Int {
        min(unlimited ? 6 : targetDepth, 6)
    }

    static func nextDepth(after depth: Int, targetDepth: Int, unlimited: Bool) -> Int? {
        let step: Int
        switch depth {
        case ..<10:
            step = 2
        case ..<20:
            step = 4
        default:
            step = 8
        }
        let candidate = depth + step

        if unlimited {
            return candidate <= maxDepth ? candidate : nil
        }

        // Always include the configured max, even when the normal step would overshoot it.
        guard depth < targetDepth else { return nil }
        return min(candidate, targetDepth)
    }

    static func hasNextDepth(after depth: Int, targetDepth: Int, unlimited: Bool) -> Bool {
        nextDepth(after: depth, targetDepth: targetDepth, unlimited: unlimited) != nil
    }

    static func depthStatusMessage(
        currentDepth: Int,
        targetDepth: Int,
        unlimited: Bool,
        isFinal: Bool
    ) -> String {
        if unlimited {
            if isFinal {
                return "Depth \(currentDepth) (uncapped)"
            }
            if let next = nextDepth(after: currentDepth, targetDepth: targetDepth, unlimited: true) {
                return "Depth \(currentDepth) (next \(next))"
            }
            return "Depth \(currentDepth) (updating)"
        }

        if isFinal {
            return "Depth \(currentDepth)"
        }
        if let next = nextDepth(after: currentDepth, targetDepth: targetDepth, unlimited: false) {
            return "Depth \(currentDepth) of \(targetDepth) (next \(next))"
        }
        return "Depth \(currentDepth) of \(targetDepth)"
    }

    static func statusMessage(for error: Error, fallbackDepth: Int? = nil, unlimited: Bool = false) -> String {
        guard let engineError = error as? EngineError else {
            return "Analysis failed"
        }

        switch engineError {
        case .evaluationTimeout:
            if let fallbackDepth {
                return unlimited ? "Depth \(fallbackDepth) (timed out)" : "Depth \(fallbackDepth) (timed out)"
            }
            return "Analysis timed out"
        case .engineNotRunning:
            return "Engine unavailable"
        case .invalidFEN:
            return "Invalid position"
        default:
            return "Analysis failed"
        }
    }

    static func evaluationBarWhiteFraction(forPawns pawns: Double) -> Double {
        let normalized = tanh(pawns / 4.0)
        return min(max((normalized + 1.0) / 2.0, 0.0), 1.0)
    }

    private static func formatEvaluation(_ score: Score, sideToMove: PieceColor) -> String {
        let whitePerspective = whitePerspectiveScore(score, sideToMove: sideToMove)
        switch whitePerspective {
        case .centipawns(let cp):
            return String(format: "%+.2f", Double(cp) / 100.0)
        case .mate(let moves):
            if moves > 0 {
                return "M\(moves)"
            }
            if moves < 0 {
                return "-M\(abs(moves))"
            }
            return "0.00"
        }
    }

    private static func evaluationBarWhiteFraction(_ score: Score, sideToMove: PieceColor) -> Double {
        let whitePerspective = whitePerspectiveScore(score, sideToMove: sideToMove)

        switch whitePerspective {
        case .centipawns(let cp):
            return evaluationBarWhiteFraction(forPawns: Double(cp) / 100.0)
        case .mate(let moves):
            if moves > 0 { return 1.0 }
            if moves < 0 { return 0.0 }
            return 0.5
        }
    }

    private static func whitePerspectiveScore(_ score: Score, sideToMove: PieceColor) -> Score {
        switch score {
        case .centipawns(let cp):
            return .centipawns(sideToMove == .white ? cp : -cp)
        case .mate(let moves):
            return .mate(sideToMove == .white ? moves : -moves)
        }
    }

    private static func formatPrincipalLineUCI(_ line: [String]) -> String {
        guard !line.isEmpty else { return "—" }
        return line.joined(separator: " ")
    }

    private static func arrowMove(from uci: String?) -> AnalysisArrowMove? {
        guard let uci,
              let move = ChessKitMapping.engineMoveComponents(from: uci),
              let from = ChessPosition(notation: move.from),
              let to = ChessPosition(notation: move.to) else {
            return nil
        }

        return AnalysisArrowMove(from: from, to: to)
    }
}
