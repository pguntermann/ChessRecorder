//
//  GameReportPDFBoardRenderer.swift
//  Chess Recorder
//

import ChessKit
import SwiftUI
import UIKit

/// Draws miniature boards for PDF export using the same square colors / piece scale as the main board.
enum GameReportPDFBoardRenderer {
    struct Appearance: Sendable {
        var lightSquare: (r: CGFloat, g: CGFloat, b: CGFloat)
        var darkSquare: (r: CGFloat, g: CGFloat, b: CGFloat)
        var pieceSizePercent: Double
        var highlight: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)

        @MainActor
        static func from(miniBoard: MiniChessBoardAppearance, highlight: UIColor = UIColor(red: 0.85, green: 0.65, blue: 0.1, alpha: 1)) -> Appearance {
            Appearance(
                lightSquare: rgb(UIColor(miniBoard.lightSquareColor)),
                darkSquare: rgb(UIColor(miniBoard.darkSquareColor)),
                pieceSizePercent: miniBoard.pieceSizePercent,
                highlight: rgba(highlight)
            )
        }

        private static func rgb(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b)
        }

        private static func rgba(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b, a)
        }
    }

    static func render(
        fen: String,
        side: CGFloat,
        appearance: Appearance,
        highlightedFrom: ChessPosition? = nil,
        highlightedTo: ChessPosition? = nil
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let square = side / 8
            let pieceInset = square * CGFloat(1 - appearance.pieceSizePercent) / 2
            let pieces = piecesGrid(from: fen)

            for rank in 0..<8 {
                for file in 0..<8 {
                    let isLight = (file + rank) % 2 == 1
                    // White at bottom (PDF default).
                    let visualFile = file
                    let visualRank = 7 - rank
                    let rect = CGRect(
                        x: CGFloat(visualFile) * square,
                        y: CGFloat(visualRank) * square,
                        width: square,
                        height: square
                    )

                    let fill = isLight ? appearance.lightSquare : appearance.darkSquare
                    cg.setFillColor(red: fill.r, green: fill.g, blue: fill.b, alpha: 1)
                    cg.fill(rect)

                    if isHighlighted(file: file, rank: rank, from: highlightedFrom, to: highlightedTo) {
                        let h = appearance.highlight
                        cg.setFillColor(red: h.r, green: h.g, blue: h.b, alpha: h.a * 0.45)
                        cg.fill(rect)
                    }

                    if let piece = pieces[file][rank],
                       let image = UIImage(named: piece.imageName) {
                        let pieceRect = rect.insetBy(dx: pieceInset, dy: pieceInset)
                        image.draw(in: pieceRect)
                    }
                }
            }

            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
            cg.setLineWidth(0.5)
            cg.stroke(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private static func isHighlighted(
        file: Int,
        rank: Int,
        from: ChessPosition?,
        to: ChessPosition?
    ) -> Bool {
        if let from, from.file == file, from.rank == rank { return true }
        if let to, to.file == file, to.rank == rank { return true }
        return false
    }

    private static func piecesGrid(from fen: String) -> [[ChessPiece?]] {
        var grid = Array(repeating: Array(repeating: ChessPiece?.none, count: 8), count: 8)
        guard let position = Position(fen: fen) else { return grid }
        for piece in position.pieces {
            let appPosition = ChessKitMapping.appPosition(from: piece.square)
            guard (0..<8).contains(appPosition.file), (0..<8).contains(appPosition.rank) else { continue }
            grid[appPosition.file][appPosition.rank] = ChessKitMapping.appPiece(from: piece)
        }
        return grid
    }
}
