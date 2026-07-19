import XCTest
@testable import Chess_Recorder

@MainActor
final class ChessGameTests: XCTestCase {

    func testUndoLastMoveRemovesSingleMoveAndStaysAtLatest() {
        let game = ChessGame()
        XCTAssertTrue(game.performMove(from: ChessPosition(file: 4, rank: 1), to: ChessPosition(file: 4, rank: 3)))
        XCTAssertTrue(game.performMove(from: ChessPosition(file: 4, rank: 6), to: ChessPosition(file: 4, rank: 4)))

        XCTAssertTrue(game.undoLastMove())
        XCTAssertEqual(game.moves.count, 1)
        XCTAssertTrue(game.isAtLatestMove)
        XCTAssertTrue(game.canUndo)
        XCTAssertEqual(game.moves.last?.san, "e4")
    }

    func testUndoLastMoveReturnsToStartingPosition() {
        let game = ChessGame()
        XCTAssertTrue(game.performMove(from: ChessPosition(file: 4, rank: 1), to: ChessPosition(file: 4, rank: 3)))

        XCTAssertTrue(game.undoLastMove())
        XCTAssertTrue(game.moves.isEmpty)
        XCTAssertTrue(game.isAtLatestMove)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoAfterDisambiguatedCaptureUsesStoredMove() {
        let game = ChessGame()
        // 1.e4 e5 2.Nf3 Nc6 3.Nc3 Nf6 4.d4 exd4 — only Nf3 can recapture (Nc3 does not attack d4).
        // "Nfxd4" still resolves via file disambiguation in LegalMoveResolver.
        let setup: [(ChessPosition, ChessPosition)] = [
            (ChessPosition(file: 4, rank: 1), ChessPosition(file: 4, rank: 3)),
            (ChessPosition(file: 4, rank: 6), ChessPosition(file: 4, rank: 4)),
            (ChessPosition(file: 6, rank: 0), ChessPosition(file: 5, rank: 2)),
            (ChessPosition(file: 1, rank: 7), ChessPosition(file: 2, rank: 5)),
            (ChessPosition(file: 1, rank: 0), ChessPosition(file: 2, rank: 2)),
            (ChessPosition(file: 6, rank: 7), ChessPosition(file: 5, rank: 5)),
            (ChessPosition(file: 3, rank: 1), ChessPosition(file: 3, rank: 3)),
            (ChessPosition(file: 4, rank: 4), ChessPosition(file: 3, rank: 3))
        ]

        for (from, to) in setup {
            XCTAssertTrue(game.performMove(from: from, to: to), "Failed \(from.notation)\(to.notation)")
        }

        XCTAssertTrue(game.executeSAN("Nfxd4"), "Disambiguated capture should apply")
        XCTAssertEqual(game.moves.count, 9)
        XCTAssertEqual(game.moves.last?.from.notation, "f3")
        XCTAssertEqual(game.moves.last?.to.notation, "d4")

        XCTAssertTrue(game.undoLastMove(), "undo should truncate via stored kit moves")
        XCTAssertEqual(game.moves.count, 8)
        XCTAssertEqual(game.moves.last?.san, "exd4")
        XCTAssertTrue(game.isAtLatestMove)
    }

    func testLoadMainLineFailureRestoresPreviousState() {
        let game = ChessGame()
        XCTAssertTrue(game.performMove(from: ChessPosition(file: 4, rank: 1), to: ChessPosition(file: 4, rank: 3)))

        let invalidArchiveMove = ChessMove(
            san: "not-a-move",
            piece: .knight,
            from: ChessPosition(file: 0, rank: 0),
            to: ChessPosition(file: 0, rank: 0),
            captures: false,
            isCheck: false,
            isCheckmate: false,
            promotion: nil,
            castling: nil
        )

        XCTAssertFalse(game.loadMainLine(moves: [invalidArchiveMove]))
        XCTAssertEqual(game.moves.count, 1)
        XCTAssertEqual(game.moves.last?.san, "e4")
        XCTAssertTrue(game.isAtLatestMove)
    }

    private func setupAmbiguousKnightCaptureOnD4(_ game: ChessGame) {
        // Clear d2, park knights on b3 and f3, then push a black pawn to d4.
        // Both knights attack d4 → Nfxd4 / Nbxd4.
        let setup: [(ChessPosition, ChessPosition)] = [
            (ChessPosition(file: 3, rank: 1), ChessPosition(file: 3, rank: 2)), // d3
            (ChessPosition(file: 4, rank: 6), ChessPosition(file: 4, rank: 4)), // e5
            (ChessPosition(file: 6, rank: 0), ChessPosition(file: 5, rank: 2)), // Nf3
            (ChessPosition(file: 1, rank: 7), ChessPosition(file: 2, rank: 5)), // Nc6
            (ChessPosition(file: 1, rank: 0), ChessPosition(file: 2, rank: 2)), // Nc3
            (ChessPosition(file: 6, rank: 7), ChessPosition(file: 5, rank: 5)), // Nf6
            (ChessPosition(file: 2, rank: 2), ChessPosition(file: 4, rank: 3)), // Ne4
            (ChessPosition(file: 3, rank: 6), ChessPosition(file: 3, rank: 4)), // d5
            (ChessPosition(file: 4, rank: 3), ChessPosition(file: 3, rank: 1)), // Nd2
            (ChessPosition(file: 3, rank: 4), ChessPosition(file: 3, rank: 3)), // d4
            (ChessPosition(file: 3, rank: 1), ChessPosition(file: 1, rank: 2)), // Nb3
            (ChessPosition(file: 0, rank: 6), ChessPosition(file: 0, rank: 5))  // a6
        ]
        for (from, to) in setup {
            XCTAssertTrue(game.performMove(from: from, to: to), "Failed \(from.notation)\(to.notation)")
        }
    }

    func testExecuteVoiceCandidatesPrefersFirstLegalMatch() {
        let game = ChessGame()
        setupAmbiguousKnightCaptureOnD4(game)

        XCTAssertEqual(game.executeVoiceCandidates(["Nfxd4", "Nbxd4"]), "Nfxd4")
        XCTAssertEqual(game.moves.last?.from.notation, "f3")
        XCTAssertEqual(game.moves.last?.san, "Nfxd4")
    }

    func testDisambiguatedKnightCaptureStoresFileInSAN() {
        let game = ChessGame()
        setupAmbiguousKnightCaptureOnD4(game)

        let f3Dest = game.legalDestinations(from: ChessPosition(file: 5, rank: 2)).map(\.notation)
        let b3Dest = game.legalDestinations(from: ChessPosition(file: 1, rank: 2)).map(\.notation)
        XCTAssertTrue(f3Dest.contains("d4"), "Nf3 should reach d4, got \(f3Dest)")
        XCTAssertTrue(b3Dest.contains("d4"), "Nb3 should reach d4, got \(b3Dest)")

        XCTAssertTrue(game.performMove(
            from: ChessPosition(file: 5, rank: 2),
            to: ChessPosition(file: 3, rank: 3)
        ))
        XCTAssertEqual(
            game.moves.last?.san,
            "Nfxd4",
            "Ambiguous knight capture must include the origin file in PGN/SAN"
        )

        let movetext = PGNFormatter.movetext(from: game.moves)
        XCTAssertTrue(movetext.contains("Nfxd4"), "PGN export must keep capture disambiguation: \(movetext)")
    }

    func testExecuteVoiceCandidatesUsesDisambiguatedCapture() {
        let game = ChessGame()
        setupAmbiguousKnightCaptureOnD4(game)

        XCTAssertEqual(game.executeVoiceCandidates(["Nfxd4"]), "Nfxd4")
        XCTAssertEqual(game.moves.last?.from.notation, "f3")
        XCTAssertEqual(game.moves.last?.san, "Nfxd4")
    }


    func testPrepareTransferAppliesOffMainReplayOntoLiveGame() async {
        let source = ChessGame()
        XCTAssertTrue(source.performMove(from: ChessPosition(file: 4, rank: 1), to: ChessPosition(file: 4, rank: 3)))
        XCTAssertTrue(source.performMove(from: ChessPosition(file: 4, rank: 6), to: ChessPosition(file: 4, rank: 4)))
        let archivedMoves = source.moves

        struct Input: @unchecked Sendable {
            let moves: [ChessMove]
        }
        let input = Input(moves: archivedMoves)
        let transfer = await Task.detached(priority: .userInitiated) {
            ChessGameBackgroundPreparation.prepareTransfer(from: input.moves, result: .ongoing)
        }.value

        let live = ChessGame()
        XCTAssertTrue(live.performMove(from: ChessPosition(file: 6, rank: 0), to: ChessPosition(file: 5, rank: 2)))
        live.applyPreparedTransfer(transfer)

        XCTAssertEqual(live.moves.count, 2)
        XCTAssertEqual(live.moves.map(\.san), ["e4", "e5"])
        XCTAssertTrue(live.isAtLatestMove)
        XCTAssertEqual(live.fen(), source.fen())
    }
}
