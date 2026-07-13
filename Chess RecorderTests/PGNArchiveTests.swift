import XCTest
@testable import Chess_Recorder

@MainActor
final class PGNArchiveTests: XCTestCase {

    private func playE4E5(on game: ChessGame) {
        XCTAssertTrue(
            game.performMove(from: ChessPosition(file: 4, rank: 1), to: ChessPosition(file: 4, rank: 3))
        )
        XCTAssertTrue(
            game.performMove(from: ChessPosition(file: 4, rank: 6), to: ChessPosition(file: 4, rank: 4))
        )
    }

    func testSyncActiveGameDoesNotOverwriteArchivedGame() {
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists()
        playE4E5(on: game)
        archive.syncActiveGame(from: game)

        let archivedID = archive.activeGameID!
        archive.finalizeActiveGame(with: .draw, from: game)
        XCTAssertEqual(archive.games.first { $0.id == archivedID }?.moves.count, 2)

        game.resetGame()
        archive.setActiveGame(id: archivedID)
        _ = game.loadMainLine(moves: archive.games.first { $0.id == archivedID }!.moves)

        XCTAssertTrue(
            game.performMove(from: ChessPosition(file: 1, rank: 0), to: ChessPosition(file: 2, rank: 2))
        )
        archive.syncActiveGame(from: game)

        XCTAssertEqual(archive.games.first { $0.id == archivedID }?.moves.count, 2)
        XCTAssertEqual(archive.games.first { $0.id == archivedID }?.moves.first?.san, "e4")
    }

    func testSwitchingBetweenArchivedAndOngoingPreservesArchivedMoves() {
        let archive = PGNArchive()
        let game = ChessGame()

        archive.ensureActiveGameExists()
        playE4E5(on: game)
        archive.syncActiveGame(from: game)
        let archivedID = archive.activeGameID!

        archive.finalizeActiveGame(with: .whiteWins, from: game)
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
        archive.syncActiveGame(from: game)

        let archivedAfter = archive.games.first { $0.id == archivedID }!
        let ongoingAfter = archive.games.first { $0.id == ongoingID }!

        XCTAssertEqual(archivedAfter.moves.count, 2)
        XCTAssertEqual(archivedAfter.moves.map(\.san), ["e4", "e5"])
        XCTAssertEqual(ongoingAfter.moves.count, 1)
        XCTAssertEqual(ongoingAfter.moves.first?.san, "Nf3")
    }
}
