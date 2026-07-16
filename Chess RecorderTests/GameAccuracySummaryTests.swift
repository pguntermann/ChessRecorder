import XCTest
@testable import Chess_Recorder

final class GameAccuracySummaryTests: XCTestCase {

    func testEmptyWhenNoQualities() {
        let moves = [
            move("e4", quality: nil),
            move("e5", quality: nil)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertFalse(summary.hasContent)
        XCTAssertFalse(summary.white.hasContent)
        XCTAssertFalse(summary.black.hasContent)
        XCTAssertTrue(summary.accuracyProgress.isEmpty)
    }

    func testBookMovesExcludedFromAccuracy() {
        let moves = [
            move("e4", quality: .book),
            move("e5", quality: .book),
            move("Nf3", quality: .good, centipawnLoss: 0),
            move("Nc6", quality: .mistake, centipawnLoss: 175)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertTrue(summary.hasContent)
        XCTAssertEqual(summary.bookMoveCount, 2)
        // White: avg CPL 0 → 100%. Black: 175 → 100 - 175/3.5 = 50%.
        XCTAssertEqual(summary.white.accuracyPercent, 100)
        XCTAssertEqual(summary.black.accuracyPercent, 50)
        XCTAssertEqual(summary.white.compactLabel, "Accuracy 100% · 1 book · 1 good")
        XCTAssertEqual(summary.black.compactLabel, "Accuracy 50% · 1 book · 1 mistake")
        XCTAssertEqual(summary.accuracyProgress.count, 2)
        XCTAssertEqual(summary.accuracyProgress.map(\.side), [.white, .black])
        XCTAssertEqual(summary.accuracyProgress.map(\.accuracyPercent), [100, 50])
    }

    func testOnlyBookMovesHasNoAccuracyPercent() {
        let moves = [
            move("e4", quality: .book),
            move("c5", quality: .book)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertTrue(summary.hasContent)
        XCTAssertNil(summary.white.accuracyPercent)
        XCTAssertEqual(summary.white.compactLabel, "1 book")
        XCTAssertEqual(summary.black.compactLabel, "1 book")
        XCTAssertEqual(summary.compactTableColumns, [.accuracy, .book])
        XCTAssertEqual(summary.white.accuracyText, "—")
        XCTAssertTrue(summary.accuracyProgress.isEmpty)
        XCTAssertFalse(summary.hasAccuracyProgress)
    }

    func testCPLFormulaClampsAndAverages() {
        // Single blunder-sized loss: 280 CPL → 100 - 280/3.5 = 20.
        XCTAssertEqual(GameAccuracySummary.percent(totalCPL: 280, scoredMoves: 1), 20)
        // After per-move cap (500), even mate-scale stored losses average sensibly:
        // one 500-capped move → 100 - 500/3.5 ≈ 100 - 142.86 → floors to 5.
        XCTAssertEqual(GameAccuracySummary.percent(totalCPL: 500, scoredMoves: 1), 5)
        // Perfect play.
        XCTAssertEqual(GameAccuracySummary.percent(totalCPL: 0, scoredMoves: 3), 100)
        // Average of 0 and 70 → 35 CPL → 100 - 10 = 90.
        XCTAssertEqual(GameAccuracySummary.percent(totalCPL: 70, scoredMoves: 2), 90)
    }

    func testMateScaleCPLIsCappedBeforeAveraging() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),
            move("e5", quality: .good, centipawnLoss: 0),
            move("Nf3", quality: .blunder, centipawnLoss: 9_500), // mate-scale raw loss
            move("Nc6", quality: .good, centipawnLoss: 0)
        ]
        let summary = GameAccuracySummary(moves: moves)
        // White: (0 + 500) / 2 = 250 → 100 - 250/3.5 ≈ 28.6 → 29
        XCTAssertEqual(summary.white.accuracyPercent, 29)
        XCTAssertEqual(summary.black.accuracyPercent, 100)
        // Without the cap this would floor at 5%.
        XCTAssertGreaterThan(summary.white.accuracyPercent ?? 0, 5)
    }

