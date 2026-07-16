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
            move("Nf3", quality: .good),
            move("Nc6", quality: .mistake)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertTrue(summary.hasContent)
        XCTAssertEqual(summary.bookMoveCount, 2)
        XCTAssertEqual(summary.white.accuracyPercent, 100)
        XCTAssertEqual(summary.black.accuracyPercent, 50)
        XCTAssertEqual(summary.white.compactLabel, "Accuracy 100% · 1 book · 1 good")
        XCTAssertEqual(summary.black.compactLabel, "Accuracy 50% · 1 book · 1 mistake")
        // Book moves do not create progress points.
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

    func testBlunderAndMissCountsAppearInCompactLabel() {
        let moves = [
            move("e4", quality: .good),
            move("e5", quality: .blunder),
            move("Qh5", quality: .miss)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.blunderCount, 1)
        XCTAssertEqual(summary.missCount, 1)
        XCTAssertEqual(summary.white.compactLabel, "Accuracy 85% · 1 good · 1 miss")
        XCTAssertEqual(summary.black.compactLabel, "Accuracy 20% · 1 blunder")
        XCTAssertEqual(summary.white.accuracyText, "85%")
        XCTAssertEqual(summary.compactTableColumns, [.accuracy, .good, .blunders, .misses])
        XCTAssertEqual(summary.white.goodText, "1")
        XCTAssertEqual(summary.black.goodText, "—")
    }

    func testInaccuraciesAppearInCompactColumns() {
        let moves = [
            move("e4", quality: .good),
            move("e5", quality: .inaccuracy),
            move("Nf3", quality: .inaccuracy)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.inaccuracyCount, 2)
        XCTAssertEqual(summary.compactTableColumns, [.accuracy, .good, .inaccuracies])
        XCTAssertEqual(summary.white.inaccuraciesText, "1")
        XCTAssertEqual(summary.black.inaccuraciesText, "1")
        XCTAssertEqual(summary.white.compactLabel, "Accuracy 90% · 1 good · 1 inaccuracy")
        XCTAssertEqual(summary.black.compactLabel, "Accuracy 80% · 1 inaccuracy")
    }

    func testCompactColumnsAndQualitySlicesUseBookThenGoodOrder() {
        let moves = [
            move("e4", quality: .book),
            move("e5", quality: .good),
            move("Nf3", quality: .good),
            move("Nc6", quality: .mistake)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.compactTableColumns, [.accuracy, .book, .good, .mistakes])
        XCTAssertEqual(summary.white.qualitySlices.map(\.quality), [.book, .good])
        XCTAssertEqual(summary.black.qualitySlices.map(\.quality), [.good, .mistake])
    }

    func testSideOwnershipByPlyIndex() {
        let moves = [
            move("e4", quality: .inaccuracy), // white
            move("e5", quality: .good),       // black
            move("d4", quality: .blunder)     // white
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.white.inaccuracyCount, 1)
        XCTAssertEqual(summary.white.blunderCount, 1)
        XCTAssertEqual(summary.white.scoredMoveCount, 2)
        XCTAssertEqual(summary.black.goodCount, 1)
        // white: (80 + 20) / 2 = 50
        XCTAssertEqual(summary.white.accuracyPercent, 50)
        XCTAssertEqual(summary.black.accuracyPercent, 100)
    }

    func testAccuracyProgressIsRunningAverageByMoveNumber() {
        let moves = [
            move("e4", quality: .good),        // W move 1 → 100
            move("e5", quality: .good),        // B move 1 → 100
            move("Nf3", quality: .blunder),    // W move 2 → (100+20)/2 = 60
            move("Nc6", quality: .mistake),    // B move 2 → (100+50)/2 = 75
            move("d4", quality: .book)         // W book → no progress point
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

    func testQualitySlicesOmitZeros() {
        let moves = [
            move("e4", quality: .good),
            move("e5", quality: .book)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertEqual(summary.white.qualitySlices.map(\.quality), [.good])
        XCTAssertEqual(summary.black.qualitySlices.map(\.quality), [.book])
    }

    private func move(_ san: String, quality: MoveQuality?) -> ChessMove {
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
            quality: quality
        )
    }
}
