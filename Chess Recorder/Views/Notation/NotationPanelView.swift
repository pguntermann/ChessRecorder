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
    let engineAnalysisVisible: Bool
    let engineAnalysisUseAlgebraicNotation: Bool
    @Bindable var engineAnalysis: EngineAnalysisService
    var onClearPGN: (() -> Void)?
    var onActivateGame: ((UUID) -> Void)?
    var onDeleteGame: ((UUID) -> Void)?

    @State private var exportItem: ShareablePGNExport?
    @State private var cachedFullPGN = ""
    @State private var cachedRows: [UUID: GameRowPresentation] = [:]
    @State private var presentationCacheKey = ""

    private var hasAnyPGNContent: Bool {
        !pgnArchive.games.isEmpty || !game.moves.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if engineAnalysisVisible {
                EngineAnalysisSectionView(
                    game: game,
                    useAlgebraicNotation: engineAnalysisUseAlgebraicNotation,
                    analysisService: engineAnalysis
                )

                Divider()
            }

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
                    .disabled(!hasAnyPGNContent)

                    Button {
                        sharePGN()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .imageScale(.medium)
                    }
                    .disabled(!hasAnyPGNContent)

                    Button {
                        onClearPGN?()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.subheadline)
                            .imageScale(.medium)
                    }
                    .disabled(!hasAnyPGNContent)
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
                                    presentation: cachedRows[recordedGame.id],
                                    hideHeaderTags: hidePGNHeaderTags,
                                    isActive: recordedGame.id == pgnArchive.activeGameID,
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
                                presentation: fallbackActiveRowPresentation(),
                                hideHeaderTags: hidePGNHeaderTags,
                                isActive: true,
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
        .onAppear {
            refreshPresentationCacheIfNeeded()
        }
        .onChange(of: presentationInvalidationKey) { _, _ in
            refreshPresentationCacheIfNeeded()
        }
        #if os(iOS)
        .sheet(item: $exportItem, onDismiss: cleanupExport) { item in
            ShareSheet(items: [item.url])
        }
        #endif
    }

    private var presentationInvalidationKey: String {
        PGNPresentationBuilder.cacheKey(
            games: pgnArchive.games,
            activeGameID: pgnArchive.activeGameID,
            activePlyIndex: game.activePlyIndex,
            isAtLatestMove: game.isAtLatestMove,
            metadata: metadata,
            hidePGNHeaderTags: hidePGNHeaderTags
        )
    }

    private func refreshPresentationCacheIfNeeded() {
        let key = presentationInvalidationKey
        guard key != presentationCacheKey else { return }
        presentationCacheKey = key
        let builtRows = PGNPresentationBuilder.build(
            games: pgnArchive.games,
            activeGameID: pgnArchive.activeGameID,
            activePlyIndex: game.activePlyIndex,
            isAtLatestMove: game.isAtLatestMove,
            metadata: metadata,
            hidePGNHeaderTags: hidePGNHeaderTags
        )
        cachedRows = builtRows
    }

    private func fallbackActiveRowPresentation() -> GameRowPresentation {
        return PGNPresentationBuilder.rowPresentation(
            for: RecordedGame(
                moves: game.moves,
                round: 1,
                result: game.gameResult,
                eco: nil,
                openingName: nil
            ),
            eco: nil,
            activePlyIndex: game.activePlyIndex,
            isAtLatestMove: game.isAtLatestMove,
            showMoveHighlight: true
        )
    }

    private func copyPGNToClipboard() {
        cachedFullPGN = PGNExportService.fullPGN(for: pgnArchive, metadata: metadata)
        #if os(iOS)
        UIPasteboard.general.string = cachedFullPGN
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cachedFullPGN, forType: .string)
        #endif
    }

    private func sharePGN() {
        cachedFullPGN = PGNExportService.fullPGN(for: pgnArchive, metadata: metadata)
        guard !cachedFullPGN.isEmpty else { return }
        do {
            let url = try PGNExportService.writeTemporaryFile(content: cachedFullPGN)
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

private struct GamePGNRowView: View {
    let recordedGame: RecordedGame
    let metadata: PGNMetadata
    let presentation: GameRowPresentation?
    var hideHeaderTags: Bool = true
    let isActive: Bool
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
                    date: recordedGame.date,
                    eco: presentation?.eco
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
            } else if showMoveHighlight, let presentation {
                Text(presentation.highlightedMovetext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(presentation?.plainMovetext ?? PGNFormatter.movetext(from: recordedGame.moves, result: recordedGame.result))
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
}
