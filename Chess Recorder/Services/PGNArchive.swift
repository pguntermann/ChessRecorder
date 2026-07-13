//
//  PGNArchive.swift
//  Chess Recorder
//

import Foundation

enum PGNResult: String {
    case ongoing = "*"
    case whiteWins = "1-0"
    case blackWins = "0-1"
    case draw = "1/2-1/2"

    var isFinal: Bool {
        self != .ongoing
    }
}

struct PGNMetadata: Equatable {
    let event: String
    let site: String
    let white: String
    let black: String
}

struct RecordedGame: Identifiable {
    let id: UUID
    var moves: [ChessMove]
    var round: Int
    var result: PGNResult
    var date: Date
    var eco: String?
    var openingName: String?

    init(
        id: UUID = UUID(),
        moves: [ChessMove],
        round: Int,
        result: PGNResult,
        date: Date = Date(),
        eco: String? = nil,
        openingName: String? = nil
    ) {
        self.id = id
        self.moves = moves
        self.round = round
        self.result = result
        self.date = date
        self.eco = eco
        self.openingName = openingName
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
    static func movetext(from moves: [ChessMove], result: PGNResult = .ongoing) -> String {
        var pgn = ""
        for (index, move) in moves.enumerated() {
            if index % 2 == 0 {
                pgn += "\(index / 2 + 1). "
            }
            pgn += move.algebraicNotation + " "
        }
        if result != .ongoing {
            pgn += result.rawValue
        }
        return pgn.trimmingCharacters(in: .whitespaces)
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
        eco: String? = nil
    ) -> String {
        let headers = Self.headers(
            round: round,
            result: result,
            metadata: metadata,
            date: date,
            eco: eco
        )
        let moveText = Self.movetext(from: moves, result: result)
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

    var activeGame: RecordedGame? {
        guard let activeGameID else { return nil }
        return games.first { $0.id == activeGameID }
    }

    var activeGameIsReviewOnly: Bool {
        activeGame?.isReviewOnly ?? false
    }

    func ensureActiveGameExists() {
        guard activeGameID == nil || !games.contains(where: { $0.id == activeGameID }) else { return }
        appendNewOngoingGame()
    }

    func syncActiveGame(from chessGame: ChessGame) {
        syncActiveGame(from: chessGame, opening: nil)
    }

    func syncActiveGame(from chessGame: ChessGame, opening: OpeningDisplay?) {
        ensureActiveGameExists()
        guard let activeGameID,
              let index = games.firstIndex(where: { $0.id == activeGameID }) else { return }

        // Archived games are read-only in the archive. The live board is only mirrored into the
        // ongoing recording slot — never into finished games being reviewed.
        guard games[index].result == .ongoing else { return }

        if chessGame.moves.isEmpty {
            games[index].moves = []
            if let opening {
                games[index].eco = opening.eco
                games[index].openingName = opening.name
            }
            if chessGame.isGameOver {
                games[index].result = chessGame.gameResult
            }
            return
        }

        games[index].moves = chessGame.moves
        if let opening {
            games[index].eco = opening.eco
            games[index].openingName = opening.name
        }
        games[index].result = chessGame.gameResult
    }

    func finalizeActiveGame(with result: PGNResult, from chessGame: ChessGame) {
        finalizeActiveGame(with: result, from: chessGame, opening: nil)
    }

    func finalizeActiveGame(with result: PGNResult, from chessGame: ChessGame, opening: OpeningDisplay?) {
        if !chessGame.moves.isEmpty {
            ensureActiveGameExists()
            if let activeGameID,
               let index = games.firstIndex(where: { $0.id == activeGameID }) {
                games[index].moves = chessGame.moves
                games[index].result = result
                if let opening {
                    games[index].eco = opening.eco
                    games[index].openingName = opening.name
                }
            }
        } else if let activeGameID,
                  let index = games.firstIndex(where: { $0.id == activeGameID }) {
            if !games[index].moves.isEmpty {
                // Keep moves already synced to the archive (e.g. after declaring 1-0).
                games[index].result = result
                if let opening {
                    games[index].eco = opening.eco
                    games[index].openingName = opening.name
                }
            } else if games[index].result == .ongoing {
                games.remove(at: index)
            }
        }

        appendNewOngoingGame()
        renumberRounds()
    }

    func setActiveGame(id: UUID) {
        guard games.contains(where: { $0.id == id }) else { return }
        activeGameID = id
    }

    /// Removes a game and returns the ID of the game that should be loaded next, if any.
    @discardableResult
    func removeGame(id: UUID) -> UUID? {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return activeGameID }

        let wasActive = activeGameID == id
        games.remove(at: index)
        renumberRounds()

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

    func displayText(
        metadata: PGNMetadata
    ) -> String {
        games
            .reversed()
            .filter { !$0.moves.isEmpty }
            .map {
                PGNFormatter.formatGame(
                    moves: $0.moves,
                    round: $0.round,
                    result: $0.result,
                    metadata: metadata,
                    date: $0.date,
                    eco: $0.eco
                )
            }
            .joined(separator: "\n\n")
    }

    func resetAll() {
        games.removeAll()
        activeGameID = nil
    }

    private func appendNewOngoingGame() {
        let id = UUID()
        games.insert(RecordedGame(
            id: id,
            moves: [],
            round: games.count + 1,
            result: .ongoing,
            eco: nil,
            openingName: nil
        ), at: 0)
        activeGameID = id
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
