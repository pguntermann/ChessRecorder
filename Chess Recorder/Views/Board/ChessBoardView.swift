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
    var orientation: BoardOrientation = .whiteAtBottom
    var touchInputEnabled: Bool = false
    var analysisArrow: AnalysisArrowMove?
    var chessEngine: ChessEngine?
    
    @State private var selectedSquare: ChessPosition?
    @State private var legalDestinations: Set<ChessPosition> = []
    @State private var pendingPromotion: PendingPromotion?
    @State private var showPromotionPicker = false
    
    var body: some View {
        GeometryReader { geometry in
            let squareSize = min(geometry.size.width, geometry.size.height) / 8
            
            ZStack(alignment: .topLeading) {
                boardGrid(squareSize: squareSize)

                if let analysisArrow {
                    AnalysisArrowOverlay(
                        move: analysisArrow,
                        squareSize: squareSize,
                        orientation: orientation,
                        color: settings.engineAnalysisArrowColor.color
                    )
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
                }
            }
            .frame(width: squareSize * 8, height: squareSize * 8)
            .border(Color.secondary, width: 2)
            .onChange(of: game.activeMoveAnimation?.id) { _, newID in
                guard newID != nil, settings.moveAnimationDuration <= 0,
                      let animation = game.activeMoveAnimation else { return }
                game.clearMoveAnimation(id: animation.id)
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
    private func boardGrid(squareSize: CGFloat) -> some View {
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
                            orientation: orientation,
                            isSelected: selectedSquare == position,
                            isLegalDestination: legalDestinations.contains(position),
                            touchInputEnabled: touchInputEnabled
                        ) {
                            handleSquareTap(at: position)
                        }
                    }
                }
            }
        }
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
    
    private var showsRankLabel: Bool {
        orientation == .whiteAtBottom ? position.file == 0 : position.file == 7
    }
    
    private var showsFileLabel: Bool {
        orientation == .whiteAtBottom ? position.rank == 0 : position.rank == 7
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(isLightSquare ? settings.lightSquareColor.color : settings.darkSquareColor.color)
            
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
            } else if isLegalDestination {
                Circle()
                    .fill(Color.accentColor.opacity(piece == nil ? 0.45 : 0.25))
                    .frame(
                        width: piece == nil ? squareSize * 0.28 : squareSize * 0.82,
                        height: piece == nil ? squareSize * 0.28 : squareSize * 0.82
                    )
                    .overlay {
                        if piece != nil {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.7), lineWidth: 3)
                        }
                    }
            }
            
            if let piece = piece {
                Image(piece.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: pieceSize, height: pieceSize)
            }
            
            VStack {
                Spacer()
                HStack {
                    if showsRankLabel {
                        Text("\(position.rank + 1)")
                            .font(settings.coordinateFont())
                            .foregroundStyle(settings.coordinateColor.color)
                            .padding(2)
                    }
                    Spacer()
                }
            }
            
            if showsFileLabel {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(String("abcdefgh"[String.Index(utf16Offset: position.file, in: "abcdefgh")]))
                            .font(settings.coordinateFont())
                            .foregroundStyle(settings.coordinateColor.color)
                            .padding(2)
                    }
                }
            }
        }
        .frame(width: squareSize, height: squareSize)
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
