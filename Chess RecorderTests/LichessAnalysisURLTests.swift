//
//  LichessAnalysisURLTests.swift
//  Chess RecorderTests
//

import XCTest
@testable import Chess_Recorder

final class LichessAnalysisURLTests: XCTestCase {
    func testCompactURLUsesUnderscoreSeparatedSAN() {
        let moves = [
            makeMove(san: "e4", from: "e2", to: "e4"),
            makeMove(san: "e5", from: "e7", to: "e5"),
            makeMove(san: "Nf3", piece: .knight, from: "g1", to: "f3")
        ]
        let url = LichessAnalysisURL.make(fromMoves: moves)
        XCTAssertEqual(url?.absoluteString, "https://lichess.org/analysis/pgn/e4_e5_Nf3")
    }

    func testCheckSymbolIsPercentEncoded() {
        let moves = [
            makeMove(san: "e4", from: "e2", to: "e4"),
            makeMove(san: "e5", from: "e7", to: "e5"),
            makeMove(san: "Qh5+", piece: .queen, from: "d1", to: "h5", isCheck: true)
        ]
        let url = LichessAnalysisURL.make(fromMoves: moves)
        XCTAssertEqual(url?.absoluteString, "https://lichess.org/analysis/pgn/e4_e5_Qh5%2B")
    }

    func testEmptyMovesReturnsNil() {
        XCTAssertNil(LichessAnalysisURL.make(fromMoves: []))
    }

    func testFinalResultAppended() {
        let url = LichessAnalysisURL.make(
            fromMoves: [makeMove(san: "e4", from: "e2", to: "e4")],
            result: .whiteWins
        )
        XCTAssertEqual(url?.absoluteString, "https://lichess.org/analysis/pgn/e4_1-0")
    }

    func testCanonicalSANUsesSquaresNotStoredPieceLetter() {
        // Speech may store a wrong piece letter while from/to are correct.
        let bogus = makeMove(
            san: "Rxe4",
            piece: .rook,
            from: "e2",
            to: "e4"
        )
        let url = LichessAnalysisURL.make(fromMoves: [bogus])
        XCTAssertEqual(url?.absoluteString, "https://lichess.org/analysis/pgn/e4")
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
