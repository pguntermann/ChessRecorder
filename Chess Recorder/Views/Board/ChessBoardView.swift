//
//  ChessBoardView.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import SwiftUI

enum BoardOrientation {
    case whiteAtBottom
    case blackAtBottom
    
    mutating func toggle() {
        self = self == .whiteAtBottom ? .blackAtBottom : .whiteAtBottom
    }
    
    var displayRanks: [Int] {
        self == .whiteAtBottom ? Array((0..<8).reversed()) : Array(0..<8)
    }
    
    var displayFiles: [Int] {
        self == .whiteAtBottom ? Array(0..<8) : Array((0..<8).reversed())
    }
}

private struct PendingPromotion {
    let from: ChessPosition
    let to: ChessPosition
}

struct ChessBoardView: View {
    let game: ChessGame
    let settings: AppSettings
    let boardSide: CGFloat
    var orientation: BoardOrientation = .whiteAtBottom
    var touchInputEnabled: Bool = false
    var analysisArrow: AnalysisArrowMove?
    var lastMoveArrow: AnalysisArrowMove?
    var chessEngine: ChessEngine?

    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedSquare: ChessPosition?
    @State private var legalDestinations: Set<ChessPosition> = []
    @State private var pendingPromotion: PendingPromotion?
    @State private var showPromotionPicker = false
    
    private var boardDimensions: BoardLayoutMetrics.Dimensions {
        BoardLayoutMetrics.Dimensions(boardSide: boardSide)
    }

    private var coordinateGutter: CGFloat {
        BoardLayoutMetrics.coordinateGutterLength(
            fontSize: settings.coordinateFontSize,
            boardScale: settings.boardSizePercent
        )
    }

    /// Legible on light and dark system backgrounds when coordinates sit outside the board.
    private var outsideCoordinateColor: Color {
        colorScheme == .dark
            ? Color(red: 0.76, green: 0.76, blue: 0.78)
            : Color(red: 0.36, green: 0.36, blue: 0.38)
    }

    var body: some View {
        let dimensions = boardDimensions
        let squareSize = dimensions.squareSize
        let exactSide = dimensions.side

        Group {
            if settings.usesOutsideCoordinates {
                outsideCoordinateBoard(squareSize: squareSize, exactSide: exactSide)
            } else {
                boardCore(squareSize: squareSize, exactSide: exactSide)
            }
        }
        .onChange(of: game.activePlyIndex) { _, _ in
            clearSelection()
        }
        .onChange(of: game.activeMoveAnimation?.id) { _, newID in
            guard newID != nil, settings.moveAnimationDuration <= 0,
                  let animation = game.activeMoveAnimation else { return }
            game.clearMoveAnimation(id: animation.id)
        }
        .onChange(of: game.moves.count) { _, _ in
            clearSelection()
        }
        .onChange(of: touchInputEnabled) { _, enabled in
            if !enabled {
                clearSelection()
            }
        }
        .confirmationDialog(
            "Promote pawn",
            isPresented: $showPromotionPicker,
            titleVisibility: .visible
        ) {
            promotionButton("Queen", piece: .queen)
            promotionButton("Rook", piece: .rook)
            promotionButton("Bishop", piece: .bishop)
            promotionButton("Knight", piece: .knight)
            Button("Cancel", role: .cancel) {
                pendingPromotion = nil
            }
        }
    }

