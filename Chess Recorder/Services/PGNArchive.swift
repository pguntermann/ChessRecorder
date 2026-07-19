//
//  PGNArchive.swift
//  Chess Recorder
//

import Foundation

nonisolated enum PGNResult: String, Sendable {
    case ongoing = "*"
    case whiteWins = "1-0"
    case blackWins = "0-1"
    case draw = "1/2-1/2"

    var isFinal: Bool {
        self != .ongoing
    }
}

struct PGNMetadata: Equatable, Codable {
    let event: String
    let site: String
    let white: String
    let black: String

    static let placeholder = PGNMetadata(
        event: AppSettings.defaultPGNEvent,
        site: "?",
        white: "?",
        black: "?"
    )
}

struct RecordedGame: Identifiable {
    let id: UUID
    var moves: [ChessMove]
    var round: Int
    var result: PGNResult
    var date: Date
    var eco: String?
    var openingName: String?
    var metadata: PGNMetadata

    init(
        id: UUID = UUID(),
        moves: [ChessMove],
        round: Int,
        result: PGNResult,
        date: Date = Date(),
        eco: String? = nil,
        openingName: String? = nil,
        metadata: PGNMetadata = .placeholder
    ) {
        self.id = id
        self.moves = moves
        self.round = round
        self.result = result
        self.date = date
        self.eco = eco
        self.openingName = openingName
        self.metadata = metadata
    }

    var isReviewOnly: Bool {
        result.isFinal
    }

    var summaryTitle: String {
        let moveLabel = moves.isEmpty ? "No moves" : "\(moves.count) moves"
        return "Round \(round) · \(result.rawValue) · \(moveLabel)"
    }
}

enum PGNFormatter {
    static func movetext(
        from moves: [ChessMove],
        result: PGNResult = .ongoing,
        includeAssessmentSymbols: Bool = false
    ) -> String {
        let source = moves
        var pgn = ""
        for (index, move) in source.enumerated() {
            if index % 2 == 0 {
                pgn += "\(index / 2 + 1). "
            }
            pgn += exportedMoveText(for: move, includeAssessmentSymbols: includeAssessmentSymbols) + " "
        }
        if result != .ongoing {
            pgn += result.rawValue
        }
        return pgn.trimmingCharacters(in: .whitespaces)
    }

    static func exportedMoveText(for move: ChessMove, includeAssessmentSymbols: Bool) -> String {
        guard includeAssessmentSymbols, let quality = move.quality else {
            return move.algebraicNotation
        }
        return move.algebraicNotation + quality.annotationSymbol
    }

    static func headers(
        round: Int,
        result: PGNResult = .ongoing,
        metadata: PGNMetadata,
        date: Date = Date(),
        eco: String? = nil
    ) -> String {
        var lines = [
            "[Event \"\(escapeTag(metadata.event))\"]",
            "[Site \"\(escapeTag(metadata.site))\"]",
            "[Date \"\(dateString(date))\"]",
            "[Round \"\(round)\"]",
            "[White \"\(escapeTag(metadata.white))\"]",
            "[Black \"\(escapeTag(metadata.black))\"]",
            "[Result \"\(result.rawValue)\"]"
        ]
        if let eco, !eco.isEmpty {
            lines.append("[ECO \"\(escapeTag(eco))\"]")
        }
        return lines.joined(separator: "\n")
    }

    static func formatGame(
        moves: [ChessMove],
        round: Int,
        result: PGNResult = .ongoing,
        metadata: PGNMetadata,
        date: Date = Date(),
        eco: String? = nil,
        includeAssessmentSymbols: Bool = false
    ) -> String {
        let headers = Self.headers(
            round: round,
            result: result,
            metadata: metadata,
            date: date,
            eco: eco
        )
        let moveText = Self.movetext(
            from: moves,
            result: result,
            includeAssessmentSymbols: includeAssessmentSymbols
        )
        guard !moves.isEmpty else { return headers }
        return headers + "\n\n" + moveText
    }

