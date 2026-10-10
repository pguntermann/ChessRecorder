//
//  StockfishFENSanitizer.swift
//  Chess Recorder
//

import Foundation

/// Stockfish treats invalid castling rights as undefined behavior and can crash in
/// `attacks_bb` / `set_check_info` (especially at higher depths). ChessKit FENs
/// sometimes keep rights like `K` after h1 is no longer a white rook.
enum StockfishFENSanitizer {
    /// Returns a FEN safe for Stockfish, stripping castling rights that the board
    /// cannot support. Logs when anything is changed.
    static func sanitizeForStockfish(_ fen: String) -> String {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return fen }

        let placement = parts[0]
        let castling = parts[2]
        guard castling != "-" else { return fen }

        let board = boardFromPlacement(placement)
        var kept = ""

        if castling.contains("K"),
           board["e1"] == "K",
           board["h1"] == "R" {
            kept.append("K")
        }
        if castling.contains("Q"),
           board["e1"] == "K",
           board["a1"] == "R" {
            kept.append("Q")
        }
        if castling.contains("k"),
           board["e8"] == "k",
           board["h8"] == "r" {
            kept.append("k")
        }
        if castling.contains("q"),
           board["e8"] == "k",
           board["a8"] == "r" {
            kept.append("q")
        }

        let sanitizedCastling = kept.isEmpty ? "-" : kept
        guard sanitizedCastling != castling else { return fen }

        var updated = parts
        updated[2] = sanitizedCastling
        return updated.joined(separator: " ")
    }

    /// Map algebraic square -> piece character (or absent).
    private static func boardFromPlacement(_ placement: String) -> [String: Character] {
        var board: [String: Character] = [:]
        let ranks = placement.split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return board }

        let files = Array("abcdefgh")
        for (rankOffset, rankText) in ranks.enumerated() {
            let rank = 8 - rankOffset
            var fileIndex = 0
            for ch in rankText {
                if let empty = ch.wholeNumberValue {
                    fileIndex += empty
                    continue
                }
                guard fileIndex < 8 else { break }
                let square = "\(files[fileIndex])\(rank)"
                board[square] = ch
                fileIndex += 1
            }
        }
        return board
    }
}
