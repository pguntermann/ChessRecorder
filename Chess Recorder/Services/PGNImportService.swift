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
        case notPGN
        case inputTooLarge(byteCount: Int, limitBytes: Int)
        case tooManyGames(found: Int, limit: Int)
        case nonStandardStart(gameIndex: Int)
        case parseFailed(gameIndex: Int, detail: String)

        var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "Clipboard or file is empty."
            case .noGamesParsed:
                return "No PGN games were found."
            case .notPGN:
                return "This doesn’t look like a PGN file. Choose a .pgn export or paste standard chess game notation."
            case .inputTooLarge(_, let limitBytes):
                let limitMB = Double(limitBytes) / 1_000_000
                return String(
                    format: "This PGN is too large. Maximum size is %.1f MB.",
                    limitMB
                )
            case .tooManyGames(let found, let limit):
                return "This file contains \(found) games. Chess Recorder can import at most \(limit) games at a time — split the file and try again."
            case .nonStandardStart(let gameIndex):
                return "Game \(gameIndex + 1) uses a non-standard starting position (SetUp/FEN), which is not supported."
            case .parseFailed(let gameIndex, let detail):
                return "Could not parse game \(gameIndex + 1): \(detail)"
            }
        }
    }

    /// Hard cap on games per import (product limit for a recorder, not a database).
    static let maxGamesPerImport = 20
    /// Show a non-database disclaimer when more than this many games were imported.
    static let largeImportNoticeThreshold = 10
    /// Reject oversized paste/file payloads before parsing.
    static let maxInputUTF8ByteCount = 512_000

    static func shouldShowLargeImportNotice(importedCount: Int) -> Bool {
        importedCount > largeImportNoticeThreshold
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

    /// Counts only chunks that look like real PGN (tags and/or numbered movetext), not blank-line prose.
    static func estimateGameCount(in text: String) -> Int {
        pgnGameCandidates(in: text).count
    }

    /// True when the text contains at least one PGN-looking game.
    static func looksLikePGN(_ text: String) -> Bool {
        estimateGameCount(in: text) > 0
    }

    static func importGames(from pgn: String) throws -> [ImportedGame] {
        let trimmed = pgn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyInput }

        let utf8Count = trimmed.utf8.count
        guard utf8Count <= maxInputUTF8ByteCount else {
            throw ImportError.inputTooLarge(byteCount: utf8Count, limitBytes: maxInputUTF8ByteCount)
        }

        let gameTexts = pgnGameCandidates(in: trimmed)
        guard !gameTexts.isEmpty else {
            throw splitGames(in: trimmed).isEmpty ? ImportError.noGamesParsed : ImportError.notPGN
        }
        guard gameTexts.count <= maxGamesPerImport else {
            throw ImportError.tooManyGames(found: gameTexts.count, limit: maxGamesPerImport)
        }

        var imported: [ImportedGame] = []
        for (gameIndex, gameText) in gameTexts.enumerated() {
            let tags = parseTags(in: gameText)
            if isNonStandardStart(tags: tags) {
                throw ImportError.nonStandardStart(gameIndex: gameIndex)
            }

            let game: ImportedGame
            do {
                game = try importWithChessKit(gameText: gameText, tags: tags)
            } catch let error as ImportError {
                if case .nonStandardStart = error { throw error }
                game = try importByReplayingSAN(gameText: gameText, tags: tags, gameIndex: gameIndex)
            } catch {
                game = try importByReplayingSAN(gameText: gameText, tags: tags, gameIndex: gameIndex)
            }
            imported.append(game)
        }

        guard !imported.isEmpty else { throw ImportError.noGamesParsed }
        return imported
    }

    /// Splits on blank lines, then keeps only chunks that resemble PGN games.
    private static func pgnGameCandidates(in text: String) -> [String] {
        splitGames(in: text).filter(looksLikePGNGame)
    }

    private static func looksLikePGNGame(_ text: String) -> Bool {
        let tags = parseTags(in: text)
        let hasSevenTagRoster =
            tags["Event"] != nil
            || tags["Site"] != nil
            || tags["Date"] != nil
            || tags["Round"] != nil
            || tags["White"] != nil
            || tags["Black"] != nil
            || tags["Result"] != nil
        if hasSevenTagRoster { return true }
        if tags["FEN"] != nil || tags["SetUp"] != nil || tags["ECO"] != nil { return true }

        let movetext = extractMovetext(from: text).text
        // Numbered move: "1.e4", "12... Nf6", "8. O-O"
        if movetext.range(of: #"\b\d+\.+[.\s]*[A-Za-z0-9]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    // MARK: - ChessKit path

    private static func importWithChessKit(gameText: String, tags: [String: String]) throws -> ImportedGame {
        let kitGame = try PGNParser.parse(game: gameText)

        let endIndex = kitGame.moves.endIndex
        let mainlineIndices = kitGame.moves.history(for: endIndex)
        let moves = mainlineIndices.compactMap { kitGame.moves[$0] }.map {
            ChessKitMapping.appMove(from: $0)
        }
        guard !moves.isEmpty else {
            throw ImportError.parseFailed(gameIndex: 0, detail: "noMoves")
        }

        let tagResult = pgnResult(from: kitGame.tags.result)
        let movetextResult = extractMovetext(from: gameText).result.map { pgnResult(from: $0) }
        let result = tagResult != .ongoing ? tagResult : (movetextResult ?? .ongoing)

        return ImportedGame(
            moves: moves,
            result: result,
            date: parseDate(kitGame.tags.date) ?? parseDate(tags["Date"] ?? "") ?? Date(),
            roundHint: Int(kitGame.tags.round) ?? Int(tags["Round"] ?? ""),
            eco: eco(from: kitGame.tags) ?? eco(from: tags),
            metadata: metadata(from: tags, kitTags: kitGame.tags)
        )
    }

    // MARK: - ChessGame replay fallback

    private static func importByReplayingSAN(
        gameText: String,
        tags: [String: String],
        gameIndex: Int
    ) throws -> ImportedGame {
        let movetext = extractMovetext(from: gameText)
        let tokens = sanTokens(from: movetext.text)
        guard !tokens.sans.isEmpty else {
            throw ImportError.parseFailed(gameIndex: gameIndex, detail: "noMoves")
        }

        let game = ChessGame()
        game.resetGame()
        for (ply, san) in tokens.sans.enumerated() {
            guard game.executeSAN(san) else {
                throw ImportError.parseFailed(
                    gameIndex: gameIndex,
                    detail: "invalidMove(\"\(san)\") at ply \(ply + 1)"
                )
            }
        }

        let tagResult = pgnResult(from: tags["Result"] ?? "")
        let trailResult = (tokens.result ?? movetext.result).map { pgnResult(from: $0) } ?? .ongoing
        let result = tagResult != .ongoing ? tagResult : trailResult

        return ImportedGame(
            moves: game.moves,
            result: result,
            date: parseDate(tags["Date"] ?? "") ?? Date(),
            roundHint: Int(tags["Round"] ?? ""),
            eco: eco(from: tags),
            metadata: metadata(from: tags, kitTags: nil)
        )
    }

    // MARK: - Tag / movetext helpers

    private static func parseTags(in gameText: String) -> [String: String] {
        let normalized = gameText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var tags: [String: String] = [:]
        let pattern = #"\[([A-Za-z0-9]+)\s+"((?:\\.|[^"\\])*)"\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return tags }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        regex.enumerateMatches(in: normalized, range: range) { match, _, _ in
            guard let match,
                  let nameRange = Range(match.range(at: 1), in: normalized),
                  let valueRange = Range(match.range(at: 2), in: normalized) else { return }
            let name = String(normalized[nameRange])
            let value = String(normalized[valueRange])
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            tags[name] = value
        }
        return tags
    }

    private static func isNonStandardStart(tags: [String: String]) -> Bool {
        if tags["SetUp"] == "1" { return true }
        if let fen = tags["FEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !fen.isEmpty {
            return true
        }
        return false
    }

    private static func extractMovetext(from gameText: String) -> (text: String, result: String?) {
        let normalized = gameText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let parts = normalized.components(separatedBy: "\n\n")
        let movetext: String
        if parts.count >= 2, parts[0].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            movetext = parts.dropFirst().joined(separator: "\n\n")
        } else if parts.count == 1, !parts[0].hasPrefix("[") {
            movetext = parts[0]
        } else {
            // Tags only, or tags without blank line before moves — strip tag lines.
            movetext = normalized
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }
                .joined(separator: "\n")
        }

        let trimmed = movetext.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = trailingResult(in: trimmed)
        return (trimmed, result)
    }

    private static func sanTokens(from movetext: String) -> (sans: [String], result: String?) {
        var text = movetext
        // Strip brace comments.
        while let range = text.range(of: #"\{[^}]*\}"#, options: .regularExpression) {
            text.replaceSubrange(range, with: " ")
        }
        // Strip non-nested variations.
        while let range = text.range(of: #"\([^()]*\)"#, options: .regularExpression) {
            text.replaceSubrange(range, with: " ")
        }
        // Strip NAGs ($1, $3, …).
        text = text.replacingOccurrences(of: #"\$\d+"#, with: " ", options: .regularExpression)

        let rawTokens = text
            .split { $0.isWhitespace || $0.isNewline }
            .map(String.init)

        var sans: [String] = []
        var result: String?
        for token in rawTokens {
            if token == "1-0" || token == "0-1" || token == "1/2-1/2" || token == "*" {
                result = token
                continue
            }
            // Move numbers: "12." / "12..." / "8."
            if token.range(of: #"^\d+\.+$"#, options: .regularExpression) != nil {
                continue
            }
            sans.append(token)
        }
        return (sans, result)
    }

    private static func trailingResult(in movetext: String) -> String? {
        let trimmed = movetext.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["1/2-1/2", "1-0", "0-1", "*"] {
            if trimmed.hasSuffix(marker) { return marker }
        }
        return nil
    }

    private static func metadata(from tags: [String: String], kitTags: Game.Tags?) -> PGNMetadata {
        PGNMetadata(
            event: nonEmpty(kitTags?.event ?? tags["Event"] ?? "", fallback: AppSettings.defaultPGNEvent),
            site: nonEmpty(kitTags?.site ?? tags["Site"] ?? "", fallback: "?"),
            white: nonEmpty(kitTags?.white ?? tags["White"] ?? "", fallback: "?"),
            black: nonEmpty(kitTags?.black ?? tags["Black"] ?? "", fallback: "?")
        )
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
        eco(from: tags.other)
    }

    private static func eco(from tags: [String: String]) -> String? {
        let value = tags["ECO"] ?? tags["Eco"]
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
