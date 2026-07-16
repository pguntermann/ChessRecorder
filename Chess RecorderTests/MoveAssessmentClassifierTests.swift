import XCTest
import LucidEngine
import SwiftUI
@testable import Chess_Recorder

final class MoveAssessmentClassifierTests: XCTestCase {

    func testContinuingForcedMateSameSpeedIsGood() {
        let quality = MoveAssessmentClassifier.quality(
            centipawnLoss: 0,
            scoreBefore: .mate(8),
            rawScoreAfter: .mate(-7)
        )
        XCTAssertEqual(quality, .good)
    }

    func testSlowerForcedMateIsMissNotBlunder() {
        // Mate in 3 → mate in 8 (raw after is opponent getting mated in 8).
        let quality = MoveAssessmentClassifier.quality(
            centipawnLoss: 5,
            scoreBefore: .mate(3),
            rawScoreAfter: .mate(-8)
        )
        XCTAssertEqual(quality, .miss)
        XCTAssertEqual(MoveQuality.miss.annotationSymbol, "")
        XCTAssertTrue(MoveQuality.miss.showsAssessmentDecoration)
    }

    func testFasterOrEqualMateIsGood() {
        let faster = MoveAssessmentClassifier.quality(
            centipawnLoss: 0,
            scoreBefore: .mate(5),
            rawScoreAfter: .mate(-3)
        )
        XCTAssertEqual(faster, .good)

        let same = MoveAssessmentClassifier.quality(
            centipawnLoss: 0,
            scoreBefore: .mate(4),
            rawScoreAfter: .mate(-4)
        )
        XCTAssertEqual(same, .good)
    }

    func testDeliveringMateIsGoodNotBlunder() {
        let quality = MoveAssessmentClassifier.quality(
            centipawnLoss: 0,
            scoreBefore: .mate(1),
            rawScoreAfter: .mate(0)
        )
        XCTAssertEqual(quality, .good)
    }

    func testMateScoreDropToCrushingWinIsInaccuracyNotBlunder() {
        let quality = MoveAssessmentClassifier.quality(
            centipawnLoss: 9_000,
            scoreBefore: .mate(4),
            rawScoreAfter: .centipawns(-800)
        )
        XCTAssertEqual(quality, .inaccuracy)
    }

    func testMateScoreDropToModestWinIsMistakeNotBlunder() {
        let quality = MoveAssessmentClassifier.quality(
            centipawnLoss: 9_500,
            scoreBefore: .mate(3),
            rawScoreAfter: .centipawns(-400)
        )
        XCTAssertEqual(quality, .mistake)
    }

    func testMissingMateAndLosingAdvantageIsBlunder() {
        let quality = MoveAssessmentClassifier.quality(
            centipawnLoss: 9_800,
            scoreBefore: .mate(3),
            rawScoreAfter: .centipawns(-50)
        )
        XCTAssertEqual(quality, .blunder)
    }

    func testAllowingOpponentMateIsBlunder() {
        let quality = MoveAssessmentClassifier.quality(
            centipawnLoss: 0,
            scoreBefore: .centipawns(100),
            rawScoreAfter: .mate(3)
        )
        XCTAssertEqual(quality, .blunder)
    }

    func testAlreadyBeingMatedIsNotFlaggedAsAllowingMate() {
        let cpl = MoveAssessmentClassifier.centipawnLoss(
            scoreBefore: .mate(-5),
            rawScoreAfter: .mate(4)
        )
        let quality = MoveAssessmentClassifier.quality(
            centipawnLoss: cpl,
            scoreBefore: .mate(-5),
            rawScoreAfter: .mate(4)
        )
        XCTAssertEqual(quality, .good)
        XCTAssertLessThan(cpl, 30)
    }

    func testLegacyRawAfterPerspectiveWouldHaveMarkedMateContinuationAsBlunder() {
        let buggy = MoveClassifier.classify(
            centipawnLoss: 0,
            scoreBefore: .mate(5),
            scoreAfter: .mate(-4)
        )
        XCTAssertEqual(buggy, .blunder)

        let fixed = MoveAssessmentClassifier.quality(
            centipawnLoss: 0,
            scoreBefore: .mate(5),
            rawScoreAfter: .mate(-4)
        )
        XCTAssertEqual(fixed, .good)
    }

    func testMissUsesConfigurableUnderlineColor() {
        let pink = Color(red: 1.0, green: 0.45, blue: 0.75)
        let colors = MoveAssessmentColors(
            inaccuracy: .yellow,
            mistake: .orange,
            blunder: .red,
            miss: pink
        )
        XCTAssertEqual(colors.underlineColor(for: .miss), pink)
    }
}