    private static func escapeTag(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

@Observable
final class PGNArchive {
    private(set) var games: [RecordedGame] = []
    private(set) var activeGameID: UUID?
    /// Bumps whenever game move lists, qualities, results, or metadata that affect
    /// notation presentation change. Used for O(1) presentation cache invalidation.
    private(set) var contentRevision: UInt64 = 0
    /// Per-game revision so inactive rows can skip work when only another game changed.
    private var gameContentRevisions: [UUID: UInt64] = [:]
    /// Game IDs whose stored content changed since the last `consumeMutatedGameIDs()`.
    private var pendingMutatedGameIDs: Set<UUID> = []

    var activeGame: RecordedGame? {
        guard let activeGameID else { return nil }
        return games.first { $0.id == activeGameID }
    }

    var activeGameIsReviewOnly: Bool {
        activeGame?.isReviewOnly ?? false
    }

    /// Content stamp for a single game (for row-level invalidation / accuracy cache).
    func contentRevision(for gameID: UUID) -> UInt64 {
        gameContentRevisions[gameID] ?? 0
    }

    /// Returns and clears game IDs mutated since the previous consume.
    func consumeMutatedGameIDs() -> Set<UUID> {
        let ids = pendingMutatedGameIDs
        pendingMutatedGameIDs = []
        return ids
    }

    private func bumpContentRevision(affecting gameIDs: Set<UUID>) {
        contentRevision &+= 1
        pendingMutatedGameIDs.formUnion(gameIDs)
        let liveIDs = Set(games.map(\.id))
        for gameID in gameIDs where liveIDs.contains(gameID) {
            gameContentRevisions[gameID, default: 0] &+= 1
        }
        gameContentRevisions = gameContentRevisions.filter { liveIDs.contains($0.key) }
    }

    private func bumpContentRevision(affecting gameID: UUID) {
        bumpContentRevision(affecting: [gameID])
    }

    private func bumpContentRevisionFully() {
        bumpContentRevision(affecting: Set(games.map(\.id)))
    }

    func ensureActiveGameExists(metadata: PGNMetadata) {
        guard activeGameID == nil || !games.contains(where: { $0.id == activeGameID }) else { return }
        appendNewOngoingGame(metadata: metadata)
    }

    func syncActiveGame(from chessGame: ChessGame, metadata: PGNMetadata) {
        syncActiveGame(from: chessGame, opening: nil, metadata: metadata)
    }

    func syncActiveGame(from chessGame: ChessGame, opening: OpeningDisplay?, metadata: PGNMetadata) {
        ensureActiveGameExists(metadata: metadata)
        guard let activeGameID,
              let index = games.firstIndex(where: { $0.id == activeGameID }) else { return }

        // Archived games are read-only in the archive. The live board is only mirrored into the
        // ongoing recording slot — never into finished games being reviewed.
        guard games[index].result == .ongoing else { return }

        if chessGame.moves.isEmpty {
            games[index].moves = []
            applyOpeningIfAppropriate(opening, toGameAt: index)
            if chessGame.isGameOver {
                games[index].result = chessGame.gameResult
            }
            bumpContentRevision(affecting: activeGameID)
            return
        }

        games[index].moves = mergedMoves(
            preservingQualitiesFrom: games[index].moves,
            newMoves: chessGame.moves
        )
        applyOpeningIfAppropriate(opening, toGameAt: index)
        games[index].result = chessGame.gameResult
        bumpContentRevision(affecting: activeGameID)
    }

    /// Prefer a real opening-book match; don't replace a tagged/imported ECO with A00 fallbacks.
    private func applyOpeningIfAppropriate(_ opening: OpeningDisplay?, toGameAt index: Int) {
        guard let opening else { return }
        let shouldApply =
            games[index].eco == nil
            || (opening != .unknown && opening != .starting)
        guard shouldApply else { return }
        games[index].eco = opening.eco
        games[index].openingName = opening.name
    }

    @discardableResult
    func applyMoveAssessment(
        gameID: UUID,
        moveIndex: Int,
        quality: MoveQuality,
        centipawnLoss: Int? = nil,
        evaluationWhiteCentipawns: Int? = nil,
        bestMoveSAN: String? = nil,
        expectedSAN: String,
        expectedFrom: ChessPosition? = nil,
        expectedTo: ChessPosition? = nil
    ) -> Bool {
        guard let index = games.firstIndex(where: { $0.id == gameID }),
              moveIndex >= 0,
              moveIndex < games[index].moves.count else {
            return false
        }

        let move = games[index].moves[moveIndex]
        // Prefer SAN, but also accept from/to — import enqueue can race with ChessKit SAN
        // rewrite on activate (e.g. disambiguation / check markers), which left hourglasses stuck.
        let sanMatches = move.san == expectedSAN
        let squaresMatch = expectedFrom.map { $0 == move.from } == true
            && expectedTo.map { $0 == move.to } == true
        guard sanMatches || squaresMatch else {
            return false
        }

        games[index].moves[moveIndex] = move.withQuality(
            quality,
            centipawnLoss: quality == .book ? nil : centipawnLoss,
            evaluationWhiteCentipawns: quality == .book ? nil : evaluationWhiteCentipawns,
            bestMoveSAN: quality == .book ? nil : bestMoveSAN
        )
        // Reassign the game element so @Observable reliably publishes nested move changes.
        games[index] = games[index]
        bumpContentRevision(affecting: gameID)
        return true
    }

    /// Clears quality, centipawn loss, and evaluation on every stored move so assessment can run again.
    @discardableResult
    func clearAllMoveAssessments() -> Int {
        var cleared = 0
        for gameIndex in games.indices {
            var didClearGame = false
            for moveIndex in games[gameIndex].moves.indices {
                let move = games[gameIndex].moves[moveIndex]
                guard move.quality != nil
                    || move.centipawnLoss != nil
                    || move.evaluationWhiteCentipawns != nil
                    || move.bestMoveSAN != nil else { continue }
                games[gameIndex].moves[moveIndex] = move.withQuality(
                    nil,
                    centipawnLoss: nil,
                    evaluationWhiteCentipawns: nil,
                    bestMoveSAN: nil
                )
                cleared += 1
                didClearGame = true
            }
            if didClearGame {
                games[gameIndex] = games[gameIndex]
                bumpContentRevision(affecting: games[gameIndex].id)
            }
        }
        return cleared
    }

    private func mergedMoves(preservingQualitiesFrom oldMoves: [ChessMove], newMoves: [ChessMove]) -> [ChessMove] {
        var merged = newMoves
        for index in merged.indices {
            guard index < oldMoves.count,
                  oldMoves[index].matchesPositionally(newMoves[index]) else {
                break
            }
            // Skip gaps (nil quality) instead of stopping — later assessed plies must be kept.
            guard let quality = oldMoves[index].quality else { continue }
            merged[index] = merged[index].withQuality(
                quality,
                centipawnLoss: oldMoves[index].centipawnLoss,
                evaluationWhiteCentipawns: oldMoves[index].evaluationWhiteCentipawns,
                bestMoveSAN: oldMoves[index].bestMoveSAN
            )
        }
        return merged
    }

    func finalizeActiveGame(with result: PGNResult, from chessGame: ChessGame, metadataForNewGame: PGNMetadata) {
        finalizeActiveGame(with: result, from: chessGame, opening: nil, metadataForNewGame: metadataForNewGame)
    }

    func finalizeActiveGame(
        with result: PGNResult,
        from chessGame: ChessGame,
        opening: OpeningDisplay?,
        metadataForNewGame: PGNMetadata
    ) {
        var mutated: Set<UUID> = []
        if !chessGame.moves.isEmpty {
            ensureActiveGameExists(metadata: metadataForNewGame)
            if let activeGameID,
               let index = games.firstIndex(where: { $0.id == activeGameID }) {
                games[index].moves = mergedMoves(
                    preservingQualitiesFrom: games[index].moves,
                    newMoves: chessGame.moves
                )
                games[index].result = result
                applyOpeningIfAppropriate(opening, toGameAt: index)
                mutated.insert(activeGameID)
            }
        } else if let activeGameID,
                  let index = games.firstIndex(where: { $0.id == activeGameID }) {
            if !games[index].moves.isEmpty {
                // Keep moves already synced to the archive (e.g. after declaring 1-0).
                games[index].result = result
                applyOpeningIfAppropriate(opening, toGameAt: index)
                mutated.insert(activeGameID)
            } else if games[index].result == .ongoing {
                games.remove(at: index)
                mutated.insert(activeGameID)
            }
        }

        appendNewOngoingGame(metadata: metadataForNewGame)
        renumberRounds()
        if !mutated.isEmpty {
            // appendNewOngoingGame already bumped for the new slot; also mark finalized game.
            pendingMutatedGameIDs.formUnion(mutated)
        }
    }

    func setActiveGame(id: UUID) {
        guard games.contains(where: { $0.id == id }) else { return }
        activeGameID = id
    }

    /// Updates PGN header tags for a single archived game.
    func updateGameTags(id: UUID, metadata: PGNMetadata, date: Date) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        guard games[index].metadata != metadata || !Calendar.current.isDate(games[index].date, inSameDayAs: date) else {
            return
        }
        games[index].metadata = metadata
        games[index].date = date
        bumpContentRevision(affecting: id)
    }

    /// Removes a game and returns the ID of the game that should be loaded next, if any.
    @discardableResult
    func removeGame(id: UUID) -> UUID? {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return activeGameID }

        let wasActive = activeGameID == id
        games.remove(at: index)
        renumberRounds()
        bumpContentRevision(affecting: id)

        guard !games.isEmpty else {
            activeGameID = nil
            return nil
        }

        if wasActive {
            let nextIndex = min(index, games.count - 1)
            activeGameID = games[nextIndex].id
            return activeGameID
        }

        return activeGameID
    }

