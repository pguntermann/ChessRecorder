//
//  PGNExportService.swift
//  Chess Recorder
//

import Foundation

enum PGNExportService {
    static func fullPGN(for games: [RecordedGame], includeAssessmentSymbols: Bool = false) -> String {
        games
            .reversed()
            .filter { !$0.moves.isEmpty }
            .map { game in
                pgn(for: game, includeAssessmentSymbols: includeAssessmentSymbols)
            }
            .joined(separator: "\n\n")
    }

    static func fullPGN(for archive: PGNArchive, includeAssessmentSymbols: Bool = false) -> String {
        fullPGN(for: archive.games, includeAssessmentSymbols: includeAssessmentSymbols)
    }

    static func pgn(for game: RecordedGame, includeAssessmentSymbols: Bool = false) -> String {
        PGNFormatter.formatGame(
            moves: game.moves,
            round: game.round,
            result: game.result,
            metadata: game.metadata,
            date: game.date,
            eco: game.eco,
            includeAssessmentSymbols: includeAssessmentSymbols
        )
    }

    static func writeTemporaryFile(content: String, filenamePrefix: String = "ChessRecorder") throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "\(filenamePrefix)-\(formatter.string(from: Date())).pgn"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

