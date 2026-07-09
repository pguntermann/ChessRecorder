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
    
    init(settingsStore: SettingsStore, vocabularyStore: PersonalVocabularyStore) {
        self.settingsStore = settingsStore
        self.vocabularyStore = vocabularyStore
        _speechRecognizer = State(initialValue: SpeechRecognizer(vocabularyStore: vocabularyStore))
    }
    
    private var chessEngine: ChessEngine {
        ChessEngine(game: game)
    }
    
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                HStack(spacing: 0) {
                    boardSection
                        .frame(width: geometry.size.height * 0.9)
                        .padding()
                    
                    Divider()
                    
                    VStack(spacing: 0) {
                        controlToolbar
                        notationPanel
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    controlToolbar
                    
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
            if speechRecognizer.isInitializing {
                InitializationOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: speechRecognizer.isInitializing)
        .task {
            setupSpeechRecognizer()
            speechRecognizer.dictationPauseSeconds = settingsStore.settings.dictationPauseSeconds
            engineAnalysis.configure(
                depth: settingsStore.settings.cappedEngineAnalysisDepth,
                unlimited: settingsStore.settings.isEngineAnalysisUncapped
            )
            await speechRecognizer.startup(with: settingsStore.settings.defaultRecognitionLanguage)
            await engineAnalysis.prepare()
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
            engineAnalysis.refresh(game: game)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                settingsStore: settingsStore,
                vocabularyStore: vocabularyStore,
                onLanguageChanged: { language in
                    Task { await speechRecognizer.setLanguage(language) }
                },
                onVocabularyChanged: { language in
                    Task { await speechRecognizer.reloadLanguageModel(for: language) }
                }
            )
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
    }
    
    private var boardSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ChessBoardView(
                    game: game,
                    settings: settingsStore.settings,
                    orientation: boardOrientation,
                    touchInputEnabled: settingsStore.settings.touchInputEnabled,
                    analysisArrow: settingsStore.settings.engineAnalysisShowBoardArrow
                        ? engineAnalysis.display.nextMoveArrow
                        : nil,
                    chessEngine: chessEngine
                )

                if settingsStore.settings.engineAnalysisShowEvaluationBar {
                    EvaluationBarView(
                        whiteFraction: engineAnalysis.display.evaluationBarWhiteFraction,
                        orientation: boardOrientation,
                        evaluationText: engineAnalysis.display.evaluationText,
                        isEngineActive: settingsStore.settings.engineAnalysisVisible && engineAnalysis.isActive,
                        isEngineReady: engineAnalysis.isEngineReady
                    )
                }
            }
            
            HStack(spacing: 8) {
                Circle()
                    .fill(game.currentTurn == .white ? Color.white : Color.black)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
                
                Text(game.currentTurn == .white ? "White to move" : "Black to move")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
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
    
    private var controlToolbar: some View {
        HStack(spacing: 8) {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text("Chess Recorder")
                .font(.title2)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
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
            .accessibilityLabel("Help")
        }
        .frame(height: 50)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    private func setupSpeechRecognizer() {
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
    private func processMoveFromSpeech(_ notation: String) -> Bool {
        print("Processing move: \(notation)")
        guard chessEngine.executeMove(notation: notation) else {
            print("Could not find valid move for \(notation)")
            return false
        }
        return true
    }
    
    private func startNewGame(result: PGNResult) {
        pgnArchive.finalizeCurrentGame(game, result: result)
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

private struct InitializationOverlay: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .opacity(0.94)
            
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                
                Text("Preparing speech recognition…")
                    .font(.headline)
                
                Text("Loading chess vocabulary for voice input")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Initializing speech recognition")
    }
}

#Preview {
    ContentView(settingsStore: SettingsStore(), vocabularyStore: PersonalVocabularyStore())
}
