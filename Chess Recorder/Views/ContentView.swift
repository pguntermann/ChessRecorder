//
//  ContentView.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Bindable var settingsStore: SettingsStore
    @Bindable var vocabularyStore: PersonalVocabularyStore
    @Bindable var developerModeStore: DeveloperModeStore
    @State private var game = ChessGame()
    @State private var pgnArchive = PGNArchive()
    @State private var speechRecognizer: SpeechRecognizer
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var showingTeachPhrase = false
    @State private var showingRecordingPermissionAlert = false
    @State private var recordingPermissionIssue: RecordingPermissionIssue?
    @State private var boardOrientation: BoardOrientation = .whiteAtBottom
    @State private var engineAnalysis = EngineAnalysisService()
    @State private var openingService = OpeningService()
    @State private var isAppReady = false
    @State private var pendingSpeechModelWork = PendingSpeechModelWork()
    @State private var showSpeechModelRebuildOverlay = false
    
    init(
        settingsStore: SettingsStore,
        vocabularyStore: PersonalVocabularyStore,
        developerModeStore: DeveloperModeStore
    ) {
        self.settingsStore = settingsStore
        self.vocabularyStore = vocabularyStore
        self.developerModeStore = developerModeStore
        _speechRecognizer = State(initialValue: SpeechRecognizer(vocabularyStore: vocabularyStore))
    }
    
    private var chessEngine: ChessEngine {
        ChessEngine(game: game)
    }

    private var canAcceptNewMoves: Bool {
        game.isAtLatestMove && !pgnArchive.activeGameIsReviewOnly
    }
    
    var body: some View {
        @Bindable var speechRecognizer = speechRecognizer

        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                landscapeLayout(in: geometry)
            } else {
                portraitLayout(in: geometry)
            }
        }
        .overlay {
            if !isAppReady {
                InitializationOverlay(
                    phase: speechRecognizer.initializationPhase,
                    context: .startup,
                    statusDetail: speechRecognizer.initializationStatusDetail
                )
                .transition(.opacity)
            } else if showSpeechModelRebuildOverlay || speechRecognizer.isRebuildingLanguageModel {
                InitializationOverlay(
                    phase: speechRecognizer.initializationPhase,
                    context: .speechModelRebuild,
                    statusDetail: speechRecognizer.initializationStatusDetail
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isAppReady)
        .task {
            // Allow the initialization overlay to render before startup work blocks the main actor.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(50))

            setupSpeechRecognizer()
            speechRecognizer.dictationPauseSeconds = settingsStore.settings.dictationPauseSeconds
            engineAnalysis.configure(
                depth: settingsStore.settings.cappedEngineAnalysisDepth,
                unlimited: settingsStore.settings.isEngineAnalysisUncapped
            )
            await speechRecognizer.startup(with: settingsStore.settings.defaultRecognitionLanguage)
            speechRecognizer.setInitializationPhase(.preparingEngine)
            await engineAnalysis.prepare()
            speechRecognizer.setInitializationPhase(.loadingOpenings)
            await openingService.prepare()
            openingService.refresh(game: game)
            isAppReady = true
        }
        .onDisappear {
            Task { await engineAnalysis.shutdown() }
        }
        .onChange(of: settingsStore.settings.dictationPauseSeconds) { _, newValue in
            speechRecognizer.dictationPauseSeconds = newValue
        }
        .onChange(of: settingsStore.settings.engineAnalysisVisible) { _, isVisible in
            if !isVisible {
                engineAnalysis.stop()
            }
        }
        .onChange(of: settingsStore.settings.engineAnalysisDepth) { _, _ in
            engineAnalysis.configure(
                depth: settingsStore.settings.cappedEngineAnalysisDepth,
                unlimited: settingsStore.settings.isEngineAnalysisUncapped
            )
            engineAnalysis.refresh(game: game)
        }
        .onChange(of: game.moves.count) { _, _ in
            pgnArchive.syncActiveGame(from: game)
            if game.isGameOver {
                engineAnalysis.stop()
            } else {
                engineAnalysis.refresh(game: game)
            }
            openingService.refresh(game: game)
        }
        .onChange(of: game.activePlyIndex) { _, _ in
            if game.isGameOver {
                engineAnalysis.stop()
            } else {
                engineAnalysis.refresh(game: game)
            }
            openingService.refresh(game: game)
        }
        .onChange(of: game.gameResult) { _, _ in
            pgnArchive.syncActiveGame(from: game)
            if game.isGameOver {
                engineAnalysis.stop()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                settingsStore: settingsStore,
                vocabularyStore: vocabularyStore,
                developerModeStore: developerModeStore,
                pendingSpeechModelWork: $pendingSpeechModelWork
            )
        }
        .onChange(of: showingSettings) { wasShowing, isShowing in
            if isShowing {
                pendingSpeechModelWork.clear()
            } else if wasShowing {
                startDeferredSpeechModelRebuildIfNeeded()
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $showingTeachPhrase) {
            if let context = speechRecognizer.pendingFailure {
                TeachPhraseView(
                    language: speechRecognizer.currentLanguage,
                    context: context
                ) { phrase, move in
                    await speechRecognizer.learnPhrase(phrase, moveNotation: move)
                    _ = processMoveFromSpeech(move)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                speechRecognizer.refreshAuthorizationStatus()
            }
        }
        .alert(
            recordingPermissionAlertTitle(for: recordingPermissionIssue),
            isPresented: $showingRecordingPermissionAlert,
            presenting: recordingPermissionIssue
        ) { _ in
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(recordingPermissionMessage(for: issue))
        }
        .statusBar(hidden: developerModeStore.hidesStatusBar)
    }

    @ViewBuilder
    private func landscapeLayout(in geometry: GeometryProxy) -> some View {
        let boardColumnWidth = landscapeBoardColumnWidth(in: geometry)
        let boardAreaHeight = landscapeBoardAreaHeight(in: geometry)
        let sidebarWidth = max(0, geometry.size.width - boardColumnWidth - 1)

        HStack(alignment: .top, spacing: 0) {
            boardSection(compactOpening: true, boardAreaHeight: boardAreaHeight)
                .padding(8)
                .frame(width: boardColumnWidth, height: geometry.size.height, alignment: .topLeading)
                .clipped()

            Divider()

            VStack(spacing: 0) {
                controlToolbar(compact: false, availableWidth: sidebarWidth)
                ScrollView {
                    notationPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.trailing)
        }
    }

    private func landscapeBoardAreaHeight(in geometry: GeometryProxy) -> CGFloat {
        let openingHeight: CGFloat = settingsStore.settings.openingNameVisible ? 28 : 0
        let sectionSpacing: CGFloat = 6
        let statusHeight: CGFloat = 44
        let verticalPadding: CGFloat = 16
        let spacingCount: CGFloat = openingHeight > 0 ? 2 : 1

        return geometry.size.height
            - verticalPadding
            - openingHeight
            - statusHeight
            - sectionSpacing * spacingCount
    }

    private func landscapeBoardColumnWidth(in geometry: GeometryProxy) -> CGFloat {
        let showEvalBar = settingsStore.settings.engineAnalysisShowEvaluationBar
        let evalOverhead: CGFloat = showEvalBar ? 48 : 0
        let columnPadding: CGFloat = 16
        let boardAreaHeight = landscapeBoardAreaHeight(in: geometry)
        let boardSide = floor(max(0, boardAreaHeight) / 8) * 8

        return boardSide + evalOverhead + columnPadding
    }

    @ViewBuilder
    private func portraitLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            controlToolbar(compact: true, availableWidth: geometry.size.width)

            ScrollView {
                VStack(spacing: 16) {
                    boardSection()
                        .padding()

                    Divider()

                    notationPanel
                }
            }
        }
    }
    
    private func boardSection(
        compactOpening: Bool = false,
        boardAreaHeight: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: compactOpening ? 6 : 10) {
            OpeningNameView(
                display: openingService.display,
                isVisible: settingsStore.settings.openingNameVisible,
                isLoaded: openingService.isLoaded,
                hasMoves: !game.moves.isEmpty,
                compact: compactOpening
            )

            if let boardAreaHeight {
                boardLayout
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: max(0, boardAreaHeight), alignment: .topLeading)
            } else {
                boardLayout
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(game.currentTurn == .white ? Color.white : Color.black)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
                
                if !game.isAtLatestMove {
                    Button {
                        _ = game.goToLatestPosition()
                    } label: {
                        Text("Viewing move \(game.activePlyIndex) of \(game.moves.count) — tap to go to latest")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                    }
                    .buttonStyle(.plain)
                } else if pgnArchive.activeGameIsReviewOnly, let activeGame = pgnArchive.activeGame {
                    Text("Round \(activeGame.round) · \(activeGame.result.rawValue) — review only")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(game.gameStatusMessage ?? (game.currentTurn == .white ? "White to move" : "Black to move"))
                        .font(.subheadline)
                        .foregroundStyle(game.isGameOver ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                }
                
                Spacer(minLength: 0)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        boardOrientation.toggle()
                    }
                } label: {
                    Label("Turn board", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                        .imageScale(.medium)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Turn board")
                .layoutPriority(2)
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var boardLayout: some View {
        BoardWithEvaluationLayout(
            game: game,
            settings: settingsStore.settings,
            orientation: boardOrientation,
            chessEngine: chessEngine,
            engineAnalysis: engineAnalysis,
            showEvaluationBar: settingsStore.settings.engineAnalysisShowEvaluationBar,
            showBoardArrow: settingsStore.settings.engineAnalysisShowBoardArrow,
            engineAnalysisVisible: settingsStore.settings.engineAnalysisVisible,
            canAcceptNewMoves: canAcceptNewMoves
        )
    }
    
    private var notationPanel: some View {
        NotationPanelView(
            game: game,
            pgnArchive: pgnArchive,
            metadata: settingsStore.settings.pgnMetadata,
            hidePGNHeaderTags: settingsStore.settings.pgnHideHeaderTags,
            transcript: speechRecognizer.transcript,
            isRecording: speechRecognizer.isRecording,
            dictationPauseDeadline: speechRecognizer.dictationPauseDeadline,
            dictationPauseDuration: speechRecognizer.dictationPauseDuration,
            pendingFailure: speechRecognizer.pendingFailure,
            isRebuildingLanguageModel: speechRecognizer.isRebuildingLanguageModel,
            engineAnalysisVisible: settingsStore.settings.engineAnalysisVisible,
            engineAnalysisUseAlgebraicNotation: settingsStore.settings.engineAnalysisUseAlgebraicNotation,
            engineAnalysis: engineAnalysis,
            onTeachPhrase: { showingTeachPhrase = true },
            onDismissFailure: { speechRecognizer.clearPendingFailure() },
            onClearPGN: clearPGN,
            onActivateGame: activateGame,
            onDeleteGame: deleteGame
        )
    }
    
    private func controlToolbar(compact: Bool, availableWidth: CGFloat) -> some View {
        let isNarrowPortrait = compact && availableWidth < 420
        let isNarrowSidebar = !compact && availableWidth < 400
        let useIconOnlyRecord = isNarrowPortrait || isNarrowSidebar
        let iconHitSize: CGFloat = (isNarrowPortrait || isNarrowSidebar) ? 36 : (compact ? 40 : 44)
        let iconSpacing: CGFloat = compact ? (isNarrowPortrait ? 0 : 4) : (isNarrowSidebar ? 0 : 2)

        return HStack(spacing: iconSpacing) {
            if compact {
                Image("logo_sr")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                if !isNarrowPortrait {
                    Text("Chess Recorder")
                        .font(.headline)
                        .bold()
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: compact ? (isNarrowPortrait ? 0 : 4) : 0)
            
            Text(speechRecognizer.currentLanguage.flag)
                .font(.title3)
                .frame(width: iconHitSize, height: iconHitSize)
                .accessibilityLabel(speechRecognizer.currentLanguage.displayName)
            
            if useIconOnlyRecord {
                Button {
                    toggleRecording()
                } label: {
                    ToolbarIconLabel(
                        speechRecognizer.isRecording ? "mic.fill" : "mic",
                        hitSize: iconHitSize
                    )
                    .foregroundColor(speechRecognizer.isRecording ? .red : (canAcceptNewMoves ? .blue : .secondary))
                }
                .disabled(!speechRecognizer.isReadyForUse || !canAcceptNewMoves)
                .accessibilityLabel(speechRecognizer.isRecording ? "Stop recording" : "Record")
            } else {
                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                            .imageScale(.medium)
                        Text(speechRecognizer.isRecording ? "Stop" : "Record")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(speechRecognizer.isRecording ? .red : (canAcceptNewMoves ? .blue : .secondary))
                    .padding(.horizontal, compact ? 8 : 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(speechRecognizer.isRecording
                                ? Color.red.opacity(0.1)
                                : (canAcceptNewMoves ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1)))
                    )
                }
                .disabled(!speechRecognizer.isReadyForUse || !canAcceptNewMoves)
            }
            
            Button {
                navigateBack()
            } label: {
                ToolbarIconLabel("chevron.left", hitSize: iconHitSize)
            }
            .disabled(!game.canGoBack)
            .accessibilityLabel("Previous move")
            
            Button {
                navigateForward()
            } label: {
                ToolbarIconLabel("chevron.right", hitSize: iconHitSize)
            }
            .disabled(!game.canGoForward)
            .accessibilityLabel("Next move")
            
            Button {
                undoLastMove()
            } label: {
                ToolbarIconLabel("arrow.uturn.backward", hitSize: iconHitSize)
            }
            .disabled(!game.canUndo || pgnArchive.activeGameIsReviewOnly)
            
            Menu {
                Button("New Game") {
                    startNewGame(result: .ongoing)
                }
                Divider()
                Button("1-0") {
                    startNewGame(result: .whiteWins)
                }
                Button("0-1") {
                    startNewGame(result: .blackWins)
                }
                Button("1/2-1/2") {
                    startNewGame(result: .draw)
                }
            } label: {
                ToolbarIconLabel("ellipsis.circle", hitSize: iconHitSize)
            }
            
            Button {
                showingSettings = true
            } label: {
                ToolbarIconLabel("gearshape", hitSize: iconHitSize)
            }
            .accessibilityLabel("Settings")

            Button {
                showingHelp = true
            } label: {
                ToolbarIconLabel("questionmark.circle", hitSize: iconHitSize)
            }
            .accessibilityLabel("About & Help")
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 52 : 56)
        .padding(.horizontal, compact ? (isNarrowPortrait ? 6 : 12) : (isNarrowSidebar ? 6 : 8))
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    @MainActor
    private func startDeferredSpeechModelRebuildIfNeeded() {
        guard pendingSpeechModelWork.needsWork else { return }
        showSpeechModelRebuildOverlay = true
        speechRecognizer.beginLanguageModelRebuild()
        Task { await applyDeferredSpeechModelWork() }
    }

    @MainActor
    private func applyDeferredSpeechModelWork() async {
        guard let action = pendingSpeechModelWork.action else {
            showSpeechModelRebuildOverlay = false
            speechRecognizer.endLanguageModelRebuild()
            return
        }
        pendingSpeechModelWork.clear()

        defer {
            showSpeechModelRebuildOverlay = false
        }

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(150))

        switch action {
        case .changeLanguage(let language):
            await speechRecognizer.changeLanguage(language)
        case .reloadVocabulary(let language):
            await speechRecognizer.reloadLanguageModel(for: language)
        }
    }
    
    private func setupSpeechRecognizer() {
        speechRecognizer.onMoveCandidatesDetected = { candidates in
            self.processVoiceMoveCandidates(candidates)
        }

        speechRecognizer.onMoveDetected = { moveNotation in
            self.processMoveFromSpeech(moveNotation)
        }
        
        speechRecognizer.onUndoDetected = {
            guard self.game.canUndo, !self.pgnArchive.activeGameIsReviewOnly else { return }
            self.undoLastMove()
        }
    }
    
    private func toggleRecording() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
            return
        }

        Task { @MainActor in
            if let issue = await speechRecognizer.ensureRecordingPermissions() {
                recordingPermissionIssue = issue
                showingRecordingPermissionAlert = true
                return
            }

            do {
                try speechRecognizer.startRecording()
            } catch {
                print("SpeechRecognizer: failed to start recording from UI — \(error.localizedDescription)")
            }
        }
    }

    private func recordingPermissionAlertTitle(for issue: RecordingPermissionIssue?) -> String {
        switch issue {
        case .microphoneDenied:
            return "Microphone Access Required"
        case .speechDenied:
            return "Speech Recognition Required"
        case .none:
            return "Permission Required"
        }
    }

    private func recordingPermissionMessage(for issue: RecordingPermissionIssue) -> String {
        switch issue {
        case .microphoneDenied:
            return "Chess Recorder needs microphone access to hear your moves. Open Settings, tap Chess Recorder, and turn on Microphone."
        case .speechDenied:
            return "Chess Recorder needs speech recognition to understand your moves. Open Settings, tap Chess Recorder, and turn on Speech Recognition."
        }
    }
    
    @discardableResult
    private func processVoiceMoveCandidates(_ candidates: [String]) -> Bool {
        guard canAcceptNewMoves else { return false }
        print("Processing move candidates: \(candidates.joined(separator: ", "))")
        guard chessEngine.executeVoiceCandidates(candidates) else {
            print("Could not find valid move for \(candidates.joined(separator: ", "))")
            return false
        }
        return true
    }

    @discardableResult
    private func processMoveFromSpeech(_ notation: String) -> Bool {
        guard canAcceptNewMoves else { return false }
        print("Processing move: \(notation)")
        guard chessEngine.executeMove(notation: notation) else {
            print("Could not find valid move for \(notation)")
            return false
        }
        return true
    }
    
    private func startNewGame(result: PGNResult) {
        let archiveResult = result == .ongoing ? game.gameResult : result
        pgnArchive.finalizeActiveGame(with: archiveResult, from: game)
        game.resetGame()
        speechRecognizer.transcript = ""
    }
    
    private func clearPGN() {
        pgnArchive.resetAll()
        game.resetGame()
        speechRecognizer.transcript = ""
    }

    private func activateGame(id: UUID) {
        guard pgnArchive.activeGameID != id else { return }

        pgnArchive.syncActiveGame(from: game)
        guard let recordedGame = pgnArchive.games.first(where: { $0.id == id }) else { return }

        pgnArchive.setActiveGame(id: id)
        _ = game.loadMainLine(moves: recordedGame.moves)

        if speechRecognizer.isRecording, pgnArchive.activeGameIsReviewOnly {
            speechRecognizer.stopRecording()
        }
    }

    private func deleteGame(id: UUID) {
        pgnArchive.syncActiveGame(from: game)
        let nextActiveID = pgnArchive.removeGame(id: id)

        if let nextActiveID,
           let recordedGame = pgnArchive.games.first(where: { $0.id == nextActiveID }) {
            _ = game.loadMainLine(moves: recordedGame.moves)
        } else {
            game.resetGame()
        }

        if speechRecognizer.isRecording, pgnArchive.activeGameIsReviewOnly {
            speechRecognizer.stopRecording()
        }
    }
    
    private func undoLastMove() {
        if game.undoLastMove() {
            print("Undid last move")
        } else {
            print("No moves to undo")
        }
    }

    private func navigateBack() {
        guard game.goToPreviousPosition() else { return }
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
        }
    }

    private func navigateForward() {
        _ = game.goToNextPosition()
    }
}

