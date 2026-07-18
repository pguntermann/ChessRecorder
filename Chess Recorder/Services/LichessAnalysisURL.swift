//
//  LichessAnalysisURL.swift
//  Chess Recorder
//

import Foundation

enum LichessAnalysisURL {
    /// Keep payloads short enough for reliable phone-camera scanning at ~1″ print size.
    /// Full header PGN blows past this quickly; use compact SAN instead.
    static let maxURLCharacterCount = 900
    /// Safari / in-app open can carry a longer analysis URL than a printed QR.
    static let maxBrowserURLCharacterCount = 4_000

    /// Builds a compact `https://lichess.org/analysis/pgn/...` URL from move SANs.
    /// Uses underscore-separated SAN (Lichess’s preferred compact form).
    ///
    /// SAN tokens are taken from a ChessKit replay of `from`/`to` (not the stored speech
    /// string), so misheard piece letters like `Rxf8` vs `Nxf8` do not break Lichess.
    static func make(
        fromMoves moves: [ChessMove],
        result: PGNResult = .ongoing,
        maxCharacterCount: Int = maxURLCharacterCount
    ) -> URL? {
        guard !moves.isEmpty else { return nil }

        var tokens = canonicalSANTokens(from: moves)
        guard !tokens.isEmpty else { return nil }
        if result.isFinal {
            tokens.append(result.rawValue)
        }
        let body = tokens.joined(separator: "_")

        // Keep `_` literal; encode check (`+`), mate (`#`), etc.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "_-.")
        guard let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }

        let urlString = "https://lichess.org/analysis/pgn/\(encoded)"
        guard urlString.count <= maxCharacterCount else { return nil }
        return URL(string: urlString)
    }

    /// Legacy full-PGN path (headers + movetext). Prefer `make(fromMoves:)` for QR codes.
    static func make(fromPGN pgn: String) -> URL? {
        let trimmed = pgn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }

        let urlString = "https://lichess.org/analysis/pgn/\(encoded)"
        guard urlString.count <= maxURLCharacterCount else { return nil }
        return URL(string: urlString)
    }

    /// ChessKit SAN for each ply via from/to replay; falls back to stored SAN if replay fails.
    private static func canonicalSANTokens(from moves: [ChessMove]) -> [String] {
        let rebuilt = ChessGameBackgroundPreparation.prepareTransfer(from: moves).moves
        let source = rebuilt.count == moves.count ? rebuilt : moves
        return source.map(sanForLichess)
    }

    /// Drop assessment-style suffixes; keep check/mate for Lichess.
    private static func sanForLichess(_ move: ChessMove) -> String {
        var san = move.san
        while let last = san.last, "?!".contains(last) {
            san.removeLast()
        }
        return san
    }
}
