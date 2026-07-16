//
//  MoveAssessmentEngine.swift
//  Chess Recorder
//

import Foundation
import LucidEngine

struct MoveAssessmentResult: Sendable {
    let quality: MoveQuality
    let centipawnLoss: Int
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
        let afterAssessment = try await engine.evaluate(fen: fenAfter, depth: depth)

        let bestScore = centipawnValue(of: beforeAssessment.score)
        let afterScore = centipawnValue(of: afterAssessment.score)
        let scoreAfterMove = -afterScore
        let centipawnLoss = max(0, bestScore - scoreAfterMove)

        let classification = MoveClassifier.classify(
            centipawnLoss: centipawnLoss,
            scoreBefore: beforeAssessment.score,
            scoreAfter: afterAssessment.score
        )

        return MoveAssessmentResult(
            quality: MoveQuality(classification),
            centipawnLoss: centipawnLoss
        )
    }

    private func centipawnValue(of score: Score) -> Int {
        switch score {
        case .centipawns(let cp):
            return cp
        case .mate(let n):
            return n > 0 ? 10_000 - n : -10_000 - n
        }
    }
}