    @ViewBuilder
    private func outsideCoordinateBoard(squareSize: CGFloat, exactSide: CGFloat) -> some View {
        let ranksOnLeading = orientation == .whiteAtBottom
        let filesOnBottom = orientation == .whiteAtBottom

        VStack(spacing: 0) {
            if !filesOnBottom {
                outsideFileLabelRow(
                    squareSize: squareSize,
                    ranksOnLeading: ranksOnLeading
                )
            }

            HStack(spacing: 0) {
                if ranksOnLeading {
                    outsideRankLabelColumn(squareSize: squareSize)
                }

                boardCore(squareSize: squareSize, exactSide: exactSide)

                if !ranksOnLeading {
                    outsideRankLabelColumn(squareSize: squareSize)
                }
            }

            if filesOnBottom {
                outsideFileLabelRow(
                    squareSize: squareSize,
                    ranksOnLeading: ranksOnLeading
                )
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private func outsideFileLabelRow(squareSize: CGFloat, ranksOnLeading: Bool) -> some View {
        HStack(spacing: 0) {
            if ranksOnLeading {
                Color.clear
                    .frame(width: coordinateGutter, height: coordinateGutter)
            }

            HStack(spacing: 0) {
                ForEach(orientation.displayFiles, id: \.self) { file in
                    Text(fileLabel(for: file))
                        .font(settings.coordinateFont(boardScale: settings.boardSizePercent))
                        .foregroundStyle(outsideCoordinateColor)
                        .frame(width: squareSize, height: coordinateGutter)
                }
            }

            if !ranksOnLeading {
                Color.clear
                    .frame(width: coordinateGutter, height: coordinateGutter)
            }
        }
    }

    @ViewBuilder
    private func outsideRankLabelColumn(squareSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(orientation.displayRanks, id: \.self) { rank in
                Text("\(rank + 1)")
                    .font(settings.coordinateFont(boardScale: settings.boardSizePercent))
                    .foregroundStyle(outsideCoordinateColor)
                    .frame(width: coordinateGutter, height: squareSize)
            }
        }
    }

    @ViewBuilder
    private func boardCore(squareSize: CGFloat, exactSide: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            boardGrid(squareSize: squareSize, exactSide: exactSide)

            if let lastMoveArrow {
                AnalysisArrowOverlay(
                    move: lastMoveArrow,
                    squareSize: squareSize,
                    orientation: orientation,
                    color: settings.lastMoveArrowColor.color
                )
                .frame(width: exactSide, height: exactSide, alignment: .topLeading)
            }

            if let analysisArrow {
                AnalysisArrowOverlay(
                    move: analysisArrow,
                    squareSize: squareSize,
                    orientation: orientation,
                    color: settings.engineAnalysisArrowColor.color
                )
                .frame(width: exactSide, height: exactSide, alignment: .topLeading)
            }
            
            if settings.moveAnimationDuration > 0,
               let animation = game.activeMoveAnimation {
                MoveAnimationOverlay(
                    animation: animation,
                    squareSize: squareSize,
                    pieceSize: squareSize * settings.pieceSizePercent,
                    duration: settings.moveAnimationDuration,
                    orientation: orientation
                ) {
                    game.clearMoveAnimation(id: animation.id)
                }
                .id(animation.id)
                .frame(width: exactSide, height: exactSide, alignment: .topLeading)
            }
        }
        .frame(width: exactSide, height: exactSide, alignment: .topLeading)
        .fixedSize()
        .overlay {
            Rectangle()
                .strokeBorder(Color.secondary, lineWidth: 2)
        }
        .overlay {
            if let status = boardStatusOverlay {
                BoardGlassStatusOverlay(
                    squareSize: squareSize,
                    systemImage: status.icon,
                    title: status.title
                )
            }
        }
    }

    private func fileLabel(for file: Int) -> String {
        String("abcdefgh"[String.Index(utf16Offset: file, in: "abcdefgh")])
    }
    
    @ViewBuilder
    private func boardGrid(squareSize: CGFloat, exactSide: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(orientation.displayRanks, id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(orientation.displayFiles, id: \.self) { file in
                        let position = ChessPosition(file: file, rank: rank)
                        ChessSquareView(
                            position: position,
                            piece: shouldHidePiece(at: position) ? nil : game.board[file][rank],
                            squareSize: squareSize,
                            settings: settings,
                            coordinateScale: settings.boardSizePercent,
                            orientation: orientation,
                            isSelected: selectedSquare == position,
                            isLegalDestination: legalDestinations.contains(position),
                            touchInputEnabled: touchInputEnabled
                        ) {
                            handleSquareTap(at: position)
                        }
                    }
                }
                .frame(width: exactSide, height: squareSize, alignment: .topLeading)
            }
        }
        .frame(width: exactSide, height: exactSide, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: true)
    }
    
    @ViewBuilder
    private func promotionButton(_ title: String, piece: PieceType) -> some View {
        Button(title) {
            guard let pendingPromotion, let chessEngine else { return }
            if chessEngine.executeTouchMove(
                from: pendingPromotion.from,
                to: pendingPromotion.to,
                promotion: piece
            ) {
                clearSelection()
            }
            self.pendingPromotion = nil
        }
    }
    
    private func handleSquareTap(at position: ChessPosition) {
        guard touchInputEnabled, let chessEngine else { return }
        
        if let selectedSquare {
            if position == selectedSquare {
                clearSelection()
                return
            }
            
            if legalDestinations.contains(position) {
                if chessEngine.requiresPromotion(from: selectedSquare, to: position) {
                    pendingPromotion = PendingPromotion(from: selectedSquare, to: position)
                    showPromotionPicker = true
                    return
                }
                
                if chessEngine.executeTouchMove(from: selectedSquare, to: position) {
                    clearSelection()
                }
                return
            }
        }
        
        if let piece = game.pieceAt(position), piece.color == game.currentTurn {
            selectedSquare = position
            legalDestinations = Set(chessEngine.legalDestinations(from: position))
            return
        }
        
        clearSelection()
    }
    
    private func clearSelection() {
        selectedSquare = nil
        legalDestinations = []
        pendingPromotion = nil
    }
    
    private func shouldHidePiece(at position: ChessPosition) -> Bool {
        guard let animation = game.activeMoveAnimation else { return false }
        if position == animation.primary.to { return true }
        if let secondary = animation.secondary, position == secondary.to { return true }
        return false
    }
    private var boardStatusOverlay: (icon: String, title: String)? {
        if !game.isAtLatestMove {
            return ("clock.arrow.circlepath", "Reviewing history")
        }
        if let message = game.gameStatusMessage {
            return (game.isGameOver ? "flag.checkered" : "info.circle", message)
        }
        return nil
    }
}

