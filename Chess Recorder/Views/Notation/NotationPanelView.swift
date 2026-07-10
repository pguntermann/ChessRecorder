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
    let pgnArchive: PGNArchive
    let metadata: PGNMetadata
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
    
    @State private var exportItem: ShareablePGNExport?

    private var fullPGNNotation: String {
        pgnArchive.displayText(currentGame: game, metadata: metadata)
    }

    private var hasAnyPGNContent: Bool {
        !pgnArchive.completedGames.isEmpty || !game.moves.isEmpty
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
                        ForEach(Array(pgnArchive.completedGames.enumerated()), id: \.offset) { _, recordedGame in
                            Text(
                                PGNFormatter.formatGame(
                                    moves: recordedGame.moves,
                                    round: recordedGame.round,
                                    result: recordedGame.result,
                                    metadata: metadata,
                                    date: recordedGame.date
                                )
                            )
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !game.moves.isEmpty {
                            CurrentGamePGNView(
                                moves: game.moves,
                                round: pgnArchive.completedGames.count + 1,
                                result: pgnArchive.currentGameResult,
                                metadata: metadata,
                                activePlyIndex: game.activePlyIndex,
                                isAtLatestMove: game.isAtLatestMove
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

private struct CurrentGamePGNView: View {
    let moves: [ChessMove]
    let round: Int
    let result: PGNResult
    let metadata: PGNMetadata
    let activePlyIndex: Int
    let isAtLatestMove: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(currentGameHeaders)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(highlightedMovetext)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var currentGameHeaders: String {
        PGNFormatter.headers(round: round, result: result, metadata: metadata)
    }

    private var highlightedMovetext: AttributedString {
        var text = AttributedString()
        let activeMoveIndex = activePlyIndex > 0 ? activePlyIndex - 1 : nil

        for (index, move) in moves.enumerated() {
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

        if result != .ongoing {
            var resultText = AttributedString(result.rawValue)
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
