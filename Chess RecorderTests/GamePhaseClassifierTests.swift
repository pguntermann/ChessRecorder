import XCTest
@testable import Chess_Recorder

final class GamePhaseClassifierTests: XCTestCase {
    private let start =
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    func testStartingPositionIsNotEndgame() {
        XCTAssertNil(GamePhaseClassifier.classifyEndgame(fen: start))
    }

    func testRookEndgameClassification() {
        let fen = "4r1k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"
        XCTAssertEqual(GamePhaseClassifier.classifyEndgame(fen: fen), .rook)
    }

    func testPawnEndgameClassification() {
        let fen = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"
        XCTAssertEqual(GamePhaseClassifier.classifyEndgame(fen: fen), .pawn)
    }

    func testBoundariesUseBookExitAndCapture() {
        let game = ChessGame()
        XCTAssertTrue(game.executeSAN("e4"))
        XCTAssertTrue(game.executeSAN("e5"))
        XCTAssertTrue(game.executeSAN("Nf3"))
        XCTAssertTrue(game.executeSAN("Nc6"))
        XCTAssertTrue(game.executeSAN("Bb5"))
        let fens = game.fenSequenceFromStart()

        let boundsInBook = GamePhaseClassifier.boundaries(fenSequence: fens, lastInBookPly: fens.count - 1)
        XCTAssertNil(boundsInBook.middlegameStartPly, "Still fully in book → no middlegame yet")

        let boundsLeftBook = GamePhaseClassifier.boundaries(fenSequence: fens, lastInBookPly: 2)
        // Default opening plies (30) is past this short game → no middlegame marker yet.
        XCTAssertNil(boundsLeftBook.middlegameStartPly)
    }

    func testEndgameBeforeMiddlegameOmitsMiddlegameMarker() {
        let start =
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let endgame = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"
        // Long enough that the default opening cut (ply 30) would otherwise set middlegame.
        var fens = Array(repeating: start, count: 35)
        fens[5] = endgame

        let bounds = GamePhaseClassifier.boundaries(fenSequence: fens, lastInBookPly: 0)
        XCTAssertEqual(bounds.endgameStartPly, 5)
        XCTAssertNil(bounds.middlegameStartPly)
    }

    func testDoubleRookEndgameNotAbsorbedByGeneralRookRule() {
        let fen = "3rr1k1/5ppp/8/8/8/8/5PPP/3RR1K1 w - - 0 1"
        XCTAssertEqual(GamePhaseClassifier.classifyEndgame(fen: fen), .doubleRook)
    }

    func testPhaseBubbleShowsOpening() {
        let info = GamePhaseClassifier.phase(
            atPly: 0,
            fen: start,
            boundaries: .empty
        )
        XCTAssertEqual(info.kind, .opening)
        XCTAssertEqual(info.bubbleText, "Opening")
    }

    func testPhaseBubbleShowsEndgameType() {
        let fen = "4r1k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"
        let bounds = GamePhaseBoundaries(middlegameStartPly: 1, endgameStartPly: 2)
        let info = GamePhaseClassifier.phase(atPly: 5, fen: fen, boundaries: bounds)
        XCTAssertEqual(info.kind, .endgame)
        XCTAssertEqual(info.bubbleText, "Endgame · Rook")
        XCTAssertEqual(info.endgameType?.displayName, "Rook")
    }

    func testAsymmetricHeavyShortLabelStaysCloseToFullName() {
        XCTAssertEqual(EndgameType.asymmetricHeavy.displayName, "Asymmetric Heavy Piece")
        XCTAssertEqual(EndgameType.asymmetricHeavy.shortDisplayName, "Asym. Heavy")
        let info = GamePhaseInfo(kind: .endgame, endgameType: .asymmetricHeavy)
        XCTAssertEqual(info.bubbleText, "Endgame · Asym. Heavy")
    }

    func testFirstNonPawnCaptureDetectsPieceTrade() {
        let game = ChessGame()
        XCTAssertTrue(game.executeSAN("e4"))
        XCTAssertTrue(game.executeSAN("e5"))
        XCTAssertTrue(game.executeSAN("Nf3"))
        XCTAssertTrue(game.executeSAN("Nc6"))
        XCTAssertTrue(game.executeSAN("Nxe5"))
        let fens = game.fenSequenceFromStart()
        let capturePly = GamePhaseClassifier.firstNonPawnCapturePly(fenSequence: fens)
        // Nxe5 captures a pawn, not a piece — should be nil
        XCTAssertNil(capturePly)

        let game2 = ChessGame()
        XCTAssertTrue(game2.executeSAN("e4"))
        XCTAssertTrue(game2.executeSAN("e5"))
        XCTAssertTrue(game2.executeSAN("Nf3"))
        XCTAssertTrue(game2.executeSAN("Nc6"))
        XCTAssertTrue(game2.executeSAN("d4"))
        XCTAssertTrue(game2.executeSAN("exd4"))
        XCTAssertTrue(game2.executeSAN("Nxd4"))
        XCTAssertTrue(game2.executeSAN("Nxd4"))
        let fens2 = game2.fenSequenceFromStart()
        let pieceCapture = GamePhaseClassifier.firstNonPawnCapturePly(fenSequence: fens2)
        XCTAssertNotNil(pieceCapture)
        XCTAssertEqual(pieceCapture, 8) // after Black's Nxd4
    }
}
