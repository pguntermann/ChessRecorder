import XCTest
@testable import Chess_Recorder

@MainActor
final class GameReportPDFComposerTests: XCTestCase {
    private let metadata = PGNMetadata(
        event: "Test",
        site: "Test",
        white: "White",
        black: "Black"
    )

    func testOpeningDiagramDisplayUsesStoredECOAndName() {
        let game = RecordedGame(
            moves: [],
            round: 1,
            result: .ongoing,
            eco: "C50",
            openingName: "Italian Game",
            metadata: metadata
        )
        XCTAssertEqual(
            GameReportPDFComposer.openingDiagramDisplay(for: game),
            OpeningDisplay(eco: "C50", name: "Italian Game")
        )
    }

    func testOpeningDiagramDisplayFallsBackToStarting() {
        let game = RecordedGame(
            moves: [],
            round: 1,
            result: .ongoing,
            metadata: metadata
        )
        XCTAssertEqual(
            GameReportPDFComposer.openingDiagramDisplay(for: game),
            OpeningDisplay.starting
        )
    }

    func testMakeKeyPositionsSplitsOpeningECOAndName() {
        let game = ChessGame()
        XCTAssertTrue(game.executeSAN("e4"))
        XCTAssertTrue(game.executeSAN("e5"))
        XCTAssertTrue(game.executeSAN("Nf3"))
        XCTAssertTrue(game.executeSAN("Nc6"))
        XCTAssertTrue(game.executeSAN("Bb5"))
        let moves = game.moves
        let fens = game.fenSequenceFromStart()
        let summary = GameAccuracySummary(moves: moves)

        let diagrams = GameReportPDFComposer.makeKeyPositions(
            moves: moves,
            summary: summary,
            fens: fens,
            lastInBookPly: 4,
            opening: OpeningDisplay(eco: "C65", name: "Ruy Lopez")
        )

        XCTAssertFalse(diagrams.contains(where: { $0.title == "Middlegame" }))
        guard let opening = diagrams.first(where: { $0.title == "C65" }) else {
            return XCTFail("Expected opening diagram titled with ECO code")
        }
        XCTAssertEqual(opening.secondaryTitle, "Ruy Lopez")
        XCTAssertEqual(opening.afterMoveIndex, 3)
        XCTAssertEqual(opening.fen, fens[4])
        XCTAssertEqual(
            diagrams.filter { $0.title == "Final position" }.count,
            1,
            "Final position should be added when not already covered"
        )
    }

    func testMakeKeyPositionsSkipsDuplicateFinalWhenLastPlyAlreadyUsed() {
        // Last move is a blunder → critical marker owns the final ply.
        let game = ChessGame()
        XCTAssertTrue(game.executeSAN("e4"))
        XCTAssertTrue(game.executeSAN("e5"))
        let moves = [
            game.moves[0].withQuality(.good, centipawnLoss: 0),
            game.moves[1].withQuality(.blunder, centipawnLoss: 400)
        ]
        let summary = GameAccuracySummary(moves: moves)
        XCTAssertTrue(summary.evaluationCriticalPlies.contains { $0.ply == 2 })

        let fens = ChessGameBackgroundPreparation.fenSequence(from: moves)
        let diagrams = GameReportPDFComposer.makeKeyPositions(
            moves: moves,
            summary: summary,
            fens: fens,
            lastInBookPly: 0,
            opening: .starting
        )

        let finalPlyDiagrams = diagrams.filter { $0.afterMoveIndex == moves.count - 1 }
        XCTAssertEqual(finalPlyDiagrams.count, 1, "Last ply should appear only once")
        XCTAssertFalse(
            diagrams.contains(where: { $0.title == "Final position" }),
            "Final position must not duplicate an existing last-ply diagram"
        )
    }

    func testMakeKeyPositionsIncludesEndgameType() {
        let start =
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let rookEndgame = "4r1k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"
        var fens = Array(repeating: start, count: 8)
        fens[5] = rookEndgame
        fens[6] = rookEndgame
        fens[7] = rookEndgame

        let moves = (0..<7).map { _ in
            ChessMove(
                san: "e4",
                piece: .pawn,
                from: ChessPosition(file: 4, rank: 1),
                to: ChessPosition(file: 4, rank: 3),
                captures: false,
                isCheck: false,
                isCheckmate: false,
                promotion: nil,
                castling: nil,
                quality: .good,
                centipawnLoss: 0
            )
        }
        let summary = GameAccuracySummary(
            moves: moves,
            fenSequence: fens,
            lastInBookPly: 1
        )
        XCTAssertEqual(summary.endgameType, .rook)

        let diagrams = GameReportPDFComposer.makeKeyPositions(
            moves: moves,
            summary: summary,
            fens: fens,
            lastInBookPly: 1,
            opening: OpeningDisplay(eco: "C50", name: "Italian Game")
        )

        guard let endgame = diagrams.first(where: { $0.title == "Endgame" }) else {
            return XCTFail("Expected endgame diagram")
        }
        XCTAssertEqual(endgame.secondaryTitle, "Rook")
        XCTAssertEqual(endgame.fen, rookEndgame)
    }
}
