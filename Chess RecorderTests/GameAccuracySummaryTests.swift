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

    func testCumulativeAccuracyProgressOnlyFallsOrStaysFlat() {
        // White blunders first, then plays perfectly — running rises; cumulative stays flat.
        let moves = [
            move("e4", quality: .blunder, centipawnLoss: 280), // W: running 20; cumulative ÷3 → ~73
            move("e5", quality: .good, centipawnLoss: 0),
            move("Nf3", quality: .good, centipawnLoss: 0),     // W: running 60; cumulative ~73
            move("Nc6", quality: .good, centipawnLoss: 0),
            move("d4", quality: .good, centipawnLoss: 0)       // W: running ~73; cumulative ~73
        ]
        let summary = GameAccuracySummary(moves: moves)
        let runningWhite = summary.accuracyProgress(for: .running).filter { $0.side == .white }
        let cumulativeWhite = summary.accuracyProgress(for: .cumulative).filter { $0.side == .white }

        XCTAssertEqual(runningWhite.map(\.accuracyPercent), [20, 60, 73])
        XCTAssertEqual(cumulativeWhite.map(\.accuracyPercent), [73, 73, 73])
        XCTAssertEqual(cumulativeWhite.last?.accuracyPercent, Double(summary.white.accuracyPercent ?? -1))

        for pair in zip(cumulativeWhite, cumulativeWhite.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.1.accuracyPercent, pair.0.accuracyPercent)
        }
    }

    func testOverviewStatsIncludeAverageCPLBestMoveAndBlunderRate() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),         // best
            move("e5", quality: .book),
            move("Nf3", quality: .blunder, centipawnLoss: 280),   // not best
            move("Nc6", quality: .good, centipawnLoss: 0),        // best
            move("d4", quality: .good, centipawnLoss: 70)         // not best
        ]
        let summary = GameAccuracySummary(moves: moves)

        // White scored: 0, 280, 70 → avg 116.67 → 117; best 1/3 → 33%; blunders 1/3 assessed → 33%
        XCTAssertEqual(summary.white.averageCentipawnLoss ?? -1, 350.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(summary.white.averageCPLText, "117")
        XCTAssertEqual(summary.white.bestMoveCount, 1)
        XCTAssertEqual(summary.white.bestMovePercent, 33)
        XCTAssertEqual(summary.white.blunderRatePercent, 33)

        // Black: one book + one best → avg CPL 0; best 100%; blunder 0/2 → 0%
        XCTAssertEqual(summary.black.averageCentipawnLoss, 0)
        XCTAssertEqual(summary.black.bestMovePercent, 100)
        XCTAssertEqual(summary.black.blunderRatePercent, 0)
    }

    func testPlayerDisplayNameFallsBackForMissingOrQuestionMark() {
        XCTAssertEqual(
            GameAccuracySummarySheet.playerDisplayName(from: "Carlsen", fallback: "White"),
            "Carlsen"
        )
        XCTAssertEqual(
            GameAccuracySummarySheet.playerDisplayName(from: "?", fallback: "White"),
            "White"
        )
        XCTAssertEqual(
            GameAccuracySummarySheet.playerDisplayName(from: "  ", fallback: "Black"),
            "Black"
        )
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

    func testAccuracyProgressXScaleCompressesOpeningPrefix() {
        let progress = [
            GameAccuracySummary.AccuracyProgressPoint(side: .white, moveNumber: 6, accuracyPercent: 100),
            GameAccuracySummary.AccuracyProgressPoint(side: .black, moveNumber: 6, accuracyPercent: 90),
            GameAccuracySummary.AccuracyProgressPoint(side: .white, moveNumber: 10, accuracyPercent: 80)
        ]
        let scale = GameAccuracySummary.AccuracyProgressXScale(progress: progress, compressedUnits: 0.28)

        XCTAssertTrue(scale.isCompressed)
        XCTAssertEqual(scale.bookEndMove, 5)
        XCTAssertEqual(scale.plotX(moveNumber: 0), 0)
        XCTAssertEqual(scale.plotX(moveNumber: 5), 0.28, accuracy: 0.0001)
        XCTAssertEqual(scale.plotX(moveNumber: 6), 1.28, accuracy: 0.0001)
        XCTAssertEqual(scale.plotX(moveNumber: 10), 5.28, accuracy: 0.0001)

        let labels = scale.axisMarks(scoredMoves: progress.map(\.moveNumber)).map(\.label)
        XCTAssertEqual(labels.first, "0...5")
        XCTAssertFalse(labels.contains("6"), "First scored move is omitted to avoid overlapping 0...N")
        XCTAssertTrue(labels.contains("10"))
    }

    func testAccuracyProgressXScaleCompressesShortOpeningToo() {
        let progress = [
            GameAccuracySummary.AccuracyProgressPoint(side: .white, moveNumber: 3, accuracyPercent: 100),
            GameAccuracySummary.AccuracyProgressPoint(side: .black, moveNumber: 3, accuracyPercent: 90),
            GameAccuracySummary.AccuracyProgressPoint(side: .white, moveNumber: 4, accuracyPercent: 85),
            GameAccuracySummary.AccuracyProgressPoint(side: .black, moveNumber: 6, accuracyPercent: 80),
            GameAccuracySummary.AccuracyProgressPoint(side: .white, moveNumber: 7, accuracyPercent: 75)
        ]
        let scale = GameAccuracySummary.AccuracyProgressXScale(progress: progress, compressedUnits: 0.28)

        XCTAssertTrue(scale.isCompressed)
        XCTAssertEqual(scale.bookEndMove, 2)
        XCTAssertEqual(scale.plotX(moveNumber: 3), 1.28, accuracy: 0.0001)
        let labels = scale.axisMarks(scoredMoves: progress.map(\.moveNumber)).map(\.label)
        XCTAssertEqual(labels.first, "0...2")
        XCTAssertEqual(Array(labels.dropFirst()), ["4", "5", "6", "7"])
    }

    func testAccuracyProgressXScaleSkipsCompressionWhenNoOpeningGap() {
        let progress = [
            GameAccuracySummary.AccuracyProgressPoint(side: .white, moveNumber: 1, accuracyPercent: 100),
            GameAccuracySummary.AccuracyProgressPoint(side: .black, moveNumber: 2, accuracyPercent: 90)
        ]
        let scale = GameAccuracySummary.AccuracyProgressXScale(progress: progress)

        XCTAssertFalse(scale.isCompressed)
        XCTAssertNil(scale.bookEndMove)
        XCTAssertEqual(scale.plotX(moveNumber: 1), 1)
        XCTAssertEqual(scale.plotX(moveNumber: 2), 2)
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
