//
//  NotationPanelView.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import SwiftUI

private struct ShareablePGNExport: Identifiable {
    let id = UUID()
    let url: URL
}

struct NotationPanelView: View {
    let game: ChessGame
    @Bindable var pgnArchive: PGNArchive
    let metadata: PGNMetadata
    var hidePGNHeaderTags: Bool = true
    let transcript: String
    let isRecording: Bool
    let dictationPauseDeadline: Date?
    let dictationPauseDuration: TimeInterval
    let pendingFailure: RecognitionFailureContext?
    let isRebuildingLanguageModel: Bool
    let engineAnalysisVisible: Bool
    let engineAnalysisUseAlgebraicNotation: Bool
    @Bindable var engineAnalysis: EngineAnalysisService
    var onTeachPhrase: (() -> Void)?
    var onDismissFailure: (() -> Void)?
    var onClearPGN: (() -> Void)?
    var onActivateGame: ((UUID) -> Void)?
    var onDeleteGame: ((UUID) -> Void)?
    
    @State private var exportItem: ShareablePGNExport?

    private var fullPGNNotation: String {
        pgnArchive.displayText(metadata: metadata)
    }

    private var hasAnyPGNContent: Bool {
        !pgnArchive.games.isEmpty || !game.moves.isEmpty
    }
    
    private var transcriptPlaceholder: String {
        if isRebuildingLanguageModel {
            return "Updating speech model…"
        }
        return isRecording ? "Listening..." : "Tap Record to start"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Live Transcript")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(transcript.isEmpty ? transcriptPlaceholder : transcript)
                    .font(.caption)
                    .foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                DictationPauseIndicator(
                    deadline: dictationPauseDeadline,
                    duration: dictationPauseDuration,
                    isActive: isRecording
                        && dictationPauseDeadline != nil
                        && dictationPauseDuration > 0
                        && !transcript.isEmpty
                )
                
                if let pendingFailure {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn't find a valid move for what was heard.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        
                        HStack {
                            Button("Teach phrase") {
                                onTeachPhrase?()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("Dismiss") {
                                onDismissFailure?()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        if !pendingFailure.attemptedMoves.isEmpty {
                            Text("Tried: \(pendingFailure.attemptedMoves.joined(separator: ", "))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            
            if engineAnalysisVisible {
                Divider()
                
                EngineAnalysisSectionView(
                    game: game,
                    useAlgebraicNotation: engineAnalysisUseAlgebraicNotation,
                    analysisService: engineAnalysis
                )
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PGN Notation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        copyPGNToClipboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline)
                            .imageScale(.medium)
                    }
                    .disabled(fullPGNNotation.isEmpty)
                    
                    Button {
                        sharePGN()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .imageScale(.medium)
                    }
                    .disabled(fullPGNNotation.isEmpty)
                    
                    Button {
                        onClearPGN?()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.subheadline)
                            .imageScale(.medium)
                    }
                    .disabled(fullPGNNotation.isEmpty)
                }
                
                if hasAnyPGNContent {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(pgnArchive.games) { recordedGame in
                            SwipeToDeleteRow {
                                onDeleteGame?(recordedGame.id)
                            } content: {
                                GamePGNRowView(
                                    recordedGame: recordedGame,
                                    metadata: metadata,
                                    hideHeaderTags: hidePGNHeaderTags,
                                    isActive: recordedGame.id == pgnArchive.activeGameID,
                                    activePlyIndex: game.activePlyIndex,
                                    isAtLatestMove: game.isAtLatestMove,
                                    showMoveHighlight: recordedGame.id == pgnArchive.activeGameID
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onActivateGame?(recordedGame.id)
                                }
                            }
                        }

                        if pgnArchive.games.isEmpty, !game.moves.isEmpty {
                            GamePGNRowView(
                                recordedGame: RecordedGame(
                                    moves: game.moves,
                                    round: 1,
                                    result: game.gameResult
                                ),
                                metadata: metadata,
                                hideHeaderTags: hidePGNHeaderTags,
                                isActive: true,
                                activePlyIndex: game.activePlyIndex,
                                isAtLatestMove: game.isAtLatestMove,
                                showMoveHighlight: true
                            )
                        }
                    }
                } else {
                    Text("No games yet")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
        }
        #if os(iOS)
        .sheet(item: $exportItem, onDismiss: cleanupExport) { item in
            ShareSheet(items: [item.url])
        }
        #endif
    }
    
    private func copyPGNToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = fullPGNNotation
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullPGNNotation, forType: .string)
        #endif
    }
    
    private func sharePGN() {
        guard !fullPGNNotation.isEmpty else { return }
        do {
            let url = try PGNExport.writeTemporaryFile(content: fullPGNNotation)
            exportItem = ShareablePGNExport(url: url)
        } catch {
            print("PGN export failed: \(error.localizedDescription)")
        }
    }
    
