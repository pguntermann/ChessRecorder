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
        // Fool's mate — Qh4# so the rebuild keeps a check/mate suffix to encode.
        let moves = [
            makeMove(san: "f3", from: "f2", to: "f3"),
            makeMove(san: "e5", from: "e7", to: "e5"),
            makeMove(san: "g4", from: "g2", to: "g4"),
            makeMove(
                san: "Qh4#",
                piece: .queen,
                from: "d8",
                to: "h4",
                isCheck: true,
                isCheckmate: true
            )
        ]
        let url = LichessAnalysisURL.make(fromMoves: moves)
        XCTAssertEqual(url?.absoluteString, "https://lichess.org/analysis/pgn/f3_e5_g4_Qh4%23")
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
        isCheck: Bool = false,
        isCheckmate: Bool = false
    ) -> ChessMove {
        ChessMove(
            san: san,
            piece: piece,
            from: ChessPosition(notation: from)!,
            to: ChessPosition(notation: to)!,
            captures: false,
            isCheck: isCheck,
            isCheckmate: isCheckmate,
            promotion: nil,
            castling: nil
        )
    }
}