    func displayText() -> String {
        games
            .reversed()
            .filter { !$0.moves.isEmpty }
            .map {
                PGNFormatter.formatGame(
                    moves: $0.moves,
                    round: $0.round,
                    result: $0.result,
                    metadata: $0.metadata,
                    date: $0.date,
                    eco: $0.eco
                )
            }
            .joined(separator: "\n\n")
    }

    func resetAll() {
        let previousIDs = Set(games.map(\.id))
        games.removeAll()
        activeGameID = nil
        gameContentRevisions.removeAll()
        bumpContentRevision(affecting: previousIDs)
    }

    /// Appends imported games without changing the active game.
    /// File order is oldest→newest (export order); archive keeps newest-first.
    @discardableResult
    func appendImportedGames(_ imported: [PGNImportService.ImportedGame]) -> [UUID] {
        guard !imported.isEmpty else { return [] }

        var addedIDs: [UUID] = []
        for game in imported {
            let id = UUID()
            games.insert(
                RecordedGame(
                    id: id,
                    moves: game.moves,
                    round: 0,
                    result: game.result,
                    date: game.date,
                    eco: game.eco,
                    openingName: game.openingName,
                    metadata: game.metadata
                ),
                at: 0
            )
            addedIDs.append(id)
        }
        renumberRounds()
        bumpContentRevision(affecting: Set(addedIDs))
        return addedIDs
    }