private struct ToolbarIconLabel: View {
    let systemName: String
    var hitSize: CGFloat = 44

    init(_ systemName: String, hitSize: CGFloat = 44) {
        self.systemName = systemName
        self.hitSize = hitSize
    }

    var body: some View {
        Image(systemName: systemName)
            .imageScale(.medium)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
    }
}

private struct BoardWithEvaluationLayout: View {
    let game: ChessGame
    let settings: AppSettings
    let orientation: BoardOrientation
    let chessEngine: ChessEngine
    let engineAnalysis: EngineAnalysisService
    let showEvaluationBar: Bool
    let showBoardArrow: Bool
    let engineAnalysisVisible: Bool
    let canAcceptNewMoves: Bool

    var body: some View {
        BoardEvalRowLayout(showEvaluationBar: showEvaluationBar) {
            ChessBoardView(
                game: game,
                settings: settings,
                orientation: orientation,
                touchInputEnabled: settings.touchInputEnabled && canAcceptNewMoves,
                analysisArrow: showBoardArrow ? engineAnalysis.display.nextMoveArrow : nil,
                chessEngine: chessEngine
            )

            if showEvaluationBar {
                EvaluationBarView(
                    whiteFraction: engineAnalysis.display.evaluationBarWhiteFraction,
                    orientation: orientation,
                    evaluationText: engineAnalysis.display.evaluationText,
                    isEngineActive: engineAnalysisVisible && engineAnalysis.isActive,
                    isEngineReady: engineAnalysis.isEngineReady
                )
            }
        }
    }
}

