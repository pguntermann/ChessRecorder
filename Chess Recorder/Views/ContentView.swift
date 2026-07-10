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
    
    var body: some View {
        @Bindable var speechRecognizer = speechRecognizer

        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                HStack(spacing: 0) {
                    boardSection
                        .frame(width: geometry.size.height * 0.9)
                        .padding()
                    
                    Divider()
                    
                    VStack(spacing: 0) {
                        controlToolbar(compact: false)
                        notationPanel
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    controlToolbar(compact: true)
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            boardSection
                                .padding()
                            
                            Divider()
                            
                            notationPanel
                        }
                    }
                }
            }
        }
        .overlay {
            if !isAppReady {
                InitializationOverlay(
                    phase: speechRecognizer.initializationPhase,
                    context: .startup
                )
                .transition(.opacity)
            } else if showSpeechModelRebuildOverlay || speechRecognizer.isRebuildingLanguageModel {
                InitializationOverlay(
                    phase: speechRecognizer.initializationPhase,
                    context: .speechModelRebuild
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isAppReady)
        .task {
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
            if game.isGameOver {
                engineAnalysis.stop()
            } else {
                engineAnalysis.refresh(game: game)
            }
            openingService.refresh(game: game)
        }
        .onChange(of: game.gameResult) { _, _ in
            pgnArchive.syncCurrentGameResult(with: game)
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
    
    private var boardSection: some View {
        VStack(spacing: 10) {
            OpeningNameView(
                display: openingService.display,
                isVisible: settingsStore.settings.openingNameVisible,
                isLoaded: openingService.isLoaded,
                hasMoves: !game.moves.isEmpty
            )

            BoardWithEvaluationLayout(
                game: game,
                settings: settingsStore.settings,
                orientation: boardOrientation,
                chessEngine: chessEngine,
                engineAnalysis: engineAnalysis,
                showEvaluationBar: settingsStore.settings.engineAnalysisShowEvaluationBar,
                showBoardArrow: settingsStore.settings.engineAnalysisShowBoardArrow,
                engineAnalysisVisible: settingsStore.settings.engineAnalysisVisible
            )

            HStack(spacing: 8) {
                Circle()
                    .fill(game.currentTurn == .white ? Color.white : Color.black)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
                
                Text(game.gameStatusMessage ?? (game.currentTurn == .white ? "White to move" : "Black to move"))
                    .font(.subheadline)
                    .foregroundStyle(game.isGameOver ? .primary : .secondary)
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        boardOrientation.toggle()
                    }
                } label: {
                    Label("Turn board", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                        .imageScale(.medium)
                }
                .accessibilityLabel("Turn board")
            }
        }
    }
    
    private var notationPanel: some View {
        NotationPanelView(
            game: game,
            pgnNotation: pgnArchive.displayText(currentGame: game, metadata: settingsStore.settings.pgnMetadata),
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
            onClearPGN: clearPGN
        )
    }
    
    private func controlToolbar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact {
                Image("logo_sr")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text("Chess Recorder")
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
            } else {
                Image("logo_sr")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Chess Recorder")
            }
            
            Spacer(minLength: 4)
            
            Text(speechRecognizer.currentLanguage.flag)
                .font(.title3)
                .accessibilityLabel(speechRecognizer.currentLanguage.displayName)
            
            Button {
                toggleRecording()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                    Text(speechRecognizer.isRecording ? "Stop" : "Record")
                        .font(.subheadline)
                }
                .frame(minWidth: 76)
                .foregroundColor(speechRecognizer.isRecording ? .red : .blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(speechRecognizer.isRecording ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                )
            }
            .disabled(!speechRecognizer.isReadyForUse)
            
            Button {
                undoLastMove()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .imageScale(.medium)
            }
            .disabled(!game.canUndo)
            
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
                Label("Game", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .imageScale(.medium)
            }
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
            }
            .accessibilityLabel("Settings")

            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .imageScale(.medium)
            }
            .accessibilityLabel("About & Help")
        }
        .frame(height: 50)
        .padding(.horizontal, 12)
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
            guard self.game.canUndo else { return }
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
                print("Failed to start recording: \(error)")
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
        print("Processing move candidates: \(candidates.joined(separator: ", "))")
        guard chessEngine.executeVoiceCandidates(candidates) else {
            print("Could not find valid move for \(candidates.joined(separator: ", "))")
            return false
        }
        return true
    }

    @discardableResult
    private func processMoveFromSpeech(_ notation: String) -> Bool {
        print("Processing move: \(notation)")
        guard chessEngine.executeMove(notation: notation) else {
            print("Could not find valid move for \(notation)")
            return false
        }
        return true
    }
    
    private func startNewGame(result: PGNResult) {
        let archiveResult = result == .ongoing ? game.gameResult : result
        pgnArchive.finalizeCurrentGame(game, result: archiveResult)
        game.resetGame()
        speechRecognizer.transcript = ""
    }
    
    private func clearPGN() {
        pgnArchive.resetAll()
        game.resetGame()
        speechRecognizer.transcript = ""
    }
    
    private func undoLastMove() {
        if game.undoLastMove() {
            print("Undid last move")
        } else {
            print("No moves to undo")
        }
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

    var body: some View {
        BoardEvalRowLayout(showEvaluationBar: showEvaluationBar) {
            ChessBoardView(
                game: game,
                settings: settings,
                orientation: orientation,
                touchInputEnabled: settings.touchInputEnabled,
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
        guard let width = proposal.width else { return .zero }
        let boardSide = boardSideLength(
            availableWidth: width,
            availableHeight: proposal.height ?? .infinity
        )
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
