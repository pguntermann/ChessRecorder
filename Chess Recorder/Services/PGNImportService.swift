//
//  PGNImportService.swift
//  Chess Recorder
//

import ChessKit
import Foundation

enum PGNImportService {
    struct ImportedGame {
        let moves: [ChessMove]
        let result: PGNResult
        let date: Date
        let roundHint: Int?
        let eco: String?
        let metadata: PGNMetadata
    }

    enum ImportError: LocalizedError, Equatable {
        case emptyInput
        case noGamesParsed
        case nonStandardStart(gameIndex: Int)
        case parseFailed(gameIndex: Int, detail: String)

        var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "Clipboard or file is empty."
            case .noGamesParsed:
                return "No PGN games were found."
            case .nonStandardStart(let gameIndex):
                return "Game \(gameIndex + 1) uses a non-standard starting position (SetUp/FEN), which is not supported."
            case .parseFailed(let gameIndex, let detail):
                return "Could not parse game \(gameIndex + 1): \(detail)"
            }
        }
    }

    /// Splits a multi-game PGN (as produced by Chess Recorder export) into single-game strings.
    static func splitGames(in pgn: String) -> [String] {
        let normalized = pgn
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let chunks = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var games: [String] = []
        var index = 0
        while index < chunks.count {
            let chunk = chunks[index]
            if chunk.hasPrefix("[") {
                if index + 1 < chunks.count, !chunks[index + 1].hasPrefix("[") {
                    games.append(chunk + "\n\n" + chunks[index + 1])
                    index += 2
                } else {
                    games.append(chunk)
                    index += 1
                }
            } else {
                games.append(chunk)
                index += 1
            }
        }
        return games
    }

    static func importGames(from pgn: String) throws -> [ImportedGame] {
        let trimmed = pgn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyInput }

        let gameTexts = splitGames(in: trimmed)
        guard !gameTexts.isEmpty else { throw ImportError.noGamesParsed }

        var imported: [ImportedGame] = []
        for (gameIndex, gameText) in gameTexts.enumerated() {
            let kitGame: Game
            do {
                kitGame = try PGNParser.parse(game: gameText)
            } catch {
                throw ImportError.parseFailed(gameIndex: gameIndex, detail: String(describing: error))
            }

            if kitGame.tags.setUp == "1"
                || !kitGame.tags.fen.isEmpty
                || (kitGame.startingPosition.map { $0 != .standard } ?? false) {
                throw ImportError.nonStandardStart(gameIndex: gameIndex)
            }

            let endIndex = kitGame.moves.endIndex
            let mainlineIndices = kitGame.moves.history(for: endIndex)
            let moves = mainlineIndices.compactMap { kitGame.moves[$0] }.map {
                ChessKitMapping.appMove(from: $0)
            }
            guard !moves.isEmpty else { continue }

            imported.append(
                ImportedGame(
                    moves: moves,
                    result: pgnResult(from: kitGame.tags.result),
                    date: parseDate(kitGame.tags.date) ?? Date(),
                    roundHint: Int(kitGame.tags.round),
                    eco: eco(from: kitGame.tags),
                    metadata: PGNMetadata(
                        event: nonEmpty(kitGame.tags.event, fallback: AppSettings.defaultPGNEvent),
                        site: nonEmpty(kitGame.tags.site, fallback: "?"),
                        white: nonEmpty(kitGame.tags.white, fallback: "?"),
                        black: nonEmpty(kitGame.tags.black, fallback: "?")
                    )
                )
            )
        }

        guard !imported.isEmpty else { throw ImportError.noGamesParsed }
        return imported
    }

    private static func pgnResult(from tag: String) -> PGNResult {
        switch tag.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1-0": return .whiteWins
        case "0-1": return .blackWins
        case "1/2-1/2": return .draw
        default: return .ongoing
        }
    }

    private static func eco(from tags: Game.Tags) -> String? {
        let value = tags.other["ECO"] ?? tags.other["Eco"]
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("?") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.date(from: trimmed)
    }
}
