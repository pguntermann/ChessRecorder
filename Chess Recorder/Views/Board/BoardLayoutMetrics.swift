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

    struct Footprint {
        let boardSide: CGFloat
        let rankGutter: CGFloat
        let fileGutter: CGFloat

        var totalWidth: CGFloat { rankGutter + boardSide }
        var totalHeight: CGFloat { boardSide + fileGutter }

        func widthIncludingEvalBar(_ showEvaluationBar: Bool) -> CGFloat {
            totalWidth + (showEvaluationBar ? evalBarWidth + evalBarSpacing : 0)
        }
    }

    static func coordinateGutterLength(fontSize: Double, boardScale: Double) -> CGFloat {
        let scaledFont = max(6, fontSize * boardScale)
        return max(12, ceil(scaledFont * 1.25) + 6)
    }

    static func scaledBoardSide(naturalSide: CGFloat, sizePercent: Double) -> CGFloat {
        let percent = CGFloat(sizePercent)
        guard percent < 1, naturalSide > 0 else { return naturalSide }
        return max(8, floor(naturalSide * percent / 8) * 8)
    }

    static func computedFootprint(
        availableWidth: CGFloat,
        maxBoardHeight: CGFloat?,
        showEvaluationBar: Bool,
        boardSizePercent: Double,
        showCoordinates: Bool,
        coordinatesOutsideBoard: Bool,
        coordinateFontSize: Double
    ) -> Footprint {
        let rankGutter = showCoordinates && coordinatesOutsideBoard
            ? coordinateGutterLength(fontSize: coordinateFontSize, boardScale: boardSizePercent)
            : 0
        let fileGutter = rankGutter
        let horizontalOverhead = showEvaluationBar ? evalBarWidth + evalBarSpacing : 0
        let cappedHeight = maxBoardHeight ?? .infinity

        let widthForBoard = max(0, availableWidth - horizontalOverhead - rankGutter)
        let heightForBoard = max(0, cappedHeight - fileGutter)
        let naturalSide = floor(min(widthForBoard, heightForBoard) / 8) * 8
        let boardSide = Dimensions(
            boardSide: scaledBoardSide(naturalSide: naturalSide, sizePercent: boardSizePercent)
        ).side

        return Footprint(
            boardSide: boardSide,
            rankGutter: rankGutter,
            fileGutter: fileGutter
        )
    }

    static func computedBoardSide(
        availableWidth: CGFloat,
        maxBoardHeight: CGFloat?,
        showEvaluationBar: Bool,
        boardSizePercent: Double,
        showCoordinates: Bool = true,
        coordinatesOutsideBoard: Bool = true,
        coordinateFontSize: Double = 14
    ) -> CGFloat {
        computedFootprint(
            availableWidth: availableWidth,
            maxBoardHeight: maxBoardHeight,
            showEvaluationBar: showEvaluationBar,
            boardSizePercent: boardSizePercent,
            showCoordinates: showCoordinates,
            coordinatesOutsideBoard: coordinatesOutsideBoard,
            coordinateFontSize: coordinateFontSize
        ).boardSide
    }
}
