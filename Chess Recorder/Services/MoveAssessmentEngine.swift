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

    func assessMove(fenBefore: String, fenAfter: String, depth: Int) async throws -> MoveAssessmentResult {
        let beforeAssessment = try await engine.evaluate(fen: fenBefore, depth: depth)
        let rawScoreAfter: Score
        do {
            rawScoreAfter = try await engine.evaluate(fen: fenAfter, depth: depth).score
        } catch EngineError.analysisInterrupted {
            // Terminal checkmate/stalemate FENs often have no best move; LucidEngine maps that
            // to analysisInterrupted. If we already had a forced mate, treat this as delivery.
            guard case .mate(let n) = beforeAssessment.score, n > 0 else {
                throw EngineError.analysisInterrupted
            }
            rawScoreAfter = .mate(0)
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
            rawScoreAfter: rawScoreAfter
        )
    }
}
