//
//  ChessComAnalysisURL.swift
//  Chess Recorder
//

import Foundation

enum ChessComAnalysisURL {
    /// In-app browser open; Chess.com uses a query-encoded PGN (less compact than Lichess).
    /// Prefer `ChessComAnalysisBrowser` over a Universal Link — the Chess.com app claims the
    /// URL but does not load the shared game, and mobile web often leaves the board at start.
    static let maxBrowserURLCharacterCount = 16_000

    /// Builds `https://www.chess.com/analysis?tab=analysis&pgn=…` from move SANs.
    ///
    /// SAN tokens are taken from a ChessKit replay of `from`/`to` (not the stored speech
    /// string), so misheard piece letters do not break the import.
    static func make(
        fromMoves moves: [ChessMove],
        result: PGNResult = .ongoing,
        maxCharacterCount: Int = maxBrowserURLCharacterCount
    ) -> URL? {
        guard let body = pgnMovetext(from: moves, result: result), !body.isEmpty else {
            return nil
        }

        // Encode the whole PGN body; `+` / `#` / spaces must not stay literal in the query.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }

        let urlString = "https://www.chess.com/analysis?tab=analysis&pgn=\(encoded)"
        guard urlString.count <= maxCharacterCount else { return nil }
        return URL(string: urlString)
    }

    /// Compact numbered movetext for the Chess.com `pgn` query / pasteboard.
    static func pgnMovetext(
        from moves: [ChessMove],
        result: PGNResult = .ongoing
    ) -> String? {
        guard !moves.isEmpty else { return nil }

        let rebuilt = ChessGameBackgroundPreparation.prepareTransfer(from: moves).moves
        let source = rebuilt.count == moves.count ? rebuilt : moves

        var parts: [String] = []
        for (index, move) in source.enumerated() {
            if index % 2 == 0 {
                parts.append("\(index / 2 + 1).")
            }
            parts.append(sanWithoutAnnotations(move))
        }
        if result.isFinal {
            parts.append(result.rawValue)
        }
        let text = parts.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func sanWithoutAnnotations(_ move: ChessMove) -> String {
        var san = move.san
        while let last = san.last, "?!".contains(last) {
            san.removeLast()
        }
        return san
    }
}
