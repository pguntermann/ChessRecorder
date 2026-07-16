import XCTest
@testable import Chess_Recorder

@MainActor
final class PGNArchiveTests: XCTestCase {

    private let testMetadata = PGNMetadata.placeholder

    private func playE4E5(on game: ChessGame) {
        XCTAssertTrue(
            game.performMove(from: ChessPosition(file: 4, rank: 1), to: ChessPosition(file: 4, rank: 3))
        )
        XCTAssertTrue(
            game.performMove(from: ChessPosition(file: 4, rank: 6), to: ChessPosition(file: 4, rank: 4))
        )
    }

    func testFinalizeCapturesMetadataForFinishedGameAndNewSlot() {
        let firstMetadata = PGNMetadata(event: "Round 1", site: "Hall A", white: "Alice", black: "Bob")
        let secondMetadata = PGNMetadata(event: "Round 2", site: "Hall B", white: "Bob", black: "Alice")

        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists(metadata: firstMetadata)
        playE4E5(on: game)
        archive.syncActiveGame(from: game, metadata: firstMetadata)
        let firstID = archive.activeGameID!

        archive.finalizeActiveGame(with: .whiteWins, from: game, metadataForNewGame: secondMetadata)
        game.resetGame()

        let finished = archive.games.first { $0.id == firstID }!
        let ongoing = archive.games.first { $0.id == archive.activeGameID }!

        XCTAssertEqual(finished.metadata, firstMetadata)
        XCTAssertEqual(ongoing.metadata, secondMetadata)
    }

    func testSyncActiveGameDoesNotOverwriteArchivedGame() {
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists(metadata: testMetadata)
        playE4E5(on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)

        let archivedID = archive.activeGameID!
        archive.finalizeActiveGame(with: .draw, from: game, metadataForNewGame: testMetadata)
        XCTAssertEqual(archive.games.first { $0.id == archivedID }?.moves.count, 2)

        game.resetGame()
        archive.setActiveGame(id: archivedID)
        _ = game.loadMainLine(moves: archive.games.first { $0.id == archivedID }!.moves)

        XCTAssertTrue(
            game.performMove(from: ChessPosition(file: 1, rank: 0), to: ChessPosition(file: 2, rank: 2))
        )
        archive.syncActiveGame(from: game, metadata: testMetadata)

        XCTAssertEqual(archive.games.first { $0.id == archivedID }?.moves.count, 2)
        XCTAssertEqual(archive.games.first { $0.id == archivedID }?.moves.first?.san, "e4")
    }

