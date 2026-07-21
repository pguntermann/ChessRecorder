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
        var fens = Array(repeating: start, count: 8 + GamePhaseClassifier.endgameStabilityPlies)
        for ply in 5..<(5 + GamePhaseClassifier.endgameStabilityPlies) {
            fens[ply] = rookEndgame
        }

        let moves = (0..<(fens.count - 1)).map { _ in Self.dummyMove() }
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

    func testEndgameCutCaptionNotesTransitionalBecomingFinalType() {
        XCTAssertEqual(
            GameReportPDFComposer.endgameCutCaption(
                cutType: .transitional,
                finalType: .rookUnequalMinors
            ),
            GameReportPDFComposer.EndgameCutCaption(
                primary: "Transitional",
                becomesLine: "(becomes: \(EndgameType.rookUnequalMinors.displayName))"
            )
        )
        XCTAssertEqual(
            GameReportPDFComposer.endgameCutCaption(
                cutType: .generic,
                finalType: .rookUnequalMinors
            ),
            GameReportPDFComposer.EndgameCutCaption(
                primary: "Generic",
                becomesLine: "(becomes: \(EndgameType.rookUnequalMinors.displayName))"
            )
        )
        XCTAssertEqual(
            GameReportPDFComposer.endgameCutCaption(
                cutType: .strongImbalance,
                finalType: .rook
            ),
            GameReportPDFComposer.EndgameCutCaption(
                primary: "Strong Material Imbalance",
                becomesLine: "(becomes: Rook)"
            )
        )
        XCTAssertEqual(
            GameReportPDFComposer.endgameCutCaption(
                cutType: .strongImbalance,
                finalType: .rook,
                becomesAfterPly: 79
            ),
            GameReportPDFComposer.EndgameCutCaption(
                primary: "Strong Material Imbalance",
                becomesLine: "(becomes: Rook - after 40.)"
            )
        )
        XCTAssertEqual(
            GameReportPDFComposer.endgameCutCaption(
                cutType: .generic,
                finalType: .rookUnequalMinors,
                becomesAfterPly: 70
            ),
            GameReportPDFComposer.EndgameCutCaption(
                primary: "Generic",
                becomesLine: "(becomes: \(EndgameType.rookUnequalMinors.displayName) - after 35...)"
            )
        )
        XCTAssertEqual(
            GameReportPDFComposer.endgameCutCaption(cutType: .rook, finalType: .rook),
            GameReportPDFComposer.EndgameCutCaption(primary: "Rook", becomesLine: nil)
        )
    }

    func testUserReportedGameEndgameCaption() throws {
        let pgn = """
        [Event "Chess Recorder"]
        [Site "?"]
        [Date "2026.07.17"]
        [Round "9"]
        [White "?"]
        [Black "?"]
        [Result "*"]
        [ECO "B27"]

        1. e4 c5 2. c3 g6 3. Nf3 Bg7 4. d4 cxd4 5. cxd4 e6 6. Bg5 Ne7 7. Nc3 b6 8. a3 Bb7 9. Bd3 O-O 10. O-O Nbc6 11. Nb5 a6 12. Nd6 Rb8 13. Nxb7 Rxb7 14. Bxa6 Ra7 15. Bb5 Qb8 16. d5 exd5 17. exd5 Nd4 18. Nxd4 Nxd5 19. Qb3 Qe5 20. Rad1 Qxg5 21. Nf3 Qf6 22. Rxd5 Qxb2 23. Qxb2 Bxb2 24. Rfd1 Bxa3 25. Bxd7 Bc5 26. Ne5 Ra2 27. h3 Bxf2+ 28. Kf1 Bg3 29. Nc4 Rf2+ 30. Kg1 Ra8 31. R5d3 Bh4 32. R1d2 Ra1+ 33. Rd1 Raa2 34. R3d2 Raxd2 35. Nxd2 f5 36. Be6+
        """
        let imported = try PGNImportService.importGames(from: pgn)
        let moves = imported[0].moves
        let fens = ChessGameBackgroundPreparation.fenSequence(from: moves)
        let summary = GameAccuracySummary(moves: moves, fenSequence: fens, lastInBookPly: 0)
        XCTAssertEqual(summary.endgameType, .rookUnequalMinors)

        guard let cut = summary.evaluationPhaseTransitions.first(where: { $0.kind == .endgame })?.ply else {
            return XCTFail("Expected endgame transition")
        }
        let cutType = GamePhaseClassifier.classifyEndgame(fen: fens[cut])
        XCTAssertEqual(cutType, .rookUnequalMinors)

        let diagrams = GameReportPDFComposer.makeKeyPositions(
            moves: moves,
            summary: summary,
            fens: fens,
            lastInBookPly: 0,
            opening: OpeningDisplay(eco: "B27", name: "Sicilian")
        )
        let endgames = diagrams.filter { $0.title == "Endgame" }
        XCTAssertFalse(endgames.isEmpty)
        XCTAssertEqual(endgames[0].secondaryTitle, EndgameType.rookUnequalMinors.displayName)
        XCTAssertNil(endgames[0].tertiaryTitle)
        XCTAssertEqual(endgames[0].fen, fens[cut])
    }

    func testStrongImbalanceCutNotesBecomesRook() throws {
        let pgn = """
        [Event "Chess Recorder"]
        [Site "?"]
        [Date "2026.07.16"]
        [Round "8"]
        [White "?"]
        [Black "?"]
        [Result "*"]
        [ECO "D04"]

        1. Nf3 Nf6 2. d4 d5 3. e3 c6 4. Be2 g6 5. O-O Bg7 6. b3 O-O 7. Bb2 Nbd7 8. c4 e6 9. Nbd2 a5 10. a3 dxc4 11. bxc4 Re8 12. Nb3 Qb6 13. Rc1 a4 14. c5 Qxb3 15. Qxb3 axb3 16. Rc3 Ne4 17. Rxb3 Ndf6 18. h3 Nd5 19. Rd1 f5 20. h4 h6 21. Bc4 Kh7 22. g3 Ra4 23. Be2 g5 24. hxg5 hxg5 25. Kg2 Kg6 26. Rbd3 b5 27. cxb6 Nxb6 28. Rc1 Bb7 29. Nd2 Nxd2 30. Rxd2 Nd5 31. Rc5 Rb8 32. Rd3 Ba6 33. Rd2 Bxe2 34. Rxe2 Rb6 35. Kf3 Bf8 36. e4 Rb3+ 37. Kg2 Bxc5 38. exd5 Bxd4 39. Rxe6+ Kh5 40. Bxd4 Rxd4 41. Rxc6 Rxa3
        """
        let imported = try PGNImportService.importGames(from: pgn)
        let moves = imported[0].moves
        let fens = ChessGameBackgroundPreparation.fenSequence(from: moves)
        let summary = GameAccuracySummary(moves: moves, fenSequence: fens, lastInBookPly: 0)
        XCTAssertEqual(summary.endgameType, .rook)

        let cut = summary.evaluationPhaseTransitions.first { $0.kind == .endgame }!.ply
        let cutType = GamePhaseClassifier.classifyEndgame(fen: fens[cut])
        XCTAssertEqual(cutType, .rookPlusMinor)

        let diagrams = GameReportPDFComposer.makeKeyPositions(
            moves: moves,
            summary: summary,
            fens: fens,
            lastInBookPly: 0,
            opening: OpeningDisplay(eco: "D04", name: "Queen's Pawn")
        )
        let endgames = diagrams.filter { $0.title == "Endgame" }
        XCTAssertEqual(endgames[0].secondaryTitle, EndgameType.rookPlusMinor.displayName)
        let settled = GameReportPDFComposer.firstPly(matching: .rook, in: fens, from: cut)!
        XCTAssertEqual(
            endgames[0].tertiaryTitle,
            Self.expectedBecomesLine(for: .rook, afterPly: settled)
        )
    }

    func testMakeKeyPositionsAddsSettledEndgameWhenTransitionalGapIsLong() {
        let start =
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        // Q+B+N vs Q+B → transitional
        let transitional =
            "3q2k1/1b3ppp/8/8/8/1N6/1BQ2PPP/6K1 w - - 0 1"
        let unequal =
            "4r1k1/1b3ppp/8/8/8/1N6/1B3PPP/4R1K1 w - - 0 1"

        XCTAssertEqual(GamePhaseClassifier.classifyEndgame(fen: transitional), .transitional)
        XCTAssertEqual(GamePhaseClassifier.classifyEndgame(fen: unequal), .rookUnequalMinors)

        // Cut at ply 5; settled type first appears at ply 13 → gap 8 > 6.
        var fens = Array(repeating: start, count: 14)
        for ply in 5..<13 {
            fens[ply] = transitional
        }
        fens[13] = unequal

        let moves = (0..<13).map { _ in Self.dummyMove() }
        let summary = GameAccuracySummary(
            moves: moves,
            fenSequence: fens,
            lastInBookPly: 1
        )
        XCTAssertEqual(summary.endgameType, .rookUnequalMinors)

        let diagrams = GameReportPDFComposer.makeKeyPositions(
            moves: moves,
            summary: summary,
            fens: fens,
            lastInBookPly: 1,
            opening: .starting
        )
        let cutDiagrams = diagrams.filter { $0.title == "Endgame" }
        let finalEndgames = diagrams.filter { $0.title == "Final Endgame" }
        XCTAssertEqual(cutDiagrams.count, 1)
        XCTAssertEqual(finalEndgames.count, 1)
        XCTAssertEqual(cutDiagrams[0].secondaryTitle, "Transitional")
        XCTAssertEqual(
            cutDiagrams[0].tertiaryTitle,
            Self.expectedBecomesLine(for: .rookUnequalMinors, afterPly: 13)
        )
        XCTAssertEqual(cutDiagrams[0].fen, transitional)
        XCTAssertEqual(finalEndgames[0].secondaryTitle, EndgameType.rookUnequalMinors.displayName)
        XCTAssertNil(finalEndgames[0].tertiaryTitle)
        XCTAssertEqual(finalEndgames[0].fen, unequal)
    }

    func testMakeKeyPositionsSkipsSecondEndgameWhenGapIsShort() {
        let start =
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let transitional =
            "3q2k1/1b3ppp/8/8/8/1N6/1BQ2PPP/6K1 w - - 0 1"
        let unequal =
            "4r1k1/1b3ppp/8/8/8/1N6/1B3PPP/4R1K1 w - - 0 1"

        var fens = Array(repeating: start, count: 12)
        for ply in 5..<(5 + GamePhaseClassifier.endgameStabilityPlies) {
            fens[ply] = transitional
        }
        // Gap from cut (ply 5) to unequal (ply 9) is 4 plies — not more than 6.
        fens[9] = unequal
        fens[10] = unequal
        fens[11] = unequal

        let moves = (0..<(fens.count - 1)).map { _ in Self.dummyMove() }
        let summary = GameAccuracySummary(
            moves: moves,
            fenSequence: fens,
            lastInBookPly: 1
        )

        let diagrams = GameReportPDFComposer.makeKeyPositions(
            moves: moves,
            summary: summary,
            fens: fens,
            lastInBookPly: 1,
            opening: .starting
        )
        let endgames = diagrams.filter { $0.title == "Endgame" }
        XCTAssertEqual(endgames.count, 1)
        XCTAssertEqual(endgames[0].secondaryTitle, "Transitional")
        XCTAssertEqual(
            endgames[0].tertiaryTitle,
            Self.expectedBecomesLine(for: .rookUnequalMinors, afterPly: 9)
        )
    }

    private static func expectedBecomesLine(for type: EndgameType, afterPly: Int) -> String {
        let moveNumber = (afterPly + 1) / 2
        let after = afterPly % 2 == 1 ? "after \(moveNumber)." : "after \(moveNumber)..."
        return "(becomes: \(type.displayName) - \(after))"
    }

    private static func dummyMove() -> ChessMove {
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
}