private struct BoardGlassStatusOverlay: View {
    let squareSize: CGFloat
    let systemImage: String
    let title: String

    private var iconSize: CGFloat { max(14, squareSize * 0.24) }
    private var labelSize: CGFloat { max(12, squareSize * 0.21) }

    var body: some View {
        HStack(spacing: max(5, squareSize * 0.1)) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.system(size: labelSize, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, max(10, squareSize * 0.22))
        .padding(.vertical, max(6, squareSize * 0.12))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .padding(.top, max(6, squareSize * 0.08))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

private struct AnalysisArrowOverlay: View {
    let move: AnalysisArrowMove
    let squareSize: CGFloat
    let orientation: BoardOrientation
    let color: Color

    var body: some View {
        Canvas { context, size in
            let from = squareCenter(for: move.from, squareSize: squareSize, orientation: orientation)
            let to = squareCenter(for: move.to, squareSize: squareSize, orientation: orientation)
            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength = max(14, squareSize * 0.32)
            let shaftEnd = CGPoint(
                x: to.x - cos(angle) * (headLength * 0.8),
                y: to.y - sin(angle) * (headLength * 0.8)
            )

            var path = Path()
            path.move(to: from)
            path.addLine(to: shaftEnd)

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: max(6, squareSize * 0.12), lineCap: .round)
            )

            let wingAngle = CGFloat.pi / 7

            let tip = to
            let left = CGPoint(
                x: tip.x - cos(angle - wingAngle) * headLength,
                y: tip.y - sin(angle - wingAngle) * headLength
            )
            let right = CGPoint(
                x: tip.x - cos(angle + wingAngle) * headLength,
                y: tip.y - sin(angle + wingAngle) * headLength
            )

            var head = Path()
            head.move(to: tip)
            head.addLine(to: left)
            head.addLine(to: right)
            head.closeSubpath()
            context.fill(head, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

struct ChessSquareView: View {
    let position: ChessPosition
    let piece: ChessPiece?
    let squareSize: CGFloat
    let settings: AppSettings
    var coordinateScale: Double = 1
    var orientation: BoardOrientation = .whiteAtBottom
    var isSelected: Bool = false
    var isLegalDestination: Bool = false
    var touchInputEnabled: Bool = false
    var onTap: (() -> Void)?
    
    private var isLightSquare: Bool {
        (position.file + position.rank) % 2 == 1
    }
    
    private var pieceSize: CGFloat {
        squareSize * settings.pieceSizePercent
    }

    private var coordinatePadding: CGFloat {
        max(1, 2 * coordinateScale)
    }
    
    private var showsRankLabel: Bool {
        orientation == .whiteAtBottom ? position.file == 0 : position.file == 7
    }
    
    private var showsFileLabel: Bool {
        orientation == .whiteAtBottom ? position.rank == 0 : position.rank == 7
    }

    private func fileLabel(for file: Int) -> String {
        String("abcdefgh"[String.Index(utf16Offset: file, in: "abcdefgh")])
    }
    
    private var touchHighlightColor: Color {
        settings.touchInputHighlightColor.color
    }

    private var insideCoordinateColor: Color {
        settings.coordinateColor.color
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isLightSquare ? settings.lightSquareColor.color : settings.darkSquareColor.color)
            
            if isSelected {
                Rectangle()
                    .fill(touchHighlightColor.opacity(0.35))
            } else if isLegalDestination {
                Circle()
                    .fill(touchHighlightColor.opacity(piece == nil ? 0.45 : 0.25))
                    .frame(
                        width: piece == nil ? squareSize * 0.28 : squareSize * 0.82,
                        height: piece == nil ? squareSize * 0.28 : squareSize * 0.82
                    )
                    .overlay {
                        if piece != nil {
                            Circle()
                                .stroke(touchHighlightColor.opacity(0.7), lineWidth: 3)
                        }
                    }
            }
            
            if let piece = piece {
                Image(piece.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: pieceSize, height: pieceSize)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if settings.showCoordinates, !settings.coordinatesOutsideBoard, showsRankLabel {
                Text("\(position.rank + 1)")
                    .font(settings.coordinateFont(boardScale: coordinateScale))
                    .foregroundStyle(insideCoordinateColor)
                    .padding(coordinatePadding)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if settings.showCoordinates, !settings.coordinatesOutsideBoard, showsFileLabel {
                Text(fileLabel(for: position.file))
                    .font(settings.coordinateFont(boardScale: coordinateScale))
                    .foregroundStyle(insideCoordinateColor)
                    .padding(coordinatePadding)
            }
        }
        .frame(width: squareSize, height: squareSize, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            guard touchInputEnabled else { return }
            onTap?()
        }
    }
}

private struct MoveAnimationOverlay: View {
    let animation: ActiveMoveAnimation
    let squareSize: CGFloat
    let pieceSize: CGFloat
    let duration: TimeInterval
    let orientation: BoardOrientation
    let onComplete: () -> Void
    
    @State private var isAtDestination = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            animatedPiece(animation.primary)
            if let secondary = animation.secondary {
                animatedPiece(secondary)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: duration)) {
                isAtDestination = true
            }
            Task {
                try? await Task.sleep(for: .seconds(duration))
                onComplete()
            }
        }
    }
    
    @ViewBuilder
    private func animatedPiece(_ move: AnimatedPieceMove) -> some View {
        let destination = squareCenter(for: move.to, squareSize: squareSize, orientation: orientation)
        let startOffset = squareOffset(
            from: move.from,
            to: move.to,
            squareSize: squareSize,
            orientation: orientation
        )
        
        Image(move.piece.imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: pieceSize, height: pieceSize)
            .position(destination)
            .offset(isAtDestination ? .zero : startOffset)
    }
}

private func squareCenter(for position: ChessPosition, squareSize: CGFloat, orientation: BoardOrientation) -> CGPoint {
    let visualFile = orientation == .whiteAtBottom ? position.file : 7 - position.file
    let visualRank = orientation == .whiteAtBottom ? 7 - position.rank : position.rank
    return CGPoint(
        x: (CGFloat(visualFile) + 0.5) * squareSize,
        y: (CGFloat(visualRank) + 0.5) * squareSize
    )
}

private func squareOffset(
    from: ChessPosition,
    to: ChessPosition,
    squareSize: CGFloat,
    orientation: BoardOrientation
) -> CGSize {
    let fromPoint = squareCenter(for: from, squareSize: squareSize, orientation: orientation)
    let toPoint = squareCenter(for: to, squareSize: squareSize, orientation: orientation)
    return CGSize(width: fromPoint.x - toPoint.x, height: fromPoint.y - toPoint.y)
}
