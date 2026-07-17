//
//  PGNImportServiceTests.swift
//  Chess RecorderTests
//

import XCTest
@testable import Chess_Recorder

@MainActor
final class PGNImportServiceTests: XCTestCase {
    private let metadata = PGNMetadata(
        event: "Chess Recorder Session",
        site: "Test Site",
        white: "White Player",
        black: "Black Player"
    )

    func testSplitGamesHandlesExportedMultiGamePGN() {
        let game1 = PGNFormatter.formatGame(
            moves: [
                ChessMove(
                    san: "e4",
                    piece: .pawn,
                    from: ChessPosition(file: 4, rank: 1),
                    to: ChessPosition(file: 4, rank: 3),
                    captures: false,
                    isCheck: false,
                    isCheckmate: false,
                    promotion: nil,
                    castling: nil
                )
            ],
            round: 1,
            result: .ongoing,
            metadata: metadata
        )
        let game2 = PGNFormatter.formatGame(
            moves: [
                ChessMove(
                    san: "d4",
                    piece: .pawn,
                    from: ChessPosition(file: 3, rank: 1),
                    to: ChessPosition(file: 3, rank: 3),
                    captures: false,
                    isCheck: false,
                    isCheckmate: false,
                    promotion: nil,
                    castling: nil
                ),
                ChessMove(
                    san: "d5",
                    piece: .pawn,
                    from: ChessPosition(file: 3, rank: 6),
                    to: ChessPosition(file: 3, rank: 4),
                    captures: false,
                    isCheck: false,
                    isCheckmate: false,
                    promotion: nil,
                    castling: nil
                )
            ],
            round: 2,
            result: .draw,
            metadata: metadata,
            eco: "D00"
        )

        let exported = [game1, game2].joined(separator: "\n\n")
        let split = PGNImportService.splitGames(in: exported)
        XCTAssertEqual(split.count, 2)
        XCTAssertTrue(split[0].contains("[Round \"1\"]"))
        XCTAssertTrue(split[1].contains("[Round \"2\"]"))
    }

    func testImportGamesRoundTripsExportedSession() throws {
        let archive = PGNArchive()
        let game = ChessGame()
        archive.ensureActiveGameExists(metadata: metadata)
        XCTAssertTrue(game.executeSAN("e4"))
        XCTAssertTrue(game.executeSAN("e5"))
        archive.syncActiveGame(from: game, metadata: metadata)
        archive.finalizeActiveGame(with: .whiteWins, from: game, metadataForNewGame: metadata)

        let exported = PGNExportService.fullPGN(for: archive)
        let imported = try PGNImportService.importGames(from: exported)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].moves.map(\.san), ["e4", "e5"])
        XCTAssertEqual(imported[0].result, .whiteWins)
        XCTAssertEqual(imported[0].metadata.white, "White Player")

        let restore = PGNArchive()
        restore.ensureActiveGameExists(metadata: metadata)
        let activeID = restore.activeGameID
        let added = restore.appendImportedGames(imported)
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(restore.activeGameID, activeID)
        XCTAssertEqual(restore.games.count, 2)
        XCTAssertEqual(restore.games.first?.moves.map(\.san), ["e4", "e5"])
        XCTAssertNil(restore.games.first?.moves[0].quality)
    }

    func testImportRejectsNonStandardStart() {
        let pgn = """
        [Event "Custom"]
        [Site "?"]
        [Date "2026.07.17"]
        [Round "1"]
        [White "?"]
        [Black "?"]
        [Result "*"]
        [SetUp "1"]
        [FEN "8/8/8/8/8/8/4P3/4K2k w - - 0 1"]

        1. e4
        """
        XCTAssertThrowsError(try PGNImportService.importGames(from: pgn)) { error in
            guard case PGNImportService.ImportError.nonStandardStart = error else {
                return XCTFail("Expected nonStandardStart, got \(error)")
            }
        }
    }
}
