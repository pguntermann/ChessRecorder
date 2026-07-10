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
}

struct PGNMetadata: Equatable {
    let site: String
    let white: String
    let black: String
}

struct RecordedGame {
    let moves: [ChessMove]
    let round: Int
    let result: PGNResult
    let date: Date
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
        date: Date = Date()
    ) -> String {
        """
        [Event "Chess Recorder"]
        [Site "\(escapeTag(metadata.site))"]
        [Date "\(dateString(date))"]
        [Round "\(round)"]
        [White "\(escapeTag(metadata.white))"]
        [Black "\(escapeTag(metadata.black))"]
        [Result "\(result.rawValue)"]
        """
    }
    
    static func formatGame(
        moves: [ChessMove],
        round: Int,
        result: PGNResult = .ongoing,
        metadata: PGNMetadata,
        date: Date = Date()
    ) -> String {
        let headers = Self.headers(round: round, result: result, metadata: metadata, date: date)
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
    private(set) var completedGames: [RecordedGame] = []
    private(set) var currentGameResult: PGNResult = .ongoing
    
    func finalizeCurrentGame(_ game: ChessGame, result: PGNResult) {
        guard !game.moves.isEmpty else { return }
        completedGames.append(RecordedGame(
            moves: game.moves,
            round: completedGames.count + 1,
            result: result,
            date: Date()
        ))
        currentGameResult = .ongoing
    }

    func syncCurrentGameResult(with game: ChessGame) {
        currentGameResult = game.gameResult
    }
    
    func displayText(currentGame: ChessGame, metadata: PGNMetadata) -> String {
        var parts = completedGames.map {
            PGNFormatter.formatGame(
                moves: $0.moves,
                round: $0.round,
                result: $0.result,
                metadata: metadata,
                date: $0.date
            )
        }
        if !currentGame.moves.isEmpty {
            let round = completedGames.count + 1
            parts.append(PGNFormatter.formatGame(
                moves: currentGame.moves,
                round: round,
                result: currentGameResult,
                metadata: metadata
            ))
        }
        return parts.joined(separator: "\n\n")
    }
    
    func resetAll() {
        completedGames.removeAll()
        currentGameResult = .ongoing
    }
}

enum PGNExport {
    static func writeTemporaryFile(content: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "ChessRecorder-\(formatter.string(from: Date())).pgn"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
