//
//  SessionSnapshot.swift
//  Chess Recorder
//

import Foundation

/// In-memory representation of the persisted user session.
struct SessionSnapshot {
    let activeGameID: UUID?
    let games: [RecordedGame]

    init(activeGameID: UUID?, games: [RecordedGame]) {
        self.activeGameID = activeGameID
        self.games = games
    }

    init(archive: PGNArchive) {
        activeGameID = archive.activeGameID
        games = archive.games
    }

    /// True when the session has content worth writing to disk.
    var hasPersistableContent: Bool {
        games.contains { !$0.moves.isEmpty || $0.result.isFinal } || games.count > 1
    }
}

// MARK: - On-disk encoding

struct SessionIndexFile: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let activeGameID: UUID?
    let gameIDs: [UUID]
    var restoreInProgress: Bool
}

struct StoredRecordedGame: Codable, Equatable {
    let id: UUID
    let moves: [StoredChessMove]
    let round: Int
    let result: String
    let date: Date
    let eco: String?
    let openingName: String?
    let event: String?
    let site: String?
    let white: String?
    let black: String?
}

struct StoredChessMove: Codable, Equatable {
    let san: String
    let piece: String
    let from: String
    let to: String
    let captures: Bool
    let isCheck: Bool
    let isCheckmate: Bool
    let promotion: String?
    let castling: String?
    let quality: String?
}

enum SessionSnapshotCoding {
    static func encodeGame(_ game: RecordedGame) -> StoredRecordedGame {
        StoredRecordedGame(
            id: game.id,
            moves: game.moves.map(StoredChessMove.init),
            round: game.round,
            result: game.result.rawValue,
            date: game.date,
            eco: game.eco,
            openingName: game.openingName,
            event: game.metadata.event,
            site: game.metadata.site,
            white: game.metadata.white,
            black: game.metadata.black
        )
    }

    static func decodeGame(_ stored: StoredRecordedGame) -> RecordedGame? {
        guard let result = PGNResult(rawValue: stored.result) else { return nil }
        let moves = stored.moves.compactMap { $0.makeChessMove() }
        guard moves.count == stored.moves.count else { return nil }

        return RecordedGame(
            id: stored.id,
            moves: moves,
            round: stored.round,
            result: result,
            date: stored.date,
            eco: stored.eco,
            openingName: stored.openingName,
            metadata: metadata(from: stored)
        )
    }

    private static func metadata(from stored: StoredRecordedGame) -> PGNMetadata {
        PGNMetadata(
            event: stored.event ?? PGNMetadata.placeholder.event,
            site: stored.site ?? PGNMetadata.placeholder.site,
            white: stored.white ?? PGNMetadata.placeholder.white,
            black: stored.black ?? PGNMetadata.placeholder.black
        )
    }
}

private extension StoredChessMove {
    init(move: ChessMove) {
        san = move.san
        piece = move.piece.rawValue
        from = move.from.notation
        to = move.to.notation
        captures = move.captures
        isCheck = move.isCheck
        isCheckmate = move.isCheckmate
        promotion = move.promotion?.rawValue.nilIfEmpty
        castling = move.castling
        quality = move.quality?.rawValue
    }

    func makeChessMove() -> ChessMove? {
        guard let fromPosition = ChessPosition(notation: from),
              let toPosition = ChessPosition(notation: to) else {
            return nil
        }

        let pieceType = PieceType(rawValue: piece) ?? .pawn
        let promotionType = promotion.flatMap { PieceType(rawValue: $0) }
        let moveQuality = quality.flatMap(MoveQuality.init(persistedRawValue:))

        return ChessMove(
            san: san,
            piece: pieceType,
            from: fromPosition,
            to: toPosition,
            captures: captures,
            isCheck: isCheck,
            isCheckmate: isCheckmate,
            promotion: promotionType,
            castling: castling,
            quality: moveQuality
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
