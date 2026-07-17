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
    let sessionStore: SessionStore
    @State private var game = ChessGame()
    @State private var pgnArchive = PGNArchive()
    @State private var speechRecognizer: SpeechRecognizer
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var showingOpeningBook = false
    @State private var showingTeachPhrase = false
    @State private var showingAddCorrection = false
    @State private var showingRecordingPermissionAlert = false
    @State private var recordingPermissionIssue: RecordingPermissionIssue?
    @State private var boardOrientation: BoardOrientation = .whiteAtBottom
    @State private var engineAnalysis = EngineAnalysisService()
    @State private var moveAssessment = MoveAssessmentService()
    @State private var openingService = OpeningService()
    @State private var isAppReady = false
    @State private var startupIncludesSessionRestore = false
    @State private var pendingSpeechModelWork = PendingSpeechModelWork()
    @State private var showSpeechModelRebuildOverlay = false
    @State private var isApplyingArchiveSelection = false
    @State private var gameSwitchSlideOffset: CGFloat = 0
    @State private var isGameSwitchAnimating = false
    @State private var gameSwitchContainerWidth: CGFloat = 0
    /// Defers archive/PGN work until piece animation finishes so notation rebuilds don't stutter the tween.
    @State private var deferredArchiveWorkTask: Task<Void, Never>?
    
    init(
        settingsStore: SettingsStore,
        vocabularyStore: PersonalVocabularyStore,
        developerModeStore: DeveloperModeStore,
        sessionStore: SessionStore
    ) {
        self.settingsStore = settingsStore
        self.vocabularyStore = vocabularyStore
        self.developerModeStore = developerModeStore
        self.sessionStore = sessionStore
        _speechRecognizer = State(initialValue: SpeechRecognizer(vocabularyStore: vocabularyStore))
    }
    
    private var chessEngine: ChessEngine {
        ChessEngine(game: game)
    }

    private var canAcceptNewMoves: Bool {
        game.isAtLatestMove && !game.isGameOver && !pgnArchive.activeGameIsReviewOnly
    }

    private var recordButtonEnabled: Bool {
        speechRecognizer.isReadyForUse && (speechRecognizer.isRecording || canAcceptNewMoves)
    }

    private var recordButtonLooksActive: Bool {
        speechRecognizer.isRecording || recordButtonEnabled
    }

    private var recordButtonForegroundColor: Color {
        if speechRecognizer.isRecording {
            return .red
        }
        return recordButtonLooksActive ? .blue : .secondary
    }

    private var recordButtonBackgroundColor: Color {
        if speechRecognizer.isRecording {
            return Color.red.opacity(0.1)
        }
        return recordButtonLooksActive ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1)
    }
    
    var body: some View {
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
                    context: .startup(includesSessionRestore: startupIncludesSessionRestore),
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
            startupIncludesSessionRestore = sessionStore.hasStoredSession

            // Allow the initialization overlay to render before startup work blocks the main actor.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(50))

            setupSpeechRecognizer()
            speechRecognizer.dictationPauseSeconds = settingsStore.settings.dictationPauseSeconds
            engineAnalysis.configure(
                depth: settingsStore.settings.cappedEngineAnalysisDepth,
                unlimited: settingsStore.settings.isEngineAnalysisUncapped
            )
            moveAssessment.configure(
                depth: settingsStore.settings.cappedMoveAssessmentDepth,
                enabled: settingsStore.settings.moveAssessmentEnabled,
                openingService: openingService
            )
            moveAssessment.onAssessmentApplied = {
                scheduleSessionPersist()
            }
            await speechRecognizer.startup(with: settingsStore.settings.defaultRecognitionLanguage)
            speechRecognizer.setInitializationPhase(.preparingEngine)
            async let enginePrepare: Void = engineAnalysis.prepare()
            async let assessmentPrepare: Void = moveAssessment.prepare()
            _ = await (enginePrepare, assessmentPrepare)
            speechRecognizer.setInitializationPhase(.loadingOpenings)
            await openingService.prepare()

            if startupIncludesSessionRestore {
                speechRecognizer.setInitializationPhase(.restoringSession)
                restorePersistedSessionIfAvailable()
            }

            openingService.refresh(game: game)
            moveAssessment.enqueueUnassessedMoves(in: pgnArchive)
            isAppReady = true
        }
        .onDisappear {
            Task {
                await engineAnalysis.shutdown()
                await moveAssessment.shutdown()
            }
        }
        .onChange(of: settingsStore.settings.dictationPauseSeconds) { _, newValue in
            speechRecognizer.dictationPauseSeconds = newValue
        }
        .onChange(of: developerModeStore.isSpeechPipelineTracingEnabled) { _, enabled in
            speechRecognizer.isSpeechPipelineTracingEnabled =
                DeveloperModeStore.isAvailable && enabled
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
        .onChange(of: settingsStore.settings.moveAssessmentEnabled) { _, _ in
            moveAssessment.configure(
                depth: settingsStore.settings.cappedMoveAssessmentDepth,
                enabled: settingsStore.settings.moveAssessmentEnabled,
                openingService: openingService
            )
        }
        .onChange(of: settingsStore.settings.moveAssessmentDepth) { _, _ in
            moveAssessment.configure(
                depth: settingsStore.settings.cappedMoveAssessmentDepth,
                enabled: settingsStore.settings.moveAssessmentEnabled,
                openingService: openingService
            )
        }
        .onChange(of: game.moves.count) { oldCount, newCount in
            openingService.refresh(game: game)

            let isForwardMove = newCount > oldCount && !isApplyingArchiveSelection
            let isTakeback = newCount < oldCount && !isApplyingArchiveSelection
            let animationDuration = settingsStore.settings.moveAnimationDuration

            if isTakeback {
                deferredArchiveWorkTask?.cancel()
                deferredArchiveWorkTask = nil
                moveAssessment.cancelJobs(for: pgnArchive.activeGameID, fromMoveIndex: newCount)
                syncLiveBoardToArchiveIfRecording()
                scheduleSessionPersist()
            } else if isForwardMove, animationDuration > 0 {
                // Keep archive/notation idle during the piece tween; multi-game PGN rebuilds are heavy.
                deferredArchiveWorkTask?.cancel()
                deferredArchiveWorkTask = Task { @MainActor in
                    let nanoseconds = UInt64(animationDuration * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    syncLiveBoardToArchiveIfRecording()
                    scheduleSessionPersist()
                    enqueueMoveAssessmentForLatestMove()
                }
            } else {
                deferredArchiveWorkTask?.cancel()
                deferredArchiveWorkTask = nil
                syncLiveBoardToArchiveIfRecording()
                scheduleSessionPersist()
                if isForwardMove {
                    enqueueMoveAssessmentForLatestMove()
                }
            }

            if game.isGameOver {
                deferredArchiveWorkTask?.cancel()
                deferredArchiveWorkTask = nil
                syncLiveBoardToArchiveIfRecording()
                scheduleSessionPersist()
                engineAnalysis.stop()
                stopRecordingIfNeeded()
            } else {
                refreshEngineIfAppropriate()
            }
        }
        .onChange(of: game.activePlyIndex) { _, _ in
            refreshEngineIfAppropriate()
            openingService.refresh(game: game)
        }
        .onChange(of: game.gameResult) { _, _ in
            syncLiveBoardToArchiveIfRecording()
            scheduleSessionPersist()
            if game.isGameOver {
                engineAnalysis.stop()
                stopRecordingIfNeeded()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                settingsStore: settingsStore,
                vocabularyStore: vocabularyStore,
                developerModeStore: developerModeStore,
                speechRecognizer: speechRecognizer,
                pendingSpeechModelWork: $pendingSpeechModelWork,
                onStopRecording: {
                    speechRecognizer.stopRecording()
                },
                onPurgeMoveAssessments: {
                    purgeMoveAssessmentsAndReanalyze()
                },
                onImportPGN: { pgn in
                    try importPGNGames(from: pgn)
                }
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
        .sheet(isPresented: $showingOpeningBook) {
            OpeningBookSheet(
                rootDisplay: openingService.display,
                rootFEN: openingService.currentBookFEN,
                isInBook: openingService.isInBook,
                pathToCurrent: openingService.pathToCurrent,
                miniBoardSide: settingsStore.settings.cappedOpeningBookMiniBoardSide,
                boardOrientation: settingsStore.settings.openingBookMiniBoardFollowsOrientation
                    ? boardOrientation
                    : .whiteAtBottom,
                moveHighlightColor: settingsStore.settings.lastMoveArrowColor.color,
                openingService: openingService
            )
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
        .sheet(isPresented: $showingAddCorrection) {
            if let context = speechRecognizer.pendingFailure {
                TeachCorrectionView(
                    language: speechRecognizer.currentLanguage,
                    initialHeard: context.transcript
                ) { heard, replacement in
                    Task {
                        await speechRecognizer.learnCorrection(heard: heard, replacement: replacement)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                speechRecognizer.refreshAuthorizationStatus()
            } else if newPhase == .background || newPhase == .inactive {
                deferredArchiveWorkTask?.cancel()
                deferredArchiveWorkTask = nil
                flushSessionToDisk()
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
            boardSection(
                compactOpening: true,
                boardAreaHeight: boardAreaHeight,
                availableWidth: boardColumnWidth - 16,
                iconHitSize: ToolbarMetrics.iconHitSize(
                    compact: false,
                    availableWidth: boardColumnWidth - 16
                )
            )
                .padding(8)
                .frame(width: boardColumnWidth, height: geometry.size.height, alignment: .topLeading)
                .clipped()

            Divider()

            VStack(spacing: 0) {
                controlToolbar(compact: false, availableWidth: sidebarWidth)
                ScrollView {
                    notationSidebar
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
        let columnPadding: CGFloat = 16
        let boardAreaHeight = landscapeBoardAreaHeight(in: geometry)
        let footprint = BoardLayoutMetrics.computedFootprint(
            availableWidth: .infinity,
            maxBoardHeight: boardAreaHeight,
            showEvaluationBar: showEvalBar,
            boardSizePercent: settingsStore.settings.boardSizePercent,
            showCoordinates: settingsStore.settings.showCoordinates,
            coordinatesOutsideBoard: settingsStore.settings.coordinatesOutsideBoard,
            coordinateFontSize: settingsStore.settings.coordinateFontSize
        )

        return footprint.widthIncludingEvalBar(showEvalBar) + columnPadding
    }

    @ViewBuilder
    private func portraitLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            controlToolbar(compact: true, availableWidth: geometry.size.width)

            ScrollView {
                VStack(spacing: 16) {
                    boardSection(
                        availableWidth: geometry.size.width - 32,
                        iconHitSize: ToolbarMetrics.iconHitSize(
                            compact: true,
                            availableWidth: geometry.size.width
                        )
                    )
                        .padding()

                    Divider()

                    notationSidebar
                }
            }
        }
    }
    
    private func boardSection(
        compactOpening: Bool = false,
        boardAreaHeight: CGFloat? = nil,
        availableWidth: CGFloat,
        iconHitSize: CGFloat
    ) -> some View {
        let settings = settingsStore.settings
        let footprint = BoardLayoutMetrics.computedFootprint(
            availableWidth: availableWidth,
            maxBoardHeight: boardAreaHeight,
            showEvaluationBar: settings.engineAnalysisShowEvaluationBar,
            boardSizePercent: settings.boardSizePercent,
            showCoordinates: settings.showCoordinates,
            coordinatesOutsideBoard: settings.coordinatesOutsideBoard,
            coordinateFontSize: settings.coordinateFontSize
        )
        let boardDimensions = BoardLayoutMetrics.Dimensions(boardSide: footprint.boardSide)

        return GameSwitchSlideContainer(
            offset: $gameSwitchSlideOffset,
            measuredWidth: $gameSwitchContainerWidth
        ) {
            VStack(alignment: .leading, spacing: compactOpening ? 6 : 10) {
                OpeningNameView(
                    display: openingService.display,
                    isVisible: settings.openingNameVisible,
                    isLoaded: openingService.isLoaded,
                    isInBook: openingService.isInBook,
                    compact: compactOpening,
                    onTap: openingService.isLoaded ? { showingOpeningBook = true } : nil
                )

                boardLayout(boardSide: boardDimensions.side)
                    .frame(maxWidth: .infinity)
                    .frame(height: footprint.totalHeight)

                MoveNavigationBar(
                    game: game,
                    moveQualities: activeMoveQualities,
                    showMoveAssessments: settingsStore.settings.moveAssessmentEnabled,
                    assessmentColors: settingsStore.settings.moveAssessmentColors,
                    iconHitSize: iconHitSize,
                    onGoToFirst: navigateToFirst,
                    onGoToPrevious: navigateBack,
                    onGoToNext: navigateForward,
                    onGoToLatest: navigateToLatest,
                    onGoToPly: navigateToPly,
                    onFlipBoard: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            boardOrientation.toggle()
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(!isGameSwitchAnimating)
        .onAppear {
            if availableWidth > 0 {
                gameSwitchContainerWidth = availableWidth
            }
        }
        .onChange(of: availableWidth) { _, width in
            if width > 0 {
                gameSwitchContainerWidth = width
            }
        }
    }

    private func boardLayout(boardSide: CGFloat) -> some View {
        BoardWithEvaluationLayout(
            game: game,
            settings: settingsStore.settings,
            orientation: boardOrientation,
            chessEngine: chessEngine,
            engineAnalysis: engineAnalysis,
            showEvaluationBar: settingsStore.settings.engineAnalysisShowEvaluationBar,
            showBoardArrow: settingsStore.settings.engineAnalysisShowBoardArrow,
            engineAnalysisVisible: settingsStore.settings.engineAnalysisVisible,
            canAcceptNewMoves: canAcceptNewMoves,
            boardSide: boardSide
        )
    }
    
    private var notationSidebar: some View {
        VStack(spacing: 16) {
            LiveTranscriptSection(
                speechRecognizer: speechRecognizer,
                onTeachPhrase: { showingTeachPhrase = true },
                onAddCorrection: { showingAddCorrection = true }
            )

            NotationPanelView(
                game: game,
                pgnArchive: pgnArchive,
                defaultMetadata: settingsStore.settings.pgnMetadata,
                hidePGNHeaderTags: settingsStore.settings.pgnHideHeaderTags,
                includeMoveAssessmentSymbolsInExport: settingsStore.settings.pgnIncludeMoveAssessmentSymbols,
                showAccuracySummary: settingsStore.settings.pgnShowAccuracySummary,
                activeAssessment: moveAssessment.activeAssessment,
                showMoveAssessments: settingsStore.settings.moveAssessmentEnabled,
                assessmentColors: settingsStore.settings.moveAssessmentColors,
                assessmentColorsCacheKey: settingsStore.settings.moveAssessmentColorsCacheKey,
                engineAnalysisVisible: settingsStore.settings.engineAnalysisVisible,
                engineAnalysisUseAlgebraicNotation: settingsStore.settings.engineAnalysisUseAlgebraicNotation,
                engineAnalysis: engineAnalysis,
                onClearPGN: clearPGN,
                onActivateGame: activateGame,
                onDeleteGame: deleteGame
            )
        }
    }

    private func refreshEngineIfAppropriate() {
        guard settingsStore.settings.engineAnalysisVisible else { return }
        engineAnalysis.refresh(game: game)
    }

    private func enqueueMoveAssessmentForLatestMove() {
        guard settingsStore.settings.moveAssessmentEnabled,
              moveAssessment.isEngineReady,
              let gameID = pgnArchive.activeGameID,
              !pgnArchive.activeGameIsReviewOnly,
              !game.moves.isEmpty else {
            return
        }

        let moveIndex = game.moves.count - 1
        let playedMove = game.moves[moveIndex]

        // Game switches reload the board and bump moves.count; skip moves already assessed in the archive.
        if let archivedMoves = pgnArchive.games.first(where: { $0.id == gameID })?.moves,
           moveIndex < archivedMoves.count,
           archivedMoves[moveIndex].matchesPositionally(playedMove),
           archivedMoves[moveIndex].quality != nil {
            return
        }

        let fenSequence = game.fenSequenceFromStart()
        guard moveIndex + 1 < fenSequence.count else { return }

        let job = MoveAssessmentJob(
            gameID: gameID,
            moveIndex: moveIndex,
            fenBeforeMove: fenSequence[moveIndex],
            fenAfterMove: fenSequence[moveIndex + 1],
            playedMoveSAN: playedMove.san
        )
        moveAssessment.enqueue(job, archive: pgnArchive)
    }

    private func purgeMoveAssessmentsAndReanalyze() {
        moveAssessment.cancelAll()
        _ = pgnArchive.clearAllMoveAssessments()
        scheduleSessionPersist()
        moveAssessment.enqueueUnassessedMoves(in: pgnArchive)
    }

    @discardableResult
    private func importPGNGames(from pgn: String) throws -> Int {
        let imported = try PGNImportService.importGames(from: pgn)
        let ids = pgnArchive.appendImportedGames(imported)
        scheduleSessionPersist()
        moveAssessment.enqueueUnassessedMoves(in: pgnArchive)
        return ids.count
    }
    
    private func controlToolbar(compact: Bool, availableWidth: CGFloat) -> some View {
        let isNarrowPortrait = compact && availableWidth < 500
        let isNarrowSidebar = !compact && availableWidth < 400
        let useIconOnlyRecord = isNarrowSidebar
        let iconHitSize = ToolbarMetrics.iconHitSize(compact: compact, availableWidth: availableWidth)
        let iconSpacing: CGFloat = compact ? 4 : (isNarrowSidebar ? 0 : 2)
        let recordButtonWidth: CGFloat = 82

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
                    .foregroundColor(recordButtonForegroundColor)
                }
                .disabled(!recordButtonEnabled)
                .accessibilityLabel(speechRecognizer.isRecording ? "Stop recording" : "Record")
            } else {
                Button {
                    toggleRecording()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                            .imageScale(.medium)
                            .frame(width: 20)
                        Text(speechRecognizer.isRecording ? "Stop" : "Record")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: recordButtonWidth)
                    .foregroundColor(recordButtonForegroundColor)
                    .padding(.horizontal, compact ? 8 : 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(recordButtonBackgroundColor)
                    )
                }
                .layoutPriority(1)
                .disabled(!recordButtonEnabled)
            }
            
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
                    endGame(with: .whiteWins)
                }
                .disabled(game.isGameOver)
                Button("0-1") {
                    endGame(with: .blackWins)
                }
                .disabled(game.isGameOver)
                Button("1/2-1/2") {
                    endGame(with: .draw)
                }
                .disabled(game.isGameOver)
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
        speechRecognizer.isSpeechPipelineTracingEnabled =
            DeveloperModeStore.isAvailable && developerModeStore.isSpeechPipelineTracingEnabled
        speechRecognizer.onMoveCandidatesDetected = { candidates, preferCaptures in
            self.processVoiceMoveCandidates(candidates, preferCaptures: preferCaptures)
        }
        speechRecognizer.canAcceptVoiceMoves = {
            self.canAcceptNewMoves
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
    private func processVoiceMoveCandidates(_ candidates: [String], preferCaptures: Bool = false) -> String? {
        guard canAcceptNewMoves else { return nil }
        print("Processing move candidates: \(candidates.joined(separator: ", "))")
        guard let matched = chessEngine.executeVoiceCandidates(candidates, preferCaptures: preferCaptures) else {
            print("Could not find valid move for \(candidates.joined(separator: ", "))")
            return nil
        }
        return matched
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
    
    private func endGame(with result: PGNResult) {
        guard result != .ongoing, !game.isGameOver else { return }
        game.declareResult(result)
    }

    private func startNewGame(result: PGNResult) {
        let archiveResult = result == .ongoing ? game.gameResult : result
        beginArchiveSelection()
        pgnArchive.finalizeActiveGame(
            with: archiveResult,
            from: game,
            opening: openingService.display,
            metadataForNewGame: currentPGNMetadata
        )
        game.resetGame()
        speechRecognizer.resetTranscriptDisplay()
        finishArchiveSelection()
        scheduleSessionPersist()
    }
    
    private func clearPGN() {
        moveAssessment.cancelAll()
        pgnArchive.resetAll()
        game.resetGame()
        speechRecognizer.resetTranscriptDisplay()
        sessionStore.clearSession()
    }

    private struct PreparedGameSwitch {
        let staging: ChessGame
        let recordedGame: RecordedGame?
    }

    private func syncOutgoingGameToArchive() {
        if !pgnArchive.activeGameIsReviewOnly {
            pgnArchive.syncActiveGame(from: game, opening: openingService.display, metadata: currentPGNMetadata)
        }
    }

    private func prepareLoadedGame(for id: UUID?) async -> PreparedGameSwitch {
        beginArchiveSelection()

        guard let id,
              let recordedGame = pgnArchive.games.first(where: { $0.id == id }) else {
            return PreparedGameSwitch(staging: ChessGame(), recordedGame: nil)
        }

        let moves = recordedGame.moves
        let result = recordedGame.result
        let staging = await Task.detached(priority: .userInitiated) {
            ChessGame.prepared(from: moves, result: result)
        }.value

        return PreparedGameSwitch(staging: staging, recordedGame: recordedGame)
    }

    /// Board-only swap at the slide midpoint. Heavy archive/engine/opening work waits until
    /// `finalizeGameSwitchAfterSlide` after the slide-in finishes.
    private func commitPreparedGameSwitchBoardOnly(_ prepared: PreparedGameSwitch?) {
        guard let prepared else { return }

        if prepared.recordedGame != nil {
            game.replaceMainLine(with: prepared.staging)
            if let recordedGame = prepared.recordedGame, recordedGame.result != .ongoing {
                game.declareResult(recordedGame.result)
            }
        } else {
            game.resetGame()
        }
    }

    private func finalizeGameSwitchAfterSlide(activatingGameID: UUID?) {
        if let activatingGameID {
            pgnArchive.setActiveGame(id: activatingGameID)
        }

        openingService.refresh(game: game)
        refreshEngineIfAppropriate()
        finishArchiveSelection()

        if speechRecognizer.isRecording, pgnArchive.activeGameIsReviewOnly {
            speechRecognizer.stopRecording()
        }

        scheduleSessionPersist()
    }

    private func activateGame(id: UUID) {
        guard pgnArchive.activeGameID != id, !isGameSwitchAnimating else { return }

        guard settingsStore.settings.gameSwitchAnimationEnabled else {
            applyGameSelection(id: id)
            return
        }

        syncOutgoingGameToArchive()
        engineAnalysis.suspendInFlightAnalysis()

        let previousID = pgnArchive.activeGameID
        let direction = gameSwitchDirection(from: previousID, to: id)
        Task { @MainActor in
            await Task.yield()
            let slideDistance = gameSwitchContainerWidth
            guard slideDistance > 0 else {
                applyGameSelection(id: id)
                return
            }

            isGameSwitchAnimating = true
            defer { isGameSwitchAnimating = false }

            var prepared: PreparedGameSwitch?
            await GameSwitchSlideAnimator.run(
                direction: direction,
                distance: slideDistance,
                setOffset: { gameSwitchSlideOffset = $0 },
                prepareSwap: {
                    // Do not setActiveGame here — notation rebuild must wait until after slide-in.
                    prepared = await prepareLoadedGame(for: id)
                },
                swapContent: { commitPreparedGameSwitchBoardOnly(prepared) }
            )

            await Task.yield()
            finalizeGameSwitchAfterSlide(activatingGameID: id)
        }
    }

    private func deleteGame(id: UUID) {
        guard !isGameSwitchAnimating else { return }

        if !pgnArchive.activeGameIsReviewOnly {
            pgnArchive.syncActiveGame(from: game, opening: openingService.display, metadata: currentPGNMetadata)
        }

        let previousID = pgnArchive.activeGameID
        moveAssessment.cancelJobs(for: id, fromMoveIndex: 0)
        let nextActiveID = pgnArchive.removeGame(id: id)

        guard settingsStore.settings.gameSwitchAnimationEnabled else {
            loadActiveGameAfterDeletion(nextActiveID: nextActiveID)
            return
        }

        let direction = gameSwitchDirection(from: previousID, to: nextActiveID)
        engineAnalysis.suspendInFlightAnalysis()

        Task { @MainActor in
            await Task.yield()
            let slideDistance = gameSwitchContainerWidth
            guard slideDistance > 0 else {
                loadActiveGameAfterDeletion(nextActiveID: nextActiveID)
                return
            }

            isGameSwitchAnimating = true
            defer { isGameSwitchAnimating = false }

            var prepared: PreparedGameSwitch?
            await GameSwitchSlideAnimator.run(
                direction: direction,
                distance: slideDistance,
                setOffset: { gameSwitchSlideOffset = $0 },
                prepareSwap: {
                    prepared = await prepareLoadedGame(for: nextActiveID)
                },
                swapContent: { commitPreparedGameSwitchBoardOnly(prepared) }
            )

            await Task.yield()
            // removeGame already updated activeGameID when needed.
            finalizeGameSwitchAfterSlide(activatingGameID: nil)
        }
    }

    private func gameSwitchDirection(from oldID: UUID?, to newID: UUID?) -> GameSwitchDirection {
        let oldIndex = oldID.flatMap { id in pgnArchive.games.firstIndex { $0.id == id } }
        let newIndex = newID.flatMap { id in pgnArchive.games.firstIndex { $0.id == id } }
        return GameSwitchDirection.between(oldIndex: oldIndex, newIndex: newIndex)
    }

    private func applyGameSelection(id: UUID) {
        if !pgnArchive.activeGameIsReviewOnly {
            pgnArchive.syncActiveGame(from: game, opening: openingService.display, metadata: currentPGNMetadata)
        }

        beginArchiveSelection()
        pgnArchive.setActiveGame(id: id)
        guard let recordedGame = pgnArchive.games.first(where: { $0.id == id }) else {
            finishArchiveSelection()
            return
        }

        let loaded = game.loadMainLine(moves: recordedGame.moves)
        if !loaded {
            print("Failed to load game \(id) (\(recordedGame.moves.count) moves)")
        }
        if recordedGame.result != .ongoing {
            game.declareResult(recordedGame.result)
        }
        openingService.refresh(game: game)
        refreshEngineIfAppropriate()
        finishArchiveSelection()

        if speechRecognizer.isRecording, pgnArchive.activeGameIsReviewOnly {
            speechRecognizer.stopRecording()
        }

        scheduleSessionPersist()
    }

    private func loadActiveGameAfterDeletion(nextActiveID: UUID?) {
        beginArchiveSelection()
        if let nextActiveID,
           let recordedGame = pgnArchive.games.first(where: { $0.id == nextActiveID }) {
            _ = game.loadMainLine(moves: recordedGame.moves)
            if recordedGame.result != .ongoing {
                game.declareResult(recordedGame.result)
            }
        } else {
            game.resetGame()
        }
        openingService.refresh(game: game)
        refreshEngineIfAppropriate()
        finishArchiveSelection()

        if speechRecognizer.isRecording, pgnArchive.activeGameIsReviewOnly {
            speechRecognizer.stopRecording()
        }

        scheduleSessionPersist()
    }

    private func beginArchiveSelection() {
        isApplyingArchiveSelection = true
    }

    private func finishArchiveSelection() {
        Task { @MainActor in
            isApplyingArchiveSelection = false
        }
    }

    private func syncLiveBoardToArchiveIfRecording() {
        guard !isApplyingArchiveSelection, !pgnArchive.activeGameIsReviewOnly else { return }
        pgnArchive.syncActiveGame(from: game, opening: openingService.display, metadata: currentPGNMetadata)
    }

    private var currentPGNMetadata: PGNMetadata {
        settingsStore.settings.pgnMetadata
    }

    private var activeMoveQualities: [MoveQuality?] {
        guard let recordedGame = pgnArchive.activeGame,
              recordedGame.moves.count == game.moves.count else {
            return []
        }
        return recordedGame.moves.map(\.quality)
    }

    private func restorePersistedSessionIfAvailable() {
        guard let snapshot = sessionStore.restoreSession() else { return }

        pgnArchive.applySessionSnapshot(snapshot)
        guard let activeGameID = pgnArchive.activeGameID,
              let recordedGame = pgnArchive.games.first(where: { $0.id == activeGameID }) else {
            return
        }

        let loaded = game.loadMainLine(moves: recordedGame.moves)
        if !loaded {
            print("Session restore: failed to replay active game \(activeGameID)")
            return
        }

        if recordedGame.result != .ongoing {
            game.declareResult(recordedGame.result)
        }
    }

    private func currentSessionSnapshot() -> SessionSnapshot {
        syncLiveBoardToArchiveIfRecording()
        return SessionSnapshot(archive: pgnArchive)
    }

    private func scheduleSessionPersist() {
        sessionStore.schedulePersist(snapshot: currentSessionSnapshot())
    }

    private func flushSessionToDisk() {
        sessionStore.flush(snapshot: currentSessionSnapshot())
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
        stopRecordingIfNeeded()
    }

    private func navigateForward() {
        _ = game.goToNextPosition()
    }

    private func navigateToFirst() {
        guard game.goToFirstPosition() else { return }
        stopRecordingIfNeeded()
    }

    private func navigateToLatest() {
        _ = game.goToLatestPosition()
    }

    private func navigateToPly(_ plyIndex: Int) {
        guard game.goToPlyIndex(plyIndex) else { return }
        if plyIndex < game.moves.count {
            stopRecordingIfNeeded()
        }
    }

    private func stopRecordingIfNeeded() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
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
    let canAcceptNewMoves: Bool
    let boardSide: CGFloat

    var body: some View {
        let dimensions = BoardLayoutMetrics.Dimensions(boardSide: boardSide)

        HStack(alignment: .top, spacing: BoardLayoutMetrics.evalBarSpacing) {
            ChessBoardView(
                game: game,
                settings: settings,
                boardSide: dimensions.side,
                orientation: orientation,
                touchInputEnabled: settings.touchInputEnabled && canAcceptNewMoves,
                analysisArrow: showBoardArrow ? engineAnalysis.display.nextMoveArrow : nil,
                lastMoveArrow: lastMoveArrow(for: game, settings: settings),
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
                .frame(width: BoardLayoutMetrics.evalBarWidth, height: dimensions.side)
                .padding(
                    .top,
                    settings.usesOutsideCoordinates && orientation == .blackAtBottom
                        ? BoardLayoutMetrics.coordinateGutterLength(
                            fontSize: settings.coordinateFontSize,
                            boardScale: settings.boardSizePercent
                        )
                        : 0
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func lastMoveArrow(for game: ChessGame, settings: AppSettings) -> AnalysisArrowMove? {
        guard settings.showLastMoveArrow,
              let move = game.moveAtActivePly else {
            return nil
        }
        if settings.moveAnimationDuration > 0,
           game.activeMoveAnimation != nil || game.activeTakebackAnimation != nil {
            return nil
        }
        return AnalysisArrowMove(from: move.from, to: move.to)
    }
}

#Preview {
    ContentView(
        settingsStore: SettingsStore(),
        vocabularyStore: PersonalVocabularyStore(),
        developerModeStore: DeveloperModeStore(),
        sessionStore: SessionStore()
    )
}