    func testBlunderAndMissCountsAppearInCompactLabel() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),
            move("e5", quality: .blunder, centipawnLoss: 280),
            move("Qh5", quality: .miss, centipawnLoss: 105)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.blunderCount, 1)
        XCTAssertEqual(summary.missCount, 1)
        // White: (0 + 105) / 2 = 52.5 → 100 - 15 = 85.
        XCTAssertEqual(summary.white.compactLabel, "Accuracy 85% · 1 good · 1 miss")
        XCTAssertEqual(summary.black.compactLabel, "Accuracy 20% · 1 blunder")
        XCTAssertEqual(summary.white.accuracyText, "85%")
        XCTAssertEqual(summary.compactTableColumns, [.accuracy, .good, .blunders, .misses])
        XCTAssertEqual(summary.white.goodText, "1")
        XCTAssertEqual(summary.black.goodText, "—")
    }

    func testInaccuraciesAppearInCompactColumns() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),
            move("e5", quality: .inaccuracy, centipawnLoss: 70),
            move("Nf3", quality: .inaccuracy, centipawnLoss: 70)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.inaccuracyCount, 2)
        XCTAssertEqual(summary.compactTableColumns, [.accuracy, .good, .inaccuracies])
        XCTAssertEqual(summary.white.inaccuraciesText, "1")
        XCTAssertEqual(summary.black.inaccuraciesText, "1")
        // White: (0+70)/2 = 35 → 90%. Black: 70 → 80%.
        XCTAssertEqual(summary.white.compactLabel, "Accuracy 90% · 1 good · 1 inaccuracy")
        XCTAssertEqual(summary.black.compactLabel, "Accuracy 80% · 1 inaccuracy")
    }

    func testCompactColumnsAndQualitySlicesUseBookThenGoodOrder() {
        let moves = [
            move("e4", quality: .book),
            move("e5", quality: .good, centipawnLoss: 0),
            move("Nf3", quality: .good, centipawnLoss: 0),
            move("Nc6", quality: .mistake, centipawnLoss: 175)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.compactTableColumns, [.accuracy, .book, .good, .mistakes])
        XCTAssertEqual(summary.white.qualitySlices.map(\.quality), [.book, .good])
        XCTAssertEqual(summary.black.qualitySlices.map(\.quality), [.good, .mistake])
    }

    func testSideOwnershipByPlyIndex() {
        let moves = [
            move("e4", quality: .inaccuracy, centipawnLoss: 70), // white
            move("e5", quality: .good, centipawnLoss: 0),       // black
            move("d4", quality: .blunder, centipawnLoss: 280)   // white
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.white.inaccuracyCount, 1)
        XCTAssertEqual(summary.white.blunderCount, 1)
        XCTAssertEqual(summary.white.scoredMoveCount, 2)
        XCTAssertEqual(summary.black.goodCount, 1)
        // white: (70 + 280) / 2 = 175 → 50%
        XCTAssertEqual(summary.white.accuracyPercent, 50)
        XCTAssertEqual(summary.black.accuracyPercent, 100)
    }

    func testAccuracyProgressIsRunningAverageByMoveNumber() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),         // W move 1 → 100
            move("e5", quality: .good, centipawnLoss: 0),         // B move 1 → 100
            move("Nf3", quality: .blunder, centipawnLoss: 280),   // W move 2 → avg 140 → 60
            move("Nc6", quality: .mistake, centipawnLoss: 175),   // B move 2 → avg 87.5 → 75
            move("d4", quality: .book)                            // W book → no progress point
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.accuracyProgress.count, 4)
        XCTAssertEqual(summary.accuracyProgress[0].side, .white)
        XCTAssertEqual(summary.accuracyProgress[0].moveNumber, 1)
        XCTAssertEqual(summary.accuracyProgress[0].accuracyPercent, 100)
        XCTAssertEqual(summary.accuracyProgress[2].side, .white)
        XCTAssertEqual(summary.accuracyProgress[2].moveNumber, 2)
        XCTAssertEqual(summary.accuracyProgress[2].accuracyPercent, 60)
        XCTAssertEqual(summary.accuracyProgress[3].accuracyPercent, 75)
        XCTAssertTrue(summary.hasAccuracyProgress)
    }

    func testLegacyQualitiesWithoutCPLMapThroughEquivalentLoss() {
        // No stored CPL: invert former point scores so percentages match the old curve.
        let moves = [
            move("e4", quality: .good),
            move("e5", quality: .mistake)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.white.accuracyPercent, 100)
        XCTAssertEqual(summary.black.accuracyPercent, 50)
    }

    func testQualitySlicesOmitZeros() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),
            move("e5", quality: .book)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.white.qualitySlices.map(\.quality), [.good])
        XCTAssertEqual(summary.black.qualitySlices.map(\.quality), [.book])
    }

    private func move(_ san: String, quality: MoveQuality?, centipawnLoss: Int? = nil) -> ChessMove {
        ChessMove(
            san: san,
            piece: .pawn,
            from: ChessPosition(file: 4, rank: 1),
            to: ChessPosition(file: 4, rank: 3),
            captures: false,
            isCheck: false,
            isCheckmate: false,
            promotion: nil,
            castling: nil,
            quality: quality,
            centipawnLoss: centipawnLoss
        )
    }
}
