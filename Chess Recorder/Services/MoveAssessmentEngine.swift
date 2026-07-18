//
//  MoveAssessmentEngine.swift
//  Chess Recorder
//

import Foundation
import LucidEngine

struct MoveAssessmentResult: Sendable {
    let quality: MoveQuality
    let centipawnLoss: Int
    let scoreBefore: Score
    let rawScoreAfter: Score
    /// Engine best move from the position before the played ply (SAN), when available.
    let bestMoveSAN: String?
}

/// Serial owner of a dedicated LucidEngine instance for post-move quality assessment.
actor MoveAssessmentEngine {
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
        guard isPrepared else { return }
        await engine.shutdown()
        isPrepared = false
    }

    func assessMove(
        fenBefore: String,
        fenAfter: String,
        depth: Int,
        deliveredCheckmate: Bool = false
    ) async throws -> MoveAssessmentResult {
        // Keep live analysis from calling sf_stop_search() during this pair of evals.
        try await StockfishSearchLock.withAssessmentSession {
            let beforeAssessment = try await engine.evaluate(fen: fenBefore, depth: depth)
            let bestMoveSAN = Self.san(for: beforeAssessment.bestMove, fenBefore: fenBefore)

            // If the played move is the engine's #1 choice, it cannot be a blunder — even when a
            // concurrent analysis stop corrupts the fenAfter eval and invents a huge CPL.
            if MoveAssessmentClassifier.isEngineBestMove(
                fenBefore: fenBefore,
                fenAfter: fenAfter,
                bestMove: beforeAssessment.bestMove
            ) {
                return MoveAssessmentResult(
                    quality: .good,
                    centipawnLoss: 0,
                    scoreBefore: beforeAssessment.score,
                    rawScoreAfter: MoveAssessmentClassifier.inverted(beforeAssessment.score),
                    bestMoveSAN: bestMoveSAN
                )
            }

            let rawScoreAfter: Score
            do {
                rawScoreAfter = try await engine.evaluate(fen: fenAfter, depth: depth).score
            } catch EngineError.analysisInterrupted {
                // Terminal checkmate/stalemate FENs often have no best move; LucidEngine maps that
                // to analysisInterrupted. Treat delivered mate (or pre-move mate score) as mate-in-0.
                if case .mate(let n) = beforeAssessment.score, n > 0 {
                    rawScoreAfter = .mate(0)
                } else if deliveredCheckmate {
                    rawScoreAfter = .mate(0)
                } else {
                    throw EngineError.analysisInterrupted
                }
            }

            let centipawnLoss = MoveAssessmentClassifier.centipawnLoss(
                scoreBefore: beforeAssessment.score,
                rawScoreAfter: rawScoreAfter
            )
            let quality = MoveAssessmentClassifier.quality(
                centipawnLoss: centipawnLoss,
                scoreBefore: beforeAssessment.score,
                rawScoreAfter: rawScoreAfter
            )

            return MoveAssessmentResult(
                quality: quality,
                centipawnLoss: centipawnLoss,
                scoreBefore: beforeAssessment.score,
                rawScoreAfter: rawScoreAfter,
                bestMoveSAN: bestMoveSAN
            )
        }
    }

    private static func san(for bestMove: Move, fenBefore: String) -> String? {
        let line = ChessKitMapping.formatEnginePrincipalLineSAN([bestMove.uci], fen: fenBefore)
        guard line != "—", !line.isEmpty else { return nil }
        return line
    }
}
