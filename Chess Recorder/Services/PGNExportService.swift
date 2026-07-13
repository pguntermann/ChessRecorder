//
//  PGNExportService.swift
//  Chess Recorder
//

import Foundation

enum PGNExportService {
    static func fullPGN(
        for games: [RecordedGame],
        metadata: PGNMetadata
    ) -> String {
        games
            .reversed()
            .filter { !$0.moves.isEmpty }
            .map { game in
                PGNFormatter.formatGame(
                    moves: game.moves,
                    round: game.round,
                    result: game.result,
                    metadata: metadata,
                    date: game.date,
                    eco: game.eco
                )
            }
            .joined(separator: "\n\n")
    }

    static func fullPGN(
        for archive: PGNArchive,
        metadata: PGNMetadata
    ) -> String {
        fullPGN(for: archive.games, metadata: metadata)
    }

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