private struct BoardEvalRowLayout: Layout {
    let showEvaluationBar: Bool

    private let evalBarWidth: CGFloat = 38
    private let spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        let availableHeight = proposal.height ?? .infinity
        let boardSide = boardSideLength(
            availableWidth: availableWidth,
            availableHeight: availableHeight
        )
        let horizontalOverhead = showEvaluationBar ? evalBarWidth + spacing : 0
        let contentWidth = boardSide + horizontalOverhead
        let width = proposal.width.map { min($0, contentWidth) } ?? contentWidth
        return CGSize(width: width, height: max(boardSide, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let boardSide = boardSideLength(
            availableWidth: bounds.width,
            availableHeight: bounds.height
        )
        guard boardSide > 0, !subviews.isEmpty else { return }

        let boardSize = ProposedViewSize(width: boardSide, height: boardSide)
        subviews[0].place(
            at: CGPoint(x: bounds.minX + boardSide / 2, y: bounds.minY + boardSide / 2),
            anchor: .center,
            proposal: boardSize
        )

        guard showEvaluationBar, subviews.count > 1 else { return }

        let barSize = ProposedViewSize(width: evalBarWidth, height: boardSide)
        subviews[1].place(
            at: CGPoint(
                x: bounds.minX + boardSide + spacing + evalBarWidth / 2,
                y: bounds.minY + boardSide / 2
            ),
            anchor: .center,
            proposal: barSize
        )
    }

    private func boardSideLength(availableWidth: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let horizontalOverhead = showEvaluationBar ? evalBarWidth + spacing : 0
        return floor(
            min(max(0, availableWidth - horizontalOverhead), availableHeight) / 8
        ) * 8
    }
}

#Preview {
    ContentView(
        settingsStore: SettingsStore(),
        vocabularyStore: PersonalVocabularyStore(),
        developerModeStore: DeveloperModeStore()
    )
}
