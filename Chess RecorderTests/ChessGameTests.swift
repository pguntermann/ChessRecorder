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
        // 1.e4 e5 2.Nf3 Nc6 3.Nc3 Nf6 4.d4 exd4 — both white knights can recapture on d4.
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

    func testExecuteVoiceCandidatesPrefersFirstLegalMatch() {
        let game = ChessGame()
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
            XCTAssertTrue(game.performMove(from: from, to: to))
        }

        XCTAssertEqual(game.executeVoiceCandidates(["Nfxd4", "Ncxd4"]), "Nxd4")
        XCTAssertEqual(game.moves.last?.from.notation, "f3")
    }

    func testExecuteVoiceCandidatesUsesDisambiguatedCapture() {
        let game = ChessGame()
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
            XCTAssertTrue(game.performMove(from: from, to: to))
        }

        XCTAssertEqual(game.executeVoiceCandidates(["Nfxd4"]), "Nxd4")
        XCTAssertEqual(game.moves.last?.from.notation, "f3")
    }
}
