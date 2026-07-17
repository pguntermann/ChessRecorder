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

    func testImportEnPassantCaptureInMovetext() throws {
        let pgn = """
        [Event "?"]
        [Site "?"]
        [Date "2024.01.15"]
        [Round "1"]
        [White "W"]
        [Black "B"]
        [Result "*"]

        1. e4 c5 2. Nf3 e6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 Nc6 6. Nxc6 bxc6 7. e5 Nd5 8. Ne4 Ba6 9. Bg5 Qa5+ 10. c3 h6 11. Bd2 f5 12. exf6
        """
        let imported = try PGNImportService.importGames(from: pgn)
        XCTAssertEqual(imported.count, 1)
        let last = imported[0].moves.last?.san ?? ""
        XCTAssertTrue(last.hasPrefix("exf6"), "Expected en passant SAN, got \(last)")
    }

    func testImportWrappedMovetextWithoutResultTag() throws {
        let pgn = """
        [Event "?"]
        [Site "?"]
        [Date "2024.01.15"]
        [Round "?"]
        [White "Engine (Level 2)"]
        [Black "Player"]

        1. e4 c5 2. Nf3 e6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 Nc6 6. Nxc6 bxc6 7. e5 Nd5 8.
        Ne4 Ba6 9. Bg5 Qa5+ 10. c3 h6 11. Bd2 f5 12. exf6 Nxf6 13. Nxf6+ gxf6 14. Bxa6
        Qxa6 15. Bf4 e5 16. Bc1 d5 17. Qg4 h5 18. Qf5 Bg7 19. Qg6+ Kf8 20. b3 Qb7 21.
        Ba3+ Kg8 22. Bc5 Qf7 23. Qg3 a6 24. O-O Rd8 25. Rfd1 Rh7 26. Rd2 Kh8 27. Re2
        Re8 28. Qd3 Bf8 29. Be3 e4 30. Qd4 Bh6 31. Bxh6 Rxh6 32. Rd1 Qg7 33. f3 f5 34.
        Qxg7+ Kxg7 35. Rde1 Rhe6 36. fxe4 dxe4 37. Rf1 Kg6 38. Kf2 Kg5 39. Ke3 c5 40.
        h4+ Kg4 41. Ref2 Rf6 42. b4 c4 43. Rf4+ Kg3 44. Rd1 Kxg2 45. Rf2+ Kg3 46. Rg1+
        Kh3 47. Kf4 e3 48. Re2 Rfe6 49. Kf3 Re4 50. b5 axb5 51. Rg3+ Kxh4 52. Rg7 Rg4
        53. Rh7 Kg5 54. Rg7+ Kh6 55. Rb7 Reg8 56. Rb6+ Kh7 57. a3 Rg3+ 58. Kf4 h4 59.
        Rb7+ R8g7 60. Rb6 h3 61. Re6 Rg2 62. R6xe3 h2 63. Re1 h1=Q 64. Re6 Rg1 65. R1e2
        0-1
        """
        let imported = try PGNImportService.importGames(from: pgn)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].moves.count, 129, "65 full moves → 129 plies (Black resigns before White's 65th reply completes a pair)")
        XCTAssertEqual(imported[0].metadata.white, "Engine (Level 2)")
        XCTAssertEqual(imported[0].metadata.black, "Player")
        XCTAssertEqual(imported[0].result, .blackWins)
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
