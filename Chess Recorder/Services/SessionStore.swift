//
//  SessionStore.swift
//  Chess Recorder
//

import Foundation

/// Persists the in-progress user session to Application Support as JSON snapshots.
/// Writes are debounced during use and flushed synchronously when the app backgrounds.
final class SessionStore {
    static let debounceInterval: TimeInterval = 1.0

    private let rootDirectory: URL
    private let gamesDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let ioQueue: DispatchQueue

    private var pendingSnapshot: SessionSnapshot?
    private var debounceWorkItem: DispatchWorkItem?

    init(fileManager: FileManager = .default, storageDirectory: URL? = nil) {
        self.fileManager = fileManager

        let baseDirectory = storageDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDirectory = baseDirectory.appending(path: "UserSession", directoryHint: .isDirectory)
        gamesDirectory = rootDirectory.appending(path: "games", directoryHint: .isDirectory)
        indexURL = rootDirectory.appendingPathComponent("session.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        ioQueue = DispatchQueue(label: "com.chessrecorder.session-store", qos: .utility)

        try? fileManager.createDirectory(at: gamesDirectory, withIntermediateDirectories: true)
        Self.excludeFromBackup(url: rootDirectory)
    }

    var hasStoredSession: Bool {
        fileManager.fileExists(atPath: indexURL.path)
    }

    /// Schedules a debounced persist of the current snapshot.
    func schedulePersist(snapshot: SessionSnapshot) {
        ioQueue.async { [weak self] in
            self?.enqueuePersist(snapshot: snapshot)
        }
    }

    /// Writes the snapshot immediately on the calling thread. Used when backgrounding.
    func flush(snapshot: SessionSnapshot) {
        ioQueue.sync {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            pendingSnapshot = nil
            persist(snapshot: snapshot)
        }
    }

    /// Clears all persisted session data.
    func clearSession() {
        ioQueue.sync {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            pendingSnapshot = nil
            removePersistedSessionFiles()
        }
    }

    /// Loads a previously persisted session. Returns nil when no session exists or restore fails safely.
    func restoreSession() -> SessionSnapshot? {
        ioQueue.sync {
            restoreSessionOnIOQueue()
        }
    }

    // MARK: - Private

    private func enqueuePersist(snapshot: SessionSnapshot) {
        pendingSnapshot = snapshot
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let snapshot = self.pendingSnapshot else { return }
            self.pendingSnapshot = nil
            self.persist(snapshot: snapshot)
        }
        debounceWorkItem = workItem
        ioQueue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: workItem)
    }

    private func persist(snapshot: SessionSnapshot) {
        guard snapshot.hasPersistableContent else {
            removePersistedSessionFiles()
            return
        }

        do {
            try writeSession(snapshot: snapshot, restoreInProgress: false)
        } catch {
            print("SessionStore: failed to persist session — \(error.localizedDescription)")
        }
    }

    private func writeSession(snapshot: SessionSnapshot, restoreInProgress: Bool) throws {
        try fileManager.createDirectory(at: gamesDirectory, withIntermediateDirectories: true)

        let gameIDs = snapshot.games.map(\.id)
        let index = SessionIndexFile(
            version: SessionIndexFile.currentVersion,
            activeGameID: snapshot.activeGameID,
            gameIDs: gameIDs,
            restoreInProgress: restoreInProgress
        )

        try writeIndex(index)

        let persistedIDs = Set(gameIDs)
        for game in snapshot.games {
            try writeGame(SessionSnapshotCoding.encodeGame(game))
        }

        try removeOrphanedGameFiles(keeping: persistedIDs)
    }

    private func restoreSessionOnIOQueue() -> SessionSnapshot? {
        guard fileManager.fileExists(atPath: indexURL.path) else { return nil }

        guard let index = readIndex() else {
            print("SessionStore: unreadable session index; starting clean")
            removePersistedSessionFiles()
            return nil
        }

        guard index.version == SessionIndexFile.currentVersion else {
            print("SessionStore: unsupported session version \(index.version); starting clean")
            removePersistedSessionFiles()
            return nil
        }

        if index.restoreInProgress {
            print("SessionStore: previous restore did not finish; discarding stored session")
            removePersistedSessionFiles()
            return nil
        }

        do {
            var inProgressIndex = index
            inProgressIndex.restoreInProgress = true
            try writeIndex(inProgressIndex)
        } catch {
            print("SessionStore: failed to mark restore in progress — \(error.localizedDescription)")
            removePersistedSessionFiles()
            return nil
        }

        var restoredGames: [RecordedGame] = []
        restoredGames.reserveCapacity(index.gameIDs.count)

        for gameID in index.gameIDs {
            guard let stored = readGame(id: gameID),
                  let game = SessionSnapshotCoding.decodeGame(stored) else {
                print("SessionStore: skipping unreadable game \(gameID.uuidString)")
                continue
            }
            restoredGames.append(game)
        }

        guard !restoredGames.isEmpty else {
            print("SessionStore: no readable games in stored session; starting clean")
            removePersistedSessionFiles()
            return nil
        }

        let activeGameID = index.activeGameID.flatMap { id in
            restoredGames.contains(where: { $0.id == id }) ? id : nil
        } ?? restoredGames.first?.id

        let snapshot = SessionSnapshot(activeGameID: activeGameID, games: restoredGames)

        do {
            try writeSession(snapshot: snapshot, restoreInProgress: false)
        } catch {
            print("SessionStore: failed to finalize restored session — \(error.localizedDescription)")
            removePersistedSessionFiles()
            return nil
        }

        return snapshot
    }

    private func readIndex() -> SessionIndexFile? {
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL) else {
            return nil
        }
        return try? decoder.decode(SessionIndexFile.self, from: data)
    }

    private func writeIndex(_ index: SessionIndexFile) throws {
        let data = try encoder.encode(index)
        try writeData(data, to: indexURL)
    }

    private func readGame(id: UUID) -> StoredRecordedGame? {
        let url = gameURL(for: id)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(StoredRecordedGame.self, from: data)
    }

    private func writeGame(_ game: StoredRecordedGame) throws {
        let data = try encoder.encode(game)
        try writeData(data, to: gameURL(for: game.id))
    }

    private func gameURL(for id: UUID) -> URL {
        gamesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func removeOrphanedGameFiles(keeping gameIDs: Set<UUID>) throws {
        guard fileManager.fileExists(atPath: gamesDirectory.path) else { return }

        let urls = try fileManager.contentsOfDirectory(
            at: gamesDirectory,
            includingPropertiesForKeys: nil
        )

        for url in urls where url.pathExtension == "json" {
            let filename = url.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: filename), gameIDs.contains(id) {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }

    private func removePersistedSessionFiles() {
        try? fileManager.removeItem(at: rootDirectory)
        try? fileManager.createDirectory(at: gamesDirectory, withIntermediateDirectories: true)
        Self.excludeFromBackup(url: rootDirectory)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        Self.excludeFromBackup(url: url)
    }

    private static func excludeFromBackup(url: URL) {
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resourceURL.setResourceValues(values)
    }
}
