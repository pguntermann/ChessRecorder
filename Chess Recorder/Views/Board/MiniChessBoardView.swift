//
//  MiniChessBoardView.swift
//  Chess Recorder
//

import ChessKit
import SwiftUI

/// Square colors and piece scale shared with the main board settings.
struct MiniChessBoardAppearance {
    var lightSquareColor: Color
    var darkSquareColor: Color
    /// Fraction of a square’s edge used for the piece (same as `AppSettings.pieceSizePercent`).
    var pieceSizePercent: Double

    static let `default` = MiniChessBoardAppearance(
        lightSquareColor: Color(red: 0.86, green: 0.93, blue: 0.98),
        darkSquareColor: Color(red: 0.36, green: 0.52, blue: 0.71),
        pieceSizePercent: 0.9
    )
}

/// Read-only miniature board for opening-book previews (no interaction).
struct MiniChessBoardView: View {
    let fen: String
    var side: CGFloat = 72
    var orientation: BoardOrientation = .whiteAtBottom
    var appearance: MiniChessBoardAppearance = .default
    /// Squares tinted for the move that reached this position (from / to).
    var highlightedFrom: ChessPosition? = nil
    var highlightedTo: ChessPosition? = nil
    var highlightColor: Color = Color(red: 0.85, green: 0.65, blue: 0.1)

    var body: some View {
        Canvas { context, size in
            let square = size.width / 8
            let pieceInset = square * CGFloat(1 - appearance.pieceSizePercent) / 2
            let pieces = Self.pieces(from: fen)

            for rank in 0..<8 {
                for file in 0..<8 {
                    let isLight = (file + rank) % 2 == 1
                    let visualFile = orientation == .whiteAtBottom ? file : 7 - file
                    let visualRank = orientation == .whiteAtBottom ? 7 - rank : rank
                    let rect = CGRect(
                        x: CGFloat(visualFile) * square,
                        y: CGFloat(visualRank) * square,
                        width: square,
                        height: square
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? appearance.lightSquareColor : appearance.darkSquareColor)
                    )

                    if isHighlighted(file: file, rank: rank) {
                        context.fill(
                            Path(rect),
                            with: .color(highlightColor.opacity(0.45))
                        )
                    }

                    if let piece = pieces[file][rank],
                       let image = context.resolveSymbol(id: piece.imageName) {
                        context.draw(image, in: rect.insetBy(dx: pieceInset, dy: pieceInset))
                    }
                }
            }
        } symbols: {
            ForEach(Self.pieceImageNames, id: \.self) { name in
                Image(name)
                    .resizable()
                    .tag(name)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func isHighlighted(file: Int, rank: Int) -> Bool {
        if let from = highlightedFrom, from.file == file, from.rank == rank {
            return true
        }
        if let to = highlightedTo, to.file == file, to.rank == rank {
            return true
        }
        return false
    }

    private static let pieceImageNames: [String] = [
        "wp", "wn", "wb", "wr", "wq", "wk",
        "bp", "bn", "bb", "br", "bq", "bk"
    ]

    /// file × rank grid (0 = a-file / rank 1).
    private static func pieces(from fen: String) -> [[ChessPiece?]] {
        var grid = Array(
            repeating: Array(repeating: ChessPiece?.none, count: 8),
            count: 8
        )
        guard let position = Position(fen: fen) else { return grid }
        for piece in position.pieces {
            let appPosition = ChessKitMapping.appPosition(from: piece.square)
            guard (0..<8).contains(appPosition.file), (0..<8).contains(appPosition.rank) else { continue }
            grid[appPosition.file][appPosition.rank] = ChessKitMapping.appPiece(from: piece)
        }
        return grid
    }
}