    func applySessionSnapshot(_ snapshot: SessionSnapshot) {
        games = snapshot.games
        if let activeGameID = snapshot.activeGameID,
           games.contains(where: { $0.id == activeGameID }) {
            self.activeGameID = activeGameID
        } else {
            activeGameID = games.first?.id
        }
        gameContentRevisions = Dictionary(
            uniqueKeysWithValues: games.map { ($0.id, gameContentRevisions[$0.id] ?? 0) }
        )
        bumpContentRevisionFully()
    }

    /// Replaces move lists for existing games when SANs were repaired off the hot path.
    /// Returns game IDs whose stored SAN text actually changed.
    @discardableResult
    func replaceMovesPreservingIdentity(_ updates: [(id: UUID, moves: [ChessMove])]) -> Set<UUID> {
        var changedIDs = Set<UUID>()
        for update in updates {
            guard let index = games.firstIndex(where: { $0.id == update.id }) else { continue }
            let before = games[index].moves.map(\.san)
            let after = update.moves.map(\.san)
            guard before != after else { continue }
            games[index].moves = update.moves
            changedIDs.insert(update.id)
        }
        if !changedIDs.isEmpty {
            bumpContentRevision(affecting: changedIDs)
        }
        return changedIDs
    }

    private func appendNewOngoingGame(metadata: PGNMetadata) {
        let id = UUID()
        games.insert(RecordedGame(
            id: id,
            moves: [],
            round: games.count + 1,
            result: .ongoing,
            eco: nil,
            openingName: nil,
            metadata: metadata
        ), at: 0)
        activeGameID = id
        bumpContentRevision(affecting: id)
    }

    private func renumberRounds() {
        for index in games.indices {
            games[index].round = games.count - index
        }
    }
}

enum PGNExport {
    static func writeTemporaryFile(content: String) throws -> URL {
        try PGNExportService.writeTemporaryFile(content: content)
    }
}