    private func cleanupExport() {
        if let exportItem {
            try? FileManager.default.removeItem(at: exportItem.url)
        }
        exportItem = nil
    }
}

private struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0

    private let revealWidth: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackground

            content()
                .background {
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
                .offset(x: offset)
                .gesture(dragGesture)
        }
    }

    private var deleteBackground: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            Button {
                performDelete(animated: true)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(uiColor: .systemRed))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if value.translation.width < 0 {
                    offset = max(-revealWidth, value.translation.width)
                } else if offset < 0 {
                    offset = min(0, -revealWidth + value.translation.width)
                }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    snapClosed()
                    return
                }

                let predicted = value.predictedEndTranslation.width
                if value.translation.width < -revealWidth * 1.25 || predicted < -revealWidth * 2.5 {
                    performDelete(animated: true)
                } else if offset < -revealWidth / 2 {
                    snapOpen()
                } else {
                    snapClosed()
                }
            }
    }

    private func snapOpen() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            offset = -revealWidth
        }
    }

    private func snapClosed() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            offset = 0
        }
    }

    private func performDelete(animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                offset = -400
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                onDelete()
                offset = 0
            }
        } else {
            onDelete()
            offset = 0
        }
    }
}

private struct GamePGNRowView: View {
    let recordedGame: RecordedGame
    let metadata: PGNMetadata
    var hideHeaderTags: Bool = true
    let isActive: Bool
    let activePlyIndex: Int
    let isAtLatestMove: Bool
    let showMoveHighlight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(recordedGame.summaryTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive ? .primary : .secondary)

                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                if recordedGame.isReviewOnly {
                    Text("Review")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !hideHeaderTags {
                Text(PGNFormatter.headers(
                    round: recordedGame.round,
                    result: recordedGame.result,
                    metadata: metadata,
                    date: recordedGame.date
                ))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if recordedGame.moves.isEmpty {
                Text("No moves yet")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if showMoveHighlight {
                Text(highlightedMovetext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(PGNFormatter.movetext(from: recordedGame.moves, result: recordedGame.result))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            Rectangle()
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        }
    }

    private var highlightedMovetext: AttributedString {
        var text = AttributedString()
        let activeMoveIndex = activePlyIndex > 0 ? activePlyIndex - 1 : nil

        for (index, move) in recordedGame.moves.enumerated() {
            if index % 2 == 0 {
                var moveNumber = AttributedString("\(index / 2 + 1). ")
                moveNumber.foregroundColor = moveColor(for: index, isMoveNumber: true)
                text.append(moveNumber)
            }

            var san = AttributedString(move.algebraicNotation)
            san.foregroundColor = moveColor(for: index, isMoveNumber: false)

            if index == activeMoveIndex {
                san.font = .system(.caption, design: .monospaced).bold()
                san.backgroundColor = Color.accentColor.opacity(0.25)
            }

            text.append(san)
            text.append(AttributedString(" "))
        }

        if recordedGame.result != .ongoing {
            var resultText = AttributedString(recordedGame.result.rawValue)
            resultText.foregroundColor = .secondary
            text.append(resultText)
        }

        return text
    }

    private func moveColor(for index: Int, isMoveNumber: Bool) -> Color {
        if !isAtLatestMove && index >= activePlyIndex {
            return .secondary.opacity(0.45)
        }
        return isMoveNumber ? .secondary : .primary
    }
}

private struct DictationPauseIndicator: View {
    let deadline: Date?
    let duration: TimeInterval
    let isActive: Bool
    
    private static let reservedHeight: CGFloat = 28
    
    var body: some View {
        Group {
            if isActive, let deadline, duration > 0 {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    let remaining = max(0, deadline.timeIntervalSince(timeline.date))
                    let progress = duration > 0 ? min(1, remaining / duration) : 0
                    
                    indicatorContent(remaining: remaining, progress: progress)
                }
            } else {
                indicatorContent(remaining: 0, progress: 0)
            }
        }
        .frame(height: Self.reservedHeight, alignment: .top)
        .padding(.top, 4)
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Interpreting move")
        .accessibilityValue(accessibilityValue)
        .accessibilityHidden(!isActive)
    }
    
    private var accessibilityValue: String {
        guard isActive, let deadline else { return "" }
        return String(format: "%.1f seconds remaining", max(0, deadline.timeIntervalSinceNow))
    }
    
    private func indicatorContent(remaining: TimeInterval, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Interpreting in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f s", remaining))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width)
                        .scaleEffect(x: progress, y: 1, anchor: .leading)
                }
            }
            .frame(height: 4)
        }
    }
}
