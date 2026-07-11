//
//  BoardLayoutMetrics.swift
//  Chess Recorder
//

import CoreGraphics

enum BoardLayoutMetrics {
    static let evalBarWidth: CGFloat = 27
    static let evalBarSpacing: CGFloat = 10

    struct Dimensions {
        let side: CGFloat
        let squareSize: CGFloat

        init(boardSide: CGFloat) {
            let squares = max(1, Int(boardSide / 8))
            squareSize = CGFloat(squares)
            side = squareSize * 8
        }
    }

    static func scaledBoardSide(naturalSide: CGFloat, sizePercent: Double) -> CGFloat {
        let percent = CGFloat(sizePercent)
        guard percent < 1, naturalSide > 0 else { return naturalSide }
        return max(8, floor(naturalSide * percent / 8) * 8)
    }

    static func computedBoardSide(
        availableWidth: CGFloat,
        maxBoardHeight: CGFloat?,
        showEvaluationBar: Bool,
        boardSizePercent: Double
    ) -> CGFloat {
        let horizontalOverhead = showEvaluationBar ? evalBarWidth + evalBarSpacing : 0
        let cappedHeight = maxBoardHeight ?? .infinity
        let naturalSide = floor(
            min(max(0, availableWidth - horizontalOverhead), cappedHeight) / 8
        ) * 8
        return Dimensions(
            boardSide: scaledBoardSide(naturalSide: naturalSide, sizePercent: boardSizePercent)
        ).side
    }
}
