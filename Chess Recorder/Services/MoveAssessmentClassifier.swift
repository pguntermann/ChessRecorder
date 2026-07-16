//
//  MoveAssessmentClassifier.swift
//  Chess Recorder
//

import Foundation
import LucidEngine

/// Adapts LucidEngine move classification to Chess Recorder's assessment pipeline.
///
/// LucidEngine's `evaluate(fen:)` scores are always from the side-to-move at that FEN.
/// After a move, that is the opponent — but `MoveClassifier` expects `scoreAfter` from the
/// mover's perspective (same as the CPL calculation). This type performs that conversion.
///
/// Additional Chess Recorder policy: when the side to move already had a forced mate,
/// do not treat mate↔centipawn scaling (CPL ≈ 9000) as an automatic blunder if the
/// position remains decisively winning. Slower forced mates are classified as `.miss`.
enum MoveAssessmentClassifier: Sendable {
    /// Centipawns (mover perspective) at/above which a position is still "decisively winning".
    nonisolated static let decisiveWinCentipawns = 300
    /// Above this, losing a mate score but staying crushing is only an inaccuracy.
    nonisolated static let crushingWinCentipawns = 600

    /// True when the move between `fenBefore` and `fenAfter` is the engine's best move.
    nonisolated static func isEngineBestMove(
        fenBefore: String,
        fenAfter: String,
        bestMove: Move
    ) -> Bool {
        guard let played = FENDiff.detectMove(before: fenBefore, after: fenAfter) else {
            return false
        }
        return played == bestMove
    }

    nonisolated static func quality(
        centipawnLoss: Int,
        scoreBefore: Score,
        rawScoreAfter: Score
    ) -> MoveQuality {
        if case .mate(let before) = scoreBefore, before > 0 {
            return qualityAfterHavingMate(
                beforeMateIn: before,
                rawScoreAfter: rawScoreAfter
            )
        }

        return MoveQuality(
            MoveClassifier.classify(
                centipawnLoss: centipawnLoss,
                scoreBefore: scoreBefore,
                scoreAfter: inverted(rawScoreAfter)
            )
        )
    }

    nonisolated static func centipawnLoss(scoreBefore: Score, rawScoreAfter: Score) -> Int {
        let bestScore = centipawnValue(of: scoreBefore)
        let scoreAfterMove = -centipawnValue(of: rawScoreAfter)
        return max(0, bestScore - scoreAfterMove)
    }

    nonisolated static func inverted(_ score: Score) -> Score {
        switch score {
        case .centipawns(let cp):
            return .centipawns(-cp)
        case .mate(let n):
            return .mate(-n)
        }
    }

    nonisolated static func centipawnValue(of score: Score) -> Int {
        switch score {
        case .centipawns(let cp):
            return cp
        case .mate(let n):
            return n > 0 ? 10_000 - n : -10_000 - n
        }
    }

    nonisolated private static func qualityAfterHavingMate(
        beforeMateIn: Int,
        rawScoreAfter: Score
    ) -> MoveQuality {
        switch inverted(rawScoreAfter) {
        case .mate(let mateAfter) where mateAfter > 0:
            // Still a forced mate. Slower than before = miss; same/faster = good.
            return mateAfter > beforeMateIn ? .miss : .good
        case .mate(let mateAfter) where mateAfter == 0:
            // Delivered checkmate.
            return .good
        case .centipawns(let cp) where cp >= crushingWinCentipawns:
            return .inaccuracy
        case .centipawns(let cp) where cp >= decisiveWinCentipawns:
            return .mistake
        default:
            // Lost the mate and the decisive advantage.
            return .blunder
        }
    }
}