    func testSwitchingBetweenArchivedAndOngoingPreservesArchivedMoves() {
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists(metadata: testMetadata)
        playE4E5(on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        let archivedID = archive.activeGameID!

        archive.finalizeActiveGame(with: .whiteWins, from: game, metadataForNewGame: testMetadata)
        game.resetGame()
        let ongoingID = archive.activeGameID!
        XCTAssertNotEqual(archivedID, ongoingID)

        let archivedMoves = archive.games.first { $0.id == archivedID }!.moves
        XCTAssertEqual(archivedMoves.count, 2)

        archive.setActiveGame(id: archivedID)
        _ = game.loadMainLine(moves: archivedMoves)
        game.declareResult(.whiteWins)

        archive.setActiveGame(id: ongoingID)
        _ = game.loadMainLine(moves: archive.games.first { $0.id == ongoingID }!.moves)

        XCTAssertTrue(
            game.performMove(from: ChessPosition(file: 6, rank: 0), to: ChessPosition(file: 5, rank: 2))
        )
        archive.syncActiveGame(from: game, metadata: testMetadata)

        let archivedAfter = archive.games.first { $0.id == archivedID }!
        let ongoingAfter = archive.games.first { $0.id == ongoingID }!

        XCTAssertEqual(archivedAfter.moves.count, 2)
        XCTAssertEqual(archivedAfter.moves.map(\.san), ["e4", "e5"])
        XCTAssertEqual(ongoingAfter.moves.count, 1)
        XCTAssertEqual(ongoingAfter.moves.first?.san, "Nf3")
    }

    func testActivateArchivedGameAfterDeclareResultAndNewGame() {
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists(metadata: testMetadata)
        playE4E5(on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        let archivedID = archive.activeGameID!

        game.declareResult(.whiteWins)
        archive.syncActiveGame(from: game, metadata: testMetadata)

        archive.finalizeActiveGame(with: .whiteWins, from: game, metadataForNewGame: testMetadata)
        game.resetGame()

        let archived = archive.games.first { $0.id == archivedID }!
        XCTAssertEqual(archived.moves.count, 2)
        XCTAssertEqual(archived.result, .whiteWins)

        archive.setActiveGame(id: archivedID)
        XCTAssertTrue(game.loadMainLine(moves: archived.moves))
        game.declareResult(.whiteWins)

        XCTAssertEqual(game.moves.count, 2)
        XCTAssertEqual(game.moves.map(\.san), ["e4", "e5"])
        XCTAssertTrue(game.isGameOver)
    }

    func testFinalizePreservesArchiveMovesWhenLiveBoardIsEmpty() {
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists(metadata: testMetadata)
        playE4E5(on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        let archivedID = archive.activeGameID!

        game.resetGame()
        archive.finalizeActiveGame(with: .whiteWins, from: game, metadataForNewGame: testMetadata)

        let archived = archive.games.first { $0.id == archivedID }!
        XCTAssertEqual(archived.moves.count, 2)
        XCTAssertEqual(archived.result, .whiteWins)
    }

    func testLoadMainLineReplaysFromStoredCoordinates() {
        let game = ChessGame()
        XCTAssertTrue(game.performMove(from: ChessPosition(file: 4, rank: 1), to: ChessPosition(file: 4, rank: 3)))

        let storedMove = game.moves[0]
        var replayGame = ChessGame()
        replayGame.resetGame()

        let replayMove = ChessMove(
            san: "invalid-but-coordinates-work",
            piece: storedMove.piece,
            from: storedMove.from,
            to: storedMove.to,
            captures: storedMove.captures,
            isCheck: storedMove.isCheck,
            isCheckmate: storedMove.isCheckmate,
            promotion: storedMove.promotion,
            castling: storedMove.castling
        )

        XCTAssertTrue(replayGame.loadMainLine(moves: [replayMove]))
        XCTAssertEqual(replayGame.moves.count, 1)
        XCTAssertEqual(replayGame.moves.first?.san, "e4")
    }

    /// Regression: long recorded game → 1-0 → New Game → tap archived game must reload full board.
    /// Movetext from a real in-app reproduction (English Opening / Réti, white wins on move 32).
    func testActivateLongArchivedGameAfterWhiteWinsAndNewGame() {
        let sans = Self.reproducedLongGameSANs
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists(metadata: testMetadata)
        playSANLine(sans, on: game, archive: archive)
        XCTAssertEqual(game.moves.count, sans.count)

        let archivedID = archive.activeGameID!
        let archivedMoves = game.moves

        game.declareResult(.whiteWins)
        archive.syncActiveGame(from: game, metadata: testMetadata)

        archive.finalizeActiveGame(with: .whiteWins, from: game, metadataForNewGame: testMetadata)
        game.resetGame()

        let stored = archive.games.first { $0.id == archivedID }!
        XCTAssertEqual(stored.moves.count, sans.count)
        XCTAssertEqual(stored.result, .whiteWins)

        archive.setActiveGame(id: archivedID)
        XCTAssertTrue(
            game.loadMainLine(moves: stored.moves),
            "Archived game should reload all \(sans.count) moves"
        )
        game.declareResult(.whiteWins)

        XCTAssertEqual(game.moves.count, sans.count)
        XCTAssertEqual(game.moves.map(\.san), archivedMoves.map(\.san))
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.moves.last?.san, "h4#")
    }

    private func playSANLine(_ sans: [String], on game: ChessGame, archive: PGNArchive) {
        for (index, san) in sans.enumerated() {
            XCTAssertTrue(game.executeSAN(san), "Failed to play move \(index + 1): \(san)")
            archive.syncActiveGame(from: game, metadata: testMetadata)
        }
    }

    /// 1. Nf3 Nf6 2. d4 g6 … 32. h4# 1-0
    private static let reproducedLongGameSANs: [String] = [
        "Nf3", "Nf6", "d4", "g6", "e3", "c5", "Be2", "Bg7", "O-O", "O-O",
        "b3", "cxd4", "Nxd4", "d5", "Bb2", "Nbd7", "c4", "Qb6", "Nd2", "e6",
        "Rc1", "Qa5", "a3", "Rd8", "b4", "Qa6", "c5", "b5", "N2b3", "Rb8",
        "Na5", "Ne5", "f4", "Nc4", "Bxc4", "dxc4", "Ndc6", "Nd5", "Nxb8", "Qxa5",
        "bxa5", "Bxb2", "Rb1", "Bxa3", "Rxb5", "c3", "Rf2", "e5", "fxe5", "Bf5",
        "c6", "Be4", "Nd7", "Nxe3", "Nf6+", "Kg7", "Qxd8", "Bf5", "Qg8+", "Kh6",
        "Qxh7+", "Kg5", "h4#"
    ]

    func testApplyMoveAssessmentUpdatesStoredMove() {
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists(metadata: testMetadata)
        playE4E5(on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        let gameID = archive.activeGameID!

        XCTAssertTrue(
            archive.applyMoveAssessment(
                gameID: gameID,
                moveIndex: 0,
                quality: .good,
                expectedSAN: "e4"
            )
        )
        XCTAssertEqual(archive.games.first { $0.id == gameID }?.moves[0].quality, .good)
    }

    func testSyncActiveGamePreservesExistingMoveQualities() {
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists(metadata: testMetadata)
        playE4E5(on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        let gameID = archive.activeGameID!

        XCTAssertTrue(
            archive.applyMoveAssessment(
                gameID: gameID,
                moveIndex: 0,
                quality: .inaccuracy,
                expectedSAN: "e4"
            )
        )

        archive.syncActiveGame(from: game, metadata: testMetadata)

        XCTAssertEqual(archive.games.first { $0.id == gameID }?.moves[0].quality, .inaccuracy)
        XCTAssertNil(archive.games.first { $0.id == gameID }?.moves[1].quality)
    }

    func testExportedMovetextIncludesAssessmentSymbolsWhenEnabled() {
        let move = ChessMove(
            san: "Nf3",
            piece: .knight,
            from: ChessPosition(file: 6, rank: 0),
            to: ChessPosition(file: 5, rank: 2),
            captures: false,
            isCheck: false,
            isCheckmate: false,
            promotion: nil,
            castling: nil,
            quality: .mistake
        )

        let withoutSymbols = PGNFormatter.movetext(from: [move], result: .ongoing, includeAssessmentSymbols: false)
        let withSymbols = PGNFormatter.movetext(from: [move], result: .ongoing, includeAssessmentSymbols: true)

        XCTAssertEqual(withoutSymbols, "1. Nf3")
        XCTAssertEqual(withSymbols, "1. Nf3?")
    }
}
