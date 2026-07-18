import XCTest
@testable import Chess_Recorder

// MARK: - SessionStore unit tests

final class SessionStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var store: SessionStore!

    override func setUpWithError() throws {
        temporaryDirectory = makeTemporaryDirectory()
        store = SessionStore(storageDirectory: temporaryDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        store = nil
        temporaryDirectory = nil
    }

    func testHasStoredSessionIsFalseForEmptyStore() {
        XCTAssertFalse(store.hasStoredSession)
    }

    func testFlushPersistsAndRestoreRoundTripsActiveGame() throws {
        let gameID = UUID()
        let snapshot = SessionSnapshot(
            activeGameID: gameID,
            games: [
                RecordedGame(
                    id: gameID,
                    moves: [SessionTestFixtures.makeE4Move()],
                    round: 1,
                    result: .ongoing,
                    eco: "B20",
                    openingName: "Sicilian Defense"
                )
            ]
        )

        store.flush(snapshot: snapshot)

        XCTAssertTrue(store.hasStoredSession)

        let restored = store.restoreSession()
        XCTAssertEqual(restored?.activeGameID, gameID)
        XCTAssertEqual(restored?.games.count, 1)
        XCTAssertEqual(restored?.games.first?.moves.count, 1)
        XCTAssertEqual(restored?.games.first?.moves.first?.san, "e4")
        XCTAssertEqual(restored?.games.first?.eco, "B20")
        XCTAssertEqual(restored?.games.first?.openingName, "Sicilian Defense")

        let index = try XCTUnwrap(SessionTestSupport.readIndex(in: temporaryDirectory))
        XCTAssertFalse(index.restoreInProgress)
    }

    func testFlushClearsSessionWhenSnapshotHasNoPersistableContent() {
        let snapshot = SessionSnapshot(
            activeGameID: UUID(),
            games: [
                RecordedGame(
                    id: UUID(),
                    moves: [],
                    round: 1,
                    result: .ongoing
                )
            ]
        )

        store.flush(snapshot: snapshot)
        XCTAssertFalse(store.hasStoredSession)
        XCTAssertTrue(SessionTestSupport.gameFileURLs(in: temporaryDirectory).isEmpty)
    }

    func testClearSessionRemovesStoredFiles() {
        store.flush(snapshot: SessionTestFixtures.snapshotWithSingleMove(san: "e4"))
        XCTAssertTrue(store.hasStoredSession)

        store.clearSession()
        XCTAssertFalse(store.hasStoredSession)
        XCTAssertNil(store.restoreSession())
        XCTAssertTrue(SessionTestSupport.gameFileURLs(in: temporaryDirectory).isEmpty)
    }

    func testRestoreReturnsNilForMissingIndex() {
        try? FileManager.default.createDirectory(
            at: SessionTestSupport.sessionRoot(in: temporaryDirectory),
            withIntermediateDirectories: true
        )

        XCTAssertNil(store.restoreSession())
        XCTAssertFalse(store.hasStoredSession)
    }

    func testRestoreReturnsNilForInvalidJSONIndex() throws {
        try SessionTestSupport.writeCorruptIndex("{ not valid json", in: temporaryDirectory)

        XCTAssertNil(store.restoreSession())
        XCTAssertFalse(store.hasStoredSession)
    }

    func testRestoreReturnsNilForTruncatedIndex() throws {
        try SessionTestSupport.writeCorruptIndex(
            "{\"version\":1,\"activeGameID\":null,\"gameIDs\":[",
            in: temporaryDirectory
        )

        XCTAssertNil(store.restoreSession())
        XCTAssertFalse(store.hasStoredSession)
    }

    func testRestoreDiscardsUnsupportedVersion() throws {
        store.flush(snapshot: SessionTestFixtures.snapshotWithSingleMove(san: "e4"))

        let indexURL = SessionTestSupport.indexURL(in: temporaryDirectory)
        let index = SessionIndexFile(
            version: 999,
            activeGameID: UUID(),
            gameIDs: [UUID()],
            restoreInProgress: false
        )
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)

        XCTAssertNil(store.restoreSession())
        XCTAssertFalse(store.hasStoredSession)
    }

    func testRestoreDiscardsSessionWhenRestoreInProgressMarkerIsSet() throws {
        store.flush(snapshot: SessionTestFixtures.snapshotWithSingleMove(san: "e4"))

        let indexURL = SessionTestSupport.indexURL(in: temporaryDirectory)
        let existing = try XCTUnwrap(SessionTestSupport.readIndex(in: temporaryDirectory))
        let corrupted = SessionIndexFile(
            version: existing.version,
            activeGameID: existing.activeGameID,
            gameIDs: existing.gameIDs,
            restoreInProgress: true
        )
        try JSONEncoder().encode(corrupted).write(to: indexURL, options: .atomic)

        XCTAssertNil(store.restoreSession())
        XCTAssertFalse(store.hasStoredSession)
    }

    func testRestoreDiscardsWhenAllReferencedGameFilesAreMissing() throws {
        let missingID = UUID()
        let index = SessionIndexFile(
            version: SessionIndexFile.currentVersion,
            activeGameID: missingID,
            gameIDs: [missingID],
            restoreInProgress: false
        )
        try SessionTestSupport.writeIndex(index, in: temporaryDirectory)

        XCTAssertNil(store.restoreSession())
        XCTAssertFalse(store.hasStoredSession)
    }

    func testRestoreDiscardsWhenEveryGameFileIsCorrupt() throws {
        let gameID = UUID()
        store.flush(snapshot: SessionTestFixtures.snapshot(id: gameID, sans: ["e4"]))

        let gameURL = SessionTestSupport.gameURL(for: gameID, in: temporaryDirectory)
        try Data("{}".utf8).write(to: gameURL, options: .atomic)

        XCTAssertNil(store.restoreSession())
        XCTAssertFalse(store.hasStoredSession)
    }

    func testRestoreSkipsUnreadableGameFiles() throws {
        let goodID = UUID()
        let badID = UUID()
        store.flush(
            snapshot: SessionSnapshot(
                activeGameID: goodID,
                games: [
                    RecordedGame(id: goodID, moves: [SessionTestFixtures.makeE4Move()], round: 2, result: .ongoing),
                    RecordedGame(id: badID, moves: [SessionTestFixtures.makeE4Move()], round: 1, result: .ongoing)
                ]
            )
        )

        try Data("not json".utf8).write(
            to: SessionTestSupport.gameURL(for: badID, in: temporaryDirectory),
            options: .atomic
        )

        let restored = store.restoreSession()
        XCTAssertEqual(restored?.games.count, 1)
        XCTAssertEqual(restored?.games.first?.id, goodID)
        XCTAssertEqual(restored?.activeGameID, goodID)
        XCTAssertEqual(try SessionTestSupport.readIndex(in: temporaryDirectory)?.gameIDs, [goodID])
    }

    func testRestoreSkipsGameWithInvalidResultField() throws {
        let validID = UUID()
        let invalidID = UUID()
        store.flush(
            snapshot: SessionSnapshot(
                activeGameID: validID,
                games: [
                    RecordedGame(id: validID, moves: [SessionTestFixtures.makeE4Move()], round: 2, result: .ongoing),
                    RecordedGame(id: invalidID, moves: [SessionTestFixtures.makeE4Move()], round: 1, result: .ongoing)
                ]
            )
        )

        let invalidStored = StoredRecordedGame(
            id: invalidID,
            moves: [SessionTestFixtures.storedMove(from: SessionTestFixtures.makeE4Move())],
            round: 1,
            result: "not-a-result",
            date: Date(),
            eco: nil,
            openingName: nil,
            event: nil,
            site: nil,
            white: nil,
            black: nil
        )
        try SessionTestSupport.writeStoredGame(invalidStored, in: temporaryDirectory)

        let restored = store.restoreSession()
        XCTAssertEqual(restored?.games.map(\.id), [validID])
    }

    func testRestoreSkipsGameWithInvalidMoveSquares() throws {
        let validID = UUID()
        let invalidID = UUID()
        store.flush(
            snapshot: SessionSnapshot(
                activeGameID: validID,
                games: [
                    RecordedGame(id: validID, moves: [SessionTestFixtures.makeE4Move()], round: 2, result: .ongoing),
                    RecordedGame(id: invalidID, moves: [SessionTestFixtures.makeE4Move()], round: 1, result: .ongoing)
                ]
            )
        )

        let invalidStored = StoredRecordedGame(
            id: invalidID,
            moves: [
                StoredChessMove(
                    san: "e4",
                    piece: "",
                    from: "bad",
                    to: "also-bad",
                    captures: false,
                    isCheck: false,
                    isCheckmate: false,
                    promotion: nil,
                    castling: nil,
                    quality: nil,
                    centipawnLoss: nil,
                    evaluationWhiteCentipawns: nil,
                    bestMoveSAN: nil
                )
            ],
            round: 1,
            result: PGNResult.ongoing.rawValue,
            date: Date(),
            eco: nil,
            openingName: nil,
            event: nil,
            site: nil,
            white: nil,
            black: nil
        )
        try SessionTestSupport.writeStoredGame(invalidStored, in: temporaryDirectory)

        let restored = store.restoreSession()
        XCTAssertEqual(restored?.games.map(\.id), [validID])
    }

    func testRestoreFallsBackWhenActiveGameFileIsMissing() throws {
        let fallbackID = UUID()
        let missingActiveID = UUID()
        store.flush(
            snapshot: SessionSnapshot(
                activeGameID: missingActiveID,
                games: [
                    RecordedGame(id: fallbackID, moves: [SessionTestFixtures.makeE4Move()], round: 1, result: .ongoing)
                ]
            )
        )

        let index = SessionIndexFile(
            version: SessionIndexFile.currentVersion,
            activeGameID: missingActiveID,
            gameIDs: [missingActiveID, fallbackID],
            restoreInProgress: false
        )
        try SessionTestSupport.writeIndex(index, in: temporaryDirectory)

        let restored = store.restoreSession()
        XCTAssertEqual(restored?.games.map(\.id), [fallbackID])
        XCTAssertEqual(restored?.activeGameID, fallbackID)
    }

    func testRestoreFallsBackWhenActiveGameIDIsUnknown() throws {
        let gameID = UUID()
        store.flush(snapshot: SessionTestFixtures.snapshot(id: gameID, sans: ["e4"]))

        let index = SessionIndexFile(
            version: SessionIndexFile.currentVersion,
            activeGameID: UUID(),
            gameIDs: [gameID],
            restoreInProgress: false
        )
        try SessionTestSupport.writeIndex(index, in: temporaryDirectory)

        let restored = store.restoreSession()
        XCTAssertEqual(restored?.activeGameID, gameID)
    }

    func testFlushRemovesOrphanedGameFiles() throws {
        let keptID = UUID()
        let orphanID = UUID()
        store.flush(
            snapshot: SessionSnapshot(
                activeGameID: keptID,
                games: [
                    RecordedGame(id: keptID, moves: [SessionTestFixtures.makeE4Move()], round: 1, result: .ongoing),
                    RecordedGame(id: orphanID, moves: [SessionTestFixtures.makeE4Move()], round: 2, result: .ongoing)
                ]
            )
        )
        XCTAssertEqual(SessionTestSupport.gameFileURLs(in: temporaryDirectory).count, 2)

        store.flush(snapshot: SessionTestFixtures.snapshot(id: keptID, sans: ["e4"]))

        let remaining = SessionTestSupport.gameFileURLs(in: temporaryDirectory)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.lastPathComponent, "\(keptID.uuidString).json")
    }

    func testSchedulePersistEventuallyWritesSnapshot() {
        store.schedulePersist(snapshot: SessionTestFixtures.snapshotWithSingleMove(san: "e4"))

        // schedulePersist hops onto ioQueue before starting the debounce timer, so waiting
        // exactly debounceInterval from the call site can lose the race under load.
        let expectation = expectation(description: "debounced persist")
        let deadline = Date().addingTimeInterval(SessionStore.debounceInterval + 2.0)
        func poll() {
            if store.hasStoredSession {
                expectation.fulfill()
            } else if Date() < deadline {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()

        wait(for: [expectation], timeout: SessionStore.debounceInterval + 3.0)
        XCTAssertTrue(store.hasStoredSession)
        XCTAssertEqual(store.restoreSession()?.games.first?.moves.first?.san, "e4")
    }

    func testDecodeGameWithoutMetadataFieldsUsesPlaceholder() {
        let stored = StoredRecordedGame(
            id: UUID(),
            moves: [SessionTestFixtures.storedMove(from: SessionTestFixtures.makeE4Move())],
            round: 1,
            result: PGNResult.ongoing.rawValue,
            date: Date(),
            eco: nil,
            openingName: nil,
            event: nil,
            site: nil,
            white: nil,
            black: nil
        )

        let decoded = SessionSnapshotCoding.decodeGame(stored)
        XCTAssertEqual(decoded?.metadata, PGNMetadata.placeholder)
    }

    func testEncodeDecodeRoundTripsPerGameMetadata() {
        let metadata = PGNMetadata(event: "Swiss", site: "Berlin", white: "Carlsen", black: "Nepo")
        let game = RecordedGame(
            id: UUID(),
            moves: [SessionTestFixtures.makeE4Move()],
            round: 3,
            result: .ongoing,
            metadata: metadata
        )

        let stored = SessionSnapshotCoding.encodeGame(game)
        let decoded = SessionSnapshotCoding.decodeGame(stored)

        XCTAssertEqual(decoded?.metadata, metadata)
    }
}

// MARK: - Archive + session integration tests

@MainActor
final class SessionArchiveIntegrationTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var store: SessionStore!
    private var archive: PGNArchive!
    private var game: ChessGame!
    private let testMetadata = PGNMetadata.placeholder

    override func setUpWithError() throws {
        temporaryDirectory = makeTemporaryDirectory()
        store = SessionStore(storageDirectory: temporaryDirectory)
        archive = PGNArchive()
        game = ChessGame()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        store = nil
        archive = nil
        game = nil
        temporaryDirectory = nil
    }

    func testDeleteGameRemovesGameFromStoredSession() throws {
        let (olderGameID, activeGameID) = setUpTwoGameArchive()

        _ = archive.removeGame(id: olderGameID)
        flushArchiveToDisk()

        let index = try XCTUnwrap(SessionTestSupport.readIndex(in: temporaryDirectory))
        XCTAssertEqual(index.gameIDs, [activeGameID])
        XCTAssertEqual(index.activeGameID, activeGameID)
        XCTAssertEqual(SessionTestSupport.gameFileURLs(in: temporaryDirectory).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: SessionTestSupport.gameURL(for: olderGameID, in: temporaryDirectory).path
        ))

        let restored = try XCTUnwrap(store.restoreSession())
        archive.applySessionSnapshot(restored)
        XCTAssertEqual(archive.games.count, 1)
        XCTAssertEqual(archive.activeGameID, activeGameID)
        XCTAssertEqual(archive.games.first?.moves.map(\.san), ["d4"])
    }

    func testDeleteInactiveGameKeepsActiveGameAndFiles() throws {
        let (olderGameID, activeGameID) = setUpTwoGameArchive()

        _ = archive.removeGame(id: olderGameID)
        flushArchiveToDisk()

        let index = try XCTUnwrap(SessionTestSupport.readIndex(in: temporaryDirectory))
        XCTAssertEqual(index.activeGameID, activeGameID)
        XCTAssertEqual(index.gameIDs, [activeGameID])

        let restored = try XCTUnwrap(store.restoreSession())
        XCTAssertEqual(restored.activeGameID, activeGameID)
        XCTAssertEqual(restored.games.count, 1)
        XCTAssertEqual(restored.games.first?.id, activeGameID)
    }

    func testDeleteLastGameWithContentClearsStoredSession() throws {
        let onlyID = setUpSingleGameArchive()
        _ = archive.removeGame(id: onlyID)

        flushArchiveToDisk()

        XCTAssertFalse(store.hasStoredSession)
        XCTAssertTrue(SessionTestSupport.gameFileURLs(in: temporaryDirectory).isEmpty)
    }

    func testClearArchiveRemovesStoredSession() throws {
        _ = setUpSingleGameArchive()
        flushArchiveToDisk()
        XCTAssertTrue(store.hasStoredSession)

        archive.resetAll()
        store.clearSession()

        XCTAssertFalse(store.hasStoredSession)
        XCTAssertTrue(SessionTestSupport.gameFileURLs(in: temporaryDirectory).isEmpty)
        XCTAssertNil(store.restoreSession())
    }

    func testClearArchiveViaEmptySnapshotRemovesStoredSession() throws {
        _ = setUpSingleGameArchive()
        flushArchiveToDisk()

        archive.resetAll()
        flushArchiveToDisk()

        XCTAssertFalse(store.hasStoredSession)
    }

    func testNewGamePersistsFinishedAndOngoingGames() throws {
        let firstID = setUpSingleGameArchive()
        archive.finalizeActiveGame(with: .whiteWins, from: game, metadataForNewGame: testMetadata)
        game.resetGame()
        SessionTestFixtures.playSANLine(["Nf3"], on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        let ongoingID = try XCTUnwrap(archive.activeGameID)

        flushArchiveToDisk()

        let index = try XCTUnwrap(SessionTestSupport.readIndex(in: temporaryDirectory))
        XCTAssertEqual(Set(index.gameIDs), Set([firstID, ongoingID]))
        XCTAssertEqual(index.activeGameID, ongoingID)

        let restored = try XCTUnwrap(store.restoreSession())
        archive.applySessionSnapshot(restored)
        XCTAssertEqual(archive.games.count, 2)

        let finished = archive.games.first { $0.id == firstID }
        let ongoing = archive.games.first { $0.id == ongoingID }
        XCTAssertEqual(finished?.result, .whiteWins)
        XCTAssertEqual(finished?.moves.map(\.san), ["e4", "e5"])
        XCTAssertEqual(ongoing?.result, .ongoing)
        XCTAssertEqual(ongoing?.moves.map(\.san), ["Nf3"])
    }

    func testTakebackUpdatesStoredMoveList() throws {
        _ = setUpSingleGameArchive()
        SessionTestFixtures.playSANLine(["Nf3", "Nc6"], on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        flushArchiveToDisk()

        XCTAssertTrue(game.undoLastMove())
        archive.syncActiveGame(from: game, metadata: testMetadata)
        flushArchiveToDisk()

        let restored = try XCTUnwrap(store.restoreSession())
        XCTAssertEqual(restored.games.first?.moves.map(\.san), ["e4", "e5", "Nf3"])

        let replayGame = ChessGame()
        XCTAssertTrue(replayGame.loadMainLine(moves: restored.games.first!.moves))
        XCTAssertEqual(replayGame.moves.count, 3)
    }

    func testPerGamePGNMetadataSurvivesSessionRestore() throws {
        let whiteAsWhite = PGNMetadata(event: "Club Night", site: "Table 1", white: "Alice", black: "Bob")
        let blackAsWhite = PGNMetadata(event: "Club Night", site: "Table 1", white: "Bob", black: "Alice")

        archive.ensureActiveGameExists(metadata: whiteAsWhite)
        SessionTestFixtures.playSANLine(["e4", "e5"], on: game)
        archive.syncActiveGame(from: game, metadata: whiteAsWhite)
        let firstID = try XCTUnwrap(archive.activeGameID)

        archive.finalizeActiveGame(with: .whiteWins, from: game, metadataForNewGame: blackAsWhite)
        game.resetGame()
        let secondID = try XCTUnwrap(archive.activeGameID)
        SessionTestFixtures.playSANLine(["d4"], on: game)
        archive.syncActiveGame(from: game, metadata: blackAsWhite)

        flushArchiveToDisk()

        let restored = try XCTUnwrap(store.restoreSession())
        archive.applySessionSnapshot(restored)

        let firstGame = archive.games.first { $0.id == firstID }
        let secondGame = archive.games.first { $0.id == secondID }
        XCTAssertEqual(firstGame?.metadata, whiteAsWhite)
        XCTAssertEqual(secondGame?.metadata, blackAsWhite)
    }

    func testRestoreAfterDeleteRoundTripsArchiveAndBoard() throws {
        let (olderGameID, activeGameID) = setUpTwoGameArchive()
        _ = archive.removeGame(id: olderGameID)
        flushArchiveToDisk()

        guard let snapshot = store.restoreSession() else {
            return XCTFail("Expected stored session")
        }

        let restoredArchive = PGNArchive()
        restoredArchive.applySessionSnapshot(snapshot)

        let restoredGame = ChessGame()
        guard let activeGame = restoredArchive.games.first(where: { $0.id == activeGameID }) else {
            return XCTFail("Expected active game in restored archive")
        }
        XCTAssertTrue(restoredGame.loadMainLine(moves: activeGame.moves))
        XCTAssertEqual(restoredGame.moves.map(\.san), ["d4"])
        XCTAssertEqual(restoredArchive.games.count, 1)
        XCTAssertNil(restoredArchive.games.first { $0.id == olderGameID })
    }

    func testRestoreRewritesCleanIndexAfterPartialCorruptionRecovery() throws {
        let goodID = UUID()
        let badID = UUID()
        store.flush(
            snapshot: SessionSnapshot(
                activeGameID: goodID,
                games: [
                    RecordedGame(id: goodID, moves: [SessionTestFixtures.makeE4Move()], round: 2, result: .ongoing),
                    RecordedGame(id: badID, moves: [SessionTestFixtures.makeE4Move()], round: 1, result: .ongoing)
                ]
            )
        )
        try Data("{}".utf8).write(
            to: SessionTestSupport.gameURL(for: badID, in: temporaryDirectory),
            options: .atomic
        )

        XCTAssertNotNil(store.restoreSession())

        let index = try XCTUnwrap(SessionTestSupport.readIndex(in: temporaryDirectory))
        XCTAssertFalse(index.restoreInProgress)
        XCTAssertEqual(index.gameIDs, [goodID])
        XCTAssertEqual(SessionTestSupport.gameFileURLs(in: temporaryDirectory).count, 1)
    }

    @discardableResult
    private func setUpSingleGameArchive() -> UUID {
        archive.ensureActiveGameExists(metadata: testMetadata)
        SessionTestFixtures.playSANLine(["e4", "e5"], on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        return archive.activeGameID!
    }

    @discardableResult
    private func setUpTwoGameArchive() -> (olderGameID: UUID, activeGameID: UUID) {
        let olderGameID = setUpSingleGameArchive()
        archive.finalizeActiveGame(with: .ongoing, from: game, metadataForNewGame: testMetadata)
        game.resetGame()
        SessionTestFixtures.playSANLine(["d4"], on: game)
        archive.syncActiveGame(from: game, metadata: testMetadata)
        return (olderGameID, archive.activeGameID!)
    }

    private func flushArchiveToDisk() {
        store.flush(snapshot: SessionSnapshot(archive: archive))
    }
}

// MARK: - Restore integration with board

@MainActor
final class SessionRestoreIntegrationTests: XCTestCase {
    func testArchiveAndGameRestoreFromSnapshot() {
        let archive = PGNArchive()
        let game = ChessGame()
        let gameID = UUID()

        archive.applySessionSnapshot(
            SessionSnapshot(
                activeGameID: gameID,
                games: [
                    RecordedGame(
                        id: gameID,
                        moves: [SessionTestFixtures.makeE4Move()],
                        round: 1,
                        result: .ongoing
                    )
                ]
            )
        )

        guard let recordedGame = archive.activeGame else {
            return XCTFail("Expected active game")
        }

        XCTAssertTrue(game.loadMainLine(moves: recordedGame.moves))
        XCTAssertEqual(game.moves.count, 1)
        XCTAssertEqual(game.moves.first?.san, "e4")
    }
}

// MARK: - Test support

private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "SessionStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private enum SessionTestFixtures {
    static func makeE4Move() -> ChessMove {
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
    }

    static func snapshotWithSingleMove(san: String) -> SessionSnapshot {
        snapshot(id: UUID(), sans: [san])
    }

    static func snapshot(id: UUID, sans: [String]) -> SessionSnapshot {
        let chessGame = ChessGame()
        playSANLine(sans, on: chessGame)
        return SessionSnapshot(
            activeGameID: id,
            games: [
                RecordedGame(
                    id: id,
                    moves: chessGame.moves,
                    round: 1,
                    result: .ongoing
                )
            ]
        )
    }

    static func playSANLine(_ sans: [String], on game: ChessGame) {
        for san in sans {
            XCTAssertTrue(game.executeSAN(san), "Failed to play \(san)")
        }
    }

    static func storedMove(from move: ChessMove) -> StoredChessMove {
        StoredChessMove(
            san: move.san,
            piece: move.piece.rawValue,
            from: move.from.notation,
            to: move.to.notation,
            captures: move.captures,
            isCheck: move.isCheck,
            isCheckmate: move.isCheckmate,
            promotion: move.promotion?.rawValue.isEmpty == false ? move.promotion?.rawValue : nil,
            castling: move.castling,
            quality: move.quality?.rawValue,
            centipawnLoss: move.centipawnLoss,
            evaluationWhiteCentipawns: move.evaluationWhiteCentipawns,
            bestMoveSAN: move.bestMoveSAN
        )
    }
}

private enum SessionTestSupport {
    static func sessionRoot(in base: URL) -> URL {
        base.appending(path: "UserSession", directoryHint: .isDirectory)
    }

    static func indexURL(in base: URL) -> URL {
        sessionRoot(in: base).appendingPathComponent("session.json")
    }

    static func gamesDirectory(in base: URL) -> URL {
        sessionRoot(in: base).appending(path: "games", directoryHint: .isDirectory)
    }

    static func gameURL(for id: UUID, in base: URL) -> URL {
        gamesDirectory(in: base).appendingPathComponent("\(id.uuidString).json")
    }

    static func readIndex(in base: URL) throws -> SessionIndexFile? {
        let url = indexURL(in: base)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SessionIndexFile.self, from: data)
    }

    static func writeIndex(_ index: SessionIndexFile, in base: URL) throws {
        try FileManager.default.createDirectory(at: gamesDirectory(in: base), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL(in: base), options: .atomic)
    }

    static func writeCorruptIndex(_ contents: String, in base: URL) throws {
        try FileManager.default.createDirectory(at: sessionRoot(in: base), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: indexURL(in: base), options: .atomic)
    }

    static func writeStoredGame(_ stored: StoredRecordedGame, in base: URL) throws {
        let data = try JSONEncoder().encode(stored)
        try data.write(to: gameURL(for: stored.id, in: base), options: .atomic)
    }

    static func gameFileURLs(in base: URL) -> [URL] {
        let directory = gamesDirectory(in: base)
        guard FileManager.default.fileExists(atPath: directory.path),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
