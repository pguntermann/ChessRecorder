//
//  ChessComAnalysisURLTests.swift
//  Chess RecorderTests
//

import XCTest
@testable import Chess_Recorder

final class ChessComAnalysisURLTests: XCTestCase {
    func testBuildsAnalysisQueryURL() {
        let moves = [
            makeMove(san: "e4", from: "e2", to: "e4"),
            makeMove(san: "e5", from: "e7", to: "e5"),
            makeMove(san: "Nf3", piece: .knight, from: "g1", to: "f3")
        ]
        let url = ChessComAnalysisURL.make(fromMoves: moves)
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.chess.com/analysis?tab=analysis&pgn=1.%20e4%20e5%202.%20Nf3"
        )
    }

    func testDrawResultSlashIsPercentEncoded() {
        let url = ChessComAnalysisURL.make(
            fromMoves: [makeMove(san: "e4", from: "e2", to: "e4")],
            result: .draw
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.chess.com/analysis?tab=analysis&pgn=1.%20e4%201%2F2-1%2F2"
        )
    }

    func testEmptyMovesReturnsNil() {
        XCTAssertNil(ChessComAnalysisURL.make(fromMoves: []))
    }

    func testFinalResultAppended() {
        let url = ChessComAnalysisURL.make(
            fromMoves: [makeMove(san: "e4", from: "e2", to: "e4")],
            result: .whiteWins
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.chess.com/analysis?tab=analysis&pgn=1.%20e4%201-0"
        )
    }

    func testCanonicalSANUsesSquaresNotStoredPieceLetter() {
        let bogus = makeMove(
            san: "Rxe4",
            piece: .rook,
            from: "e2",
            to: "e4"
        )
        let url = ChessComAnalysisURL.make(fromMoves: [bogus])
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.chess.com/analysis?tab=analysis&pgn=1.%20e4"
        )
    }

    func testRespectsMaxCharacterCount() {
        let moves = [
            makeMove(san: "e4", from: "e2", to: "e4"),
            makeMove(san: "e5", from: "e7", to: "e5")
        ]
        XCTAssertNil(ChessComAnalysisURL.make(fromMoves: moves, maxCharacterCount: 40))
        XCTAssertNotNil(ChessComAnalysisURL.make(fromMoves: moves, maxCharacterCount: 200))
    }

    private func makeMove(
        san: String,
        piece: PieceType = .pawn,
        from: String,
        to: String,
        isCheck: Bool = false
    ) -> ChessMove {
        ChessMove(
            san: san,
            piece: piece,
            from: ChessPosition(notation: from)!,
            to: ChessPosition(notation: to)!,
            captures: false,
            isCheck: isCheck,
            isCheckmate: false,
            promotion: nil,
            castling: nil
        )
    }
}
