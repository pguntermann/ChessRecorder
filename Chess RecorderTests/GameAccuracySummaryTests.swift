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
        // Win%-based: perfect white; black 175 CPL near equality ≈ 50%.
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

    func testWinChanceMoveAccuracyFromCPL() {
        XCTAssertEqual(WinChanceAccuracy.moveAccuracy(centipawnLoss: 0), 100, accuracy: 0.01)
        XCTAssertEqual(WinChanceAccuracy.moveAccuracy(centipawnLoss: 175).rounded(), 50)
        XCTAssertEqual(WinChanceAccuracy.moveAccuracy(centipawnLoss: 280).rounded(), 35)
        XCTAssertEqual(WinChanceAccuracy.moveAccuracy(centipawnLoss: 500).rounded(), 19)
        XCTAssertEqual(
            WinChanceAccuracy.gameAccuracy(moveAccuracies: [100, 100, 100]) ?? -1,
            100,
            accuracy: 0.01
        )
    }

    func testMateScaleCPLIsCappedForOverviewAndAccuracy() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),
            move("e5", quality: .good, centipawnLoss: 0),
            move("Nf3", quality: .blunder, centipawnLoss: 9_500), // mate-scale raw loss
            move("Nc6", quality: .good, centipawnLoss: 0)
        ]
        let summary = GameAccuracySummary(moves: moves)
        // White: move accuracies 100 + ~19 (500-cp swing) → game ≈ 46%.
        XCTAssertEqual(summary.white.accuracyPercent, 27)
        XCTAssertEqual(summary.black.accuracyPercent, 100)
        XCTAssertEqual(summary.white.averageCentipawnLoss ?? -1, 250, accuracy: 0.01)
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
        // White: 100 + ~66 → ≈ 81%. Black: ~35%.
        XCTAssertEqual(summary.white.compactLabel, "Accuracy 78% · 1 good · 1 miss")
        XCTAssertEqual(summary.black.compactLabel, "Accuracy 35% · 1 blunder")
        XCTAssertEqual(summary.white.accuracyText, "78%")
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
        XCTAssertEqual(summary.white.compactLabel, "Accuracy 83% · 1 good · 1 inaccuracy")
        XCTAssertEqual(summary.black.compactLabel, "Accuracy 76% · 1 inaccuracy")
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
        XCTAssertEqual(summary.white.accuracyPercent, 48)
        XCTAssertEqual(summary.black.accuracyPercent, 100)
    }

    func testAccuracyProgressIsRunningGameAccuracyByMoveNumber() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),         // W move 1 → 100
            move("e5", quality: .good, centipawnLoss: 0),         // B move 1 → 100
            move("Nf3", quality: .blunder, centipawnLoss: 280),   // W move 2 → ~59
            move("Nc6", quality: .mistake, centipawnLoss: 175),   // B move 2 → ~73
            move("d4", quality: .book)                            // W book → no progress point
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.accuracyProgress.count, 4)
        XCTAssertEqual(summary.accuracyProgress[0].side, .white)
        XCTAssertEqual(summary.accuracyProgress[0].moveNumber, 1)
        XCTAssertEqual(summary.accuracyProgress[0].accuracyPercent, 100)
        XCTAssertEqual(summary.accuracyProgress[2].side, .white)
        XCTAssertEqual(summary.accuracyProgress[2].moveNumber, 2)
        XCTAssertEqual(summary.accuracyProgress[2].accuracyPercent, 44)
        XCTAssertEqual(summary.accuracyProgress[3].accuracyPercent, 63)
        XCTAssertTrue(summary.hasAccuracyProgress)
    }

    func testCumulativeAccuracyProgressOnlyFallsOrStaysFlat() {
        // White blunders first, then plays perfectly — running rises; cumulative stays flat.
        let moves = [
            move("e4", quality: .blunder, centipawnLoss: 280),
            move("e5", quality: .good, centipawnLoss: 0),
            move("Nf3", quality: .good, centipawnLoss: 0),
            move("Nc6", quality: .good, centipawnLoss: 0),
            move("d4", quality: .good, centipawnLoss: 0)
        ]
        let summary = GameAccuracySummary(moves: moves)
        let runningWhite = summary.accuracyProgress(for: .running).filter { $0.side == .white }
        let cumulativeWhite = summary.accuracyProgress(for: .cumulative).filter { $0.side == .white }

        XCTAssertEqual(runningWhite.map(\.accuracyPercent), [35, 44, 50])
        XCTAssertEqual(cumulativeWhite.map(\.accuracyPercent), [53, 52, 50])
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
        let moves = [
            move("e4", quality: .good),
            move("e5", quality: .mistake)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.white.accuracyPercent, 100)
        // Legacy mistake → 175 CPL equivalent → ~50% move accuracy.
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
        XCTAssertFalse(labels.contains("6"), "Narrow book strip still omits first scored label")
        XCTAssertTrue(labels.contains("10"))
    }

    func testAccuracyProgressXScaleKeepsFirstPointClearOfBookLabel() {
        let progress = [
            GameAccuracySummary.AccuracyProgressPoint(side: .black, moveNumber: 8, accuracyPercent: 72),
            GameAccuracySummary.AccuracyProgressPoint(side: .white, moveNumber: 9, accuracyPercent: 82),
            GameAccuracySummary.AccuracyProgressPoint(side: .black, moveNumber: 54, accuracyPercent: 79)
        ]
        let scale = GameAccuracySummary.AccuracyProgressXScale(progress: progress)
        let domain = scale.domain(maxMoveNumber: 54)
        let firstX = scale.plotX(moveNumber: 8)
        let bookWidth = scale.compressedUnits

        XCTAssertTrue(scale.isCompressed)
        XCTAssertEqual(scale.bookEndMove, 7)
        XCTAssertGreaterThanOrEqual(bookWidth, 1.2)
        XCTAssertGreaterThan(firstX, bookWidth, "First scored point must sit after the book strip")
        XCTAssertGreaterThan(
            (firstX - domain.lowerBound) / (domain.upperBound - domain.lowerBound),
            0.06,
            "First point should not hug the leading edge on a long game"
        )

        let labels = scale.axisMarks(scoredMoves: progress.map(\.moveNumber)).map(\.label)
        XCTAssertEqual(labels.first, "0...7")
        XCTAssertTrue(labels.contains("8"), "Wide book strip should label the first scored move")
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

    func testEvaluationProgressUsesStoredWhiteCentipawns() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0, evaluationWhiteCentipawns: 20),
            move("e5", quality: .good, centipawnLoss: 0, evaluationWhiteCentipawns: 15)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.evaluationProgress.count, 3)
        XCTAssertEqual(summary.evaluationProgress[0].evaluationPawns, 0)
        XCTAssertEqual(summary.evaluationProgress[1].evaluationPawns, 0.2, accuracy: 0.0001)
        XCTAssertEqual(summary.evaluationProgress[2].evaluationPawns, 0.15, accuracy: 0.0001)
    }

    func testUnassessedMovesMarkAssessmentIncomplete() {
        let moves = [
            move("e4", quality: .good, centipawnLoss: 0),
            move("e5", quality: nil),
            move("Nf3", quality: nil)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.unassessedMoveCount, 2)
        XCTAssertTrue(summary.isAssessmentIncomplete)
    }

    func testCriticalPliesIncludeFirstBlunderEvenWhenOutsideTopCPL() {
        // Early mild blunder, then three larger mistakes that would otherwise fill the top-3 slot.
        let moves = [
            move("e4", quality: .blunder, centipawnLoss: 80),
            move("e5", quality: .mistake, centipawnLoss: 200),
            move("Nf3", quality: .mistake, centipawnLoss: 220),
            move("Nc6", quality: .miss, centipawnLoss: 250),
            move("Bb5", quality: .good, centipawnLoss: 0)
        ]
        let summary = GameAccuracySummary(moves: moves)
        let plies = summary.evaluationCriticalPlies.map(\.ply)
        XCTAssertTrue(plies.contains(1), "First blunder (ply 1) should be included")
        XCTAssertEqual(Set(plies).count, 4)
        XCTAssertEqual(plies, plies.sorted(), "Critical plies should be chronological")
    }

    func testCriticalPliesDoNotDuplicateFirstBlunderWhenAlreadyTopCPL() {
        let moves = [
            move("e4", quality: .blunder, centipawnLoss: 400),
            move("e5", quality: .mistake, centipawnLoss: 100),
            move("Nf3", quality: .good, centipawnLoss: 0)
        ]
        let summary = GameAccuracySummary(moves: moves)
        let blunderMarkers = summary.evaluationCriticalPlies.filter { $0.quality == .blunder }
        XCTAssertEqual(blunderMarkers.count, 1)
        XCTAssertEqual(blunderMarkers.first?.ply, 1)
    }

    func testSelectCriticalPliesIsStableForEmptyInput() {
        XCTAssertTrue(GameAccuracySummary.selectCriticalPlies(from: []).isEmpty)
    }

    func testOpeningAndEndgameTypeAreCapturedOnSummary() {
        let start =
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let endgame = "4r1k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"
        var fens = Array(repeating: start, count: 8)
        fens[5] = endgame
        fens[7] = endgame

        let opening = OpeningDisplay(eco: "C65", name: "Ruy Lopez")
        let summary = GameAccuracySummary(
            moves: [
                move("e4", quality: .book),
                move("e5", quality: .good, centipawnLoss: 0)
            ],
            fenSequence: fens,
            lastInBookPly: 1,
            opening: opening
        )

        XCTAssertEqual(summary.opening, opening)
        XCTAssertEqual(summary.endgameType, .rook)
        XCTAssertTrue(summary.evaluationPhaseTransitions.contains { $0.kind == .endgame })
    }

    private func move(
        _ san: String,
        quality: MoveQuality?,
        centipawnLoss: Int? = nil,
        evaluationWhiteCentipawns: Int? = nil,
        isCheckmate: Bool = false
    ) -> ChessMove {
        ChessMove(
            san: san,
            piece: .pawn,
            from: ChessPosition(file: 4, rank: 1),
            to: ChessPosition(file: 4, rank: 3),
            captures: false,
            isCheck: false,
            isCheckmate: isCheckmate,
            promotion: nil,
            castling: nil,
            quality: quality,
            centipawnLoss: centipawnLoss,
            evaluationWhiteCentipawns: evaluationWhiteCentipawns
        )
    }
}
