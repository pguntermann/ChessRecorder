//
//  SpeechRecognizer.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import Foundation
import Speech
import AVFoundation

enum RecognitionLanguage: String, CaseIterable {
    case english = "en-US"
    case german = "de-DE"
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }
    
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .german: return "🇩🇪"
        }
    }
}

struct RecognitionFailureContext: Equatable {
    let transcript: String
    let attemptedMoves: [String]
}

enum RecordingPermissionIssue: Equatable {
    case microphoneDenied
    case speechDenied
}

@Observable
class SpeechRecognizer {
    var transcript = ""
    private var rawTranscript = ""
    var isRecording = false
    var isAuthorized = false
    var isMicrophoneAuthorized = false
    var isLanguageModelReady = false
    /// True when the custom language model is missing after prepare for this session.
    var languageModelCompilationFailed = false
    /// Set when recognition cannot be recovered for this recording session.
    var recognitionSessionError: String?
    var isInitializing = true
    var isRebuildingLanguageModel = false
    var initializationPhase: InitializationPhase = .requestingPermissions
    var initializationStatusDetail: String = ""
    var currentLanguage: RecognitionLanguage = .english
    var pendingFailure: RecognitionFailureContext?
    var dictationPauseDeadline: Date?
    var dictationPauseDuration: TimeInterval = 0
    
    private var vocabularyStore: PersonalVocabularyStore?
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var lastProcessedMove: String?
    private var lastAcceptedTranscript: String?
    /// Prevents the dictation timer from restarting on stale ASR audio after a move is accepted.
    private var lastAcceptedSpeechKey: String?
    /// Recognition generation when `lastAcceptedSpeechKey` was recorded (dedup is per ASR session).
    private var lastAcceptedAtGeneration = -1
    private var lastHandledUndo: String?
    private var lastUndoTime: Date?
    private var recognitionGeneration = 0
    private var stableTranscriptTask: Task<Void, Never>?
    private var lastScheduledTranscript: String?
    /// Last raw ASR string shown in the live transcript (not corrected/processed text).
    private var lastDisplayedRawASR = ""
    private var pendingLiveTranscriptRaw: String?
    private var liveTranscriptThrottleTask: Task<Void, Never>?
    private var lastPartialNormalizeTime = Date.distantPast
    private let partialNormalizeMinInterval: TimeInterval = 0.05
    /// ASR sometimes drops the source file on the final hypothesis after a correct partial ("d takes c4" → "takes c4").
    private var lastSeenCaptureFile: Character?
    /// ASR sometimes revises a capture destination file on the final hypothesis ("dame schlagt a" → "dame schlagt e8").
    private var lastPartialCaptureDestinationFile: Character?
    /// Last hypothesis in this utterance that still contains letters (for digit-only collapse recovery).
    private var lastChessyASRPartial: String?
    private var audioSessionObserverTokens: [NSObjectProtocol] = []
    private var recognitionRecoveryTask: Task<Void, Never>?
    private var recordingSessionStartedAt: Date?
    private var consecutiveTerminalRecognitionFailures = 0
    private let maxTerminalRecognitionRecoveries = 2
    private var lastPartialLoggedGeneration = 0
    private var lastASRTranscriptBeforeMerge = ""
    var isSpeechPipelineTracingEnabled = false
    var isSpeechRecognitionFailureDiagnosticsEnabled = false
    
    private let undoCooldown: TimeInterval = 1.0
    private let finalPauseNanoseconds: UInt64 = 150_000_000
    var dictationPauseSeconds: Double = 0.9
    
    var onMoveDetected: ((String) -> Bool)?
    var onMoveCandidatesDetected: (([String], Bool) -> String?)?
    var onUndoDetected: (() -> Void)?
    /// When false, rejected voice moves are treated as stale audio (e.g. game over) — no failure UI.
    var canAcceptVoiceMoves: (() -> Bool)?
    
    var isReadyForUse: Bool {
        !isInitializing && !isRebuildingLanguageModel
    }
    
    private var hasCompletedStartup = false
    
    init(vocabularyStore: PersonalVocabularyStore? = nil) {
        self.vocabularyStore = vocabularyStore
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: currentLanguage.rawValue))
    }
    
    func setVocabularyStore(_ store: PersonalVocabularyStore) {
        vocabularyStore = store
    }
    
    @MainActor
    func learnPhrase(_ phrase: String, moveNotation: String) async {
        guard let vocabularyStore else { return }
        
        beginLanguageModelRebuild()
        await yieldForSpeechModelUI()
        defer { endLanguageModelRebuild() }
        
        vocabularyStore.learn(phrase: phrase, moveNotation: moveNotation, language: currentLanguage)
        pendingFailure = nil
        
        ChessLanguageModel.invalidate(for: currentLanguage)
        await prepareLanguageModel(for: currentLanguage)
        
        if isRecording {
            prepareForNextMove()
        }
    }

    @MainActor
    func learnCorrection(heard: String, replacement: String) async {
        guard let vocabularyStore else { return }

        beginLanguageModelRebuild()
        await yieldForSpeechModelUI()
        defer { endLanguageModelRebuild() }

        vocabularyStore.learnCorrection(heard: heard, replacement: replacement, language: currentLanguage)
        pendingFailure = nil

        ChessLanguageModel.invalidate(for: currentLanguage)
        await prepareLanguageModel(for: currentLanguage)

        if isRecording {
            prepareForNextMove()
        }
    }
    
    @MainActor
    func reloadLanguageModel(for language: RecognitionLanguage) async {
        if !isRebuildingLanguageModel {
            beginLanguageModelRebuild()
        }
        await yieldForSpeechModelUI()
        defer { endLanguageModelRebuild() }
        
        ChessLanguageModel.invalidate(for: language)
        if language == currentLanguage {
            await prepareLanguageModel(for: currentLanguage)
            if isRecording {
                restartRecognitionSession(reason: "reloadLanguageModel")
            }
        }
    }
    
    @MainActor
    func clearPendingFailure() {
        pendingFailure = nil
    }

    @MainActor
    func resetTranscriptDisplay() {
        clearLiveTranscriptDisplay()
    }
    
    @MainActor
    func startup(with language: RecognitionLanguage) async {
        logSpeechDiagnostic("startup() began for \(language.rawValue)")
        isInitializing = true
        defer {
            isInitializing = false
            hasCompletedStartup = true
            logSpeechDiagnostic("startup() finished (isLanguageModelReady=\(isLanguageModelReady))")
        }
        
        setInitializationPhase(.requestingPermissions)
        await requestAuthorization()

        setInitializationPhase(.preparingSpeechVocabulary)
        setInitializationStatusDetail("Initializing speech recognizer… Usually 5–15 seconds on first launch.")
        await yieldForSpeechModelUI()

        currentLanguage = language
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))

        await prepareLanguageModel(for: language)
        setInitializationStatusDetail("")
    }

    @MainActor
    func setInitializationPhase(_ phase: InitializationPhase) {
        initializationPhase = phase
        if phase != .preparingSpeechVocabulary {
            initializationStatusDetail = ""
        }
    }

    @MainActor
    func setInitializationStatusDetail(_ detail: String) {
        initializationStatusDetail = detail
        if !detail.isEmpty {
            logSpeechDiagnostic("initialization status: \(detail)")
        }
    }
    
    @MainActor
    func changeLanguage(_ language: RecognitionLanguage) async {
        guard language != currentLanguage || !isLanguageModelReady else {
            if isRecording {
                restartRecognitionSession(reason: "reloadLanguageModel")
            }
            if isRebuildingLanguageModel {
                endLanguageModelRebuild()
            }
            return
        }

        if hasCompletedStartup {
            if !isRebuildingLanguageModel {
                beginLanguageModelRebuild()
            }
            await yieldForSpeechModelUI()
            defer { endLanguageModelRebuild() }
        }

        currentLanguage = language
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
        await prepareLanguageModel(for: language)

        if isRecording {
            restartRecognitionSession(reason: "changeLanguage")
        }
    }

    @MainActor
    func setLanguage(_ language: RecognitionLanguage) async {
        await changeLanguage(language)
    }
    
    @MainActor
    func beginLanguageModelRebuild() {
        isRebuildingLanguageModel = true
        setInitializationPhase(.preparingSpeechVocabulary)
    }

    @MainActor
    func endLanguageModelRebuild() {
        isRebuildingLanguageModel = false
    }

    @MainActor
    private func yieldForSpeechModelUI() async {
        await Task.yield()
        // One frame for SwiftUI to present the blocking overlay before heavy work.
        try? await Task.sleep(for: .milliseconds(50))
    }

    @MainActor
    private func prepareLanguageModel(for language: RecognitionLanguage) async {
        isLanguageModelReady = false
        languageModelCompilationFailed = false
        guard let vocabularyStore else { return }

        setInitializationPhase(.preparingSpeechVocabulary)
        setInitializationStatusDetail("Loading built-in chess phrases…")
        await yieldForSpeechModelUI()

        _ = await vocabularyStore.seedCommonPhrasesIfNeeded(for: language) { [weak self] loaded, total in
            self?.setInitializationStatusDetail(
                "Loading built-in chess phrases (\(loaded) of \(total))…"
            )
        }

        let userPhraseCount = vocabularyStore.entries(for: language).count
        let correctionCount = vocabularyStore.correctionEntries(for: language).count
        if userPhraseCount > 0 || correctionCount > 0 {
            setInitializationStatusDetail(
                "Applying \(userPhraseCount) taught phrase\(userPhraseCount == 1 ? "" : "s") and \(correctionCount) correction\(correctionCount == 1 ? "" : "s")…"
            )
        } else {
            setInitializationStatusDetail("No taught phrases yet — using built-in chess vocabulary.")
        }
        await yieldForSpeechModelUI()

        let supportsOnDevice =
            SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))?.supportsOnDeviceRecognition == true

        if await ChessLanguageModel.prepare(
            for: language,
            vocabulary: vocabularyStore,
            onPhaseChange: { [weak self] phase in
                self?.initializationPhase = phase
                if phase != .preparingSpeechVocabulary {
                    self?.initializationStatusDetail = ""
                }
            },
            onStatusChange: { [weak self] detail in
                self?.setInitializationStatusDetail(detail)
            }
        ) != nil {
            isLanguageModelReady = true
            languageModelCompilationFailed = false
        } else if supportsOnDevice {
            // Custom model missing/failed — use cloud/standard recognition (no CLM).
            // Recreate the recognizer after a failed system compile attempt.
            languageModelCompilationFailed = true
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
            logSpeechDiagnostic(
                "CLM not ready for \(language.rawValue) — using recognition without custom language model"
            )
        } else {
            languageModelCompilationFailed = false
        }
    }
    
    @MainActor
    func refreshAuthorizationStatus() {
        isMicrophoneAuthorized = AVAudioApplication.shared.recordPermission == .granted
        isAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    @MainActor
    func ensureRecordingPermissions() async -> RecordingPermissionIssue? {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await requestSpeechAuthorization()
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            await requestMicrophoneAuthorization()
        }

        refreshAuthorizationStatus()

        if !isMicrophoneAuthorized {
            return .microphoneDenied
        }
        if !isAuthorized {
            return .speechDenied
        }
        return nil
    }

    @MainActor
    func requestAuthorization() async {
        refreshAuthorizationStatus()

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            logSpeechDiagnostic("requesting speech recognition authorization")
            await requestSpeechAuthorization()
        } else {
            logSpeechDiagnostic("speech recognition authorization already determined (\(Self.speechAuthorizationDescription()))")
        }

        if AVAudioApplication.shared.recordPermission == .undetermined {
            logSpeechDiagnostic("requesting microphone authorization")
            await requestMicrophoneAuthorization()
        } else {
            logSpeechDiagnostic("microphone authorization already determined (\(Self.microphonePermissionDescription()))")
        }

        refreshAuthorizationStatus()
    }

    @MainActor
    private func requestSpeechAuthorization() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        isAuthorized = status == .authorized
    }

    @MainActor
    private func requestMicrophoneAuthorization() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        isMicrophoneAuthorized = granted
    }
    
    @MainActor
    func startRecording() throws {
        logSpeechDiagnostic("startRecording() called")
        recognitionRecoveryTask?.cancel()
        recognitionRecoveryTask = nil
        consecutiveTerminalRecognitionFailures = 0
        recognitionSessionError = nil
        stopRecognitionTask()
        clearLiveTranscriptDisplay()
        rawTranscript = ""
        lastAcceptedTranscript = nil
        lastAcceptedSpeechKey = nil
        lastAcceptedAtGeneration = -1
        lastScheduledTranscript = nil
        lastChessyASRPartial = nil
        lastSeenCaptureFile = nil
        lastPartialCaptureDestinationFile = nil
        
        try RecordingAudioSession.activateForCapture(log: logSpeechDiagnostic)
        logSpeechDiagnostic("audio route: \(Self.audioRouteDescription())")
        
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        let inputNode = audioEngine.inputNode
        
        try beginRecognitionTask(context: "startRecording")
        
        RecordingAudioSession.installInputTap(on: audioEngine) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        let recordingFormat = RecordingAudioSession.inputTapFormat(for: inputNode)
        logSpeechDiagnostic(
            "installing input tap (sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount))"
        )
        
        try audioEngine.start()
        logSpeechDiagnostic("audio engine started")
        
        installAudioSessionObservers()
        isRecording = true
        recordingSessionStartedAt = Date()
        logSpeechDiagnostic("recording session ready")
    }
    
    @MainActor
    func stopRecording() {
        guard isRecording else { return }
        logSpeechDiagnostic("stopRecording() called")
        isRecording = false
        recordingSessionStartedAt = nil
        recognitionSessionError = nil
        
        recognitionRecoveryTask?.cancel()
        recognitionRecoveryTask = nil
        removeAudioSessionObservers()
        
        stableTranscriptTask?.cancel()
        stableTranscriptTask = nil
        
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        clearSessionState()
    }
    
    @MainActor
    private func clearLiveTranscriptDisplay() {
        transcript = ""
        lastDisplayedRawASR = ""
        pendingLiveTranscriptRaw = nil
        liveTranscriptThrottleTask?.cancel()
        liveTranscriptThrottleTask = nil
        lastPartialNormalizeTime = .distantPast
    }

    @MainActor
    private func clearSessionState() {
        clearLiveTranscriptDisplay()
        rawTranscript = ""
        lastProcessedMove = nil
        lastAcceptedTranscript = nil
        lastAcceptedSpeechKey = nil
        lastAcceptedAtGeneration = -1
        lastHandledUndo = nil
        lastUndoTime = nil
        pendingFailure = nil
        clearDictationPauseIndicator()
        stableTranscriptTask?.cancel()
        stableTranscriptTask = nil
        lastScheduledTranscript = nil
    }
    
    @MainActor
    private func clearFailureState() {
        pendingFailure = nil
        lastScheduledTranscript = nil
        clearDictationPauseIndicator()
    }
    
    @MainActor
    private func restartRecognitionSession(reason: String) {
        guard isRecording else {
            logSpeechDiagnostic("restartRecognitionSession skipped — not recording (reason=\(reason))")
            return
        }
        guard audioEngine != nil else {
            logSpeechDiagnostic("restartRecognitionSession falling back to full startRecording (reason=\(reason))")
            try? startRecording()
            return
        }
        
        logSpeechDiagnostic("restartRecognitionSession (reason=\(reason))")
        stopRecognitionTask(endAudio: false)
        do {
            try beginRecognitionTask(context: "restart(\(reason))")
        } catch {
            logSpeechDiagnostic("restartRecognitionSession failed to begin task: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func restartAudioCapturePipeline(reason: String) {
        guard isRecording else {
            logSpeechDiagnostic("restartAudioCapturePipeline skipped — not recording (reason=\(reason))")
            return
        }

        logSpeechDiagnostic("restartAudioCapturePipeline (reason=\(reason))")
        stopRecognitionTask(endAudio: false)

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        do {
            try RecordingAudioSession.activateForCapture(log: logSpeechDiagnostic)
            logSpeechDiagnostic("audio route: \(Self.audioRouteDescription())")

            let audioEngine = AVAudioEngine()
            self.audioEngine = audioEngine
            let inputNode = audioEngine.inputNode

            try beginRecognitionTask(context: "audioCaptureRestart(\(reason))")

            let recordingFormat = RecordingAudioSession.inputTapFormat(for: inputNode)
            logSpeechDiagnostic(
                "reinstalling input tap (sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount))"
            )
            RecordingAudioSession.installInputTap(on: audioEngine) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            try audioEngine.start()
            logSpeechDiagnostic("audio engine restarted after route change")
        } catch {
            logSpeechDiagnostic("restartAudioCapturePipeline failed: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func scheduleRecognitionRecovery(reason: String, restartsAudioCapture: Bool = false) {
        let elapsed = recordingSessionStartedAt.map { Date().timeIntervalSince($0) } ?? -1
        logSpeechDiagnostic(
            "scheduling recognition recovery in 200ms (reason=\(reason), restartAudioCapture=\(restartsAudioCapture), elapsedSinceStart=\(String(format: "%.2f", elapsed))s)"
        )
        recognitionRecoveryTask?.cancel()
        recognitionRecoveryTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else {
                self.logSpeechDiagnostic("recognition recovery cancelled (reason=\(reason))")
                return
            }
            guard self.isRecording else {
                self.logSpeechDiagnostic("recognition recovery skipped — not recording (reason=\(reason))")
                return
            }
            if restartsAudioCapture {
                self.restartAudioCapturePipeline(reason: reason)
            } else {
                self.restartRecognitionSession(reason: reason)
            }
        }
    }
    
    @MainActor
    private func installAudioSessionObservers() {
        removeAudioSessionObservers()
        let center = NotificationCenter.default
        
        let routeToken = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                let reason = Self.routeChangeReasonDescription(from: notification)
                guard Self.shouldRecoverFromRouteChange(from: notification) else {
                    self.logSpeechDiagnostic("audio route changed while recording (\(reason)) — ignoring")
                    return
                }
                self.logSpeechDiagnostic("audio route changed while recording (\(reason))")
                self.logSpeechDiagnostic("audio route: \(Self.audioRouteDescription())")
                self.scheduleRecognitionRecovery(reason: "routeChange:\(reason)", restartsAudioCapture: true)
            }
        }
        
        let interruptionToken = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                guard let info = notification.userInfo,
                      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
                self.logSpeechDiagnostic("audio interruption while recording (type=\(type.rawValue))")
                guard type == .ended else { return }
                self.scheduleRecognitionRecovery(reason: "interruptionEnded", restartsAudioCapture: true)
            }
        }
        
        audioSessionObserverTokens = [routeToken, interruptionToken]
    }
    
    @MainActor
    private func removeAudioSessionObservers() {
        let center = NotificationCenter.default
        for token in audioSessionObserverTokens {
            center.removeObserver(token)
        }
        audioSessionObserverTokens.removeAll()
    }
    
    @MainActor
    private func prepareForNextMove() {
        clearDictationPauseIndicator()
        stableTranscriptTask?.cancel()
        stableTranscriptTask = nil
        lastScheduledTranscript = nil

        clearLiveTranscriptDisplay()
        rawTranscript = ""
        lastProcessedMove = nil
        lastSeenCaptureFile = nil
        lastPartialCaptureDestinationFile = nil
        lastChessyASRPartial = nil
        clearFailureState()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard self.isRecording else { return }
            self.restartRecognitionSession(reason: "prepareForNextMove")
        }
    }
    
    @MainActor
    private func flushRecognitionBuffer() {
        print("Flushing accumulated transcript")
        clearLiveTranscriptDisplay()
        rawTranscript = ""
        lastAcceptedTranscript = nil
        lastAcceptedSpeechKey = nil
        lastAcceptedAtGeneration = -1
        lastSeenCaptureFile = nil
        lastPartialCaptureDestinationFile = nil
        lastChessyASRPartial = nil
        clearDictationPauseIndicator()
        stableTranscriptTask?.cancel()
        stableTranscriptTask = nil
        restartRecognitionSession(reason: "flushRecognitionBuffer")
    }
    
    @MainActor
    private func beginRecognitionTask(context: String) throws {
        recognitionGeneration += 1
        let generation = recognitionGeneration
        
        guard let speechRecognizer else {
            logSpeechDiagnostic("beginRecognitionTask(\(context)) failed — speechRecognizer is nil")
            throw NSError(domain: "SpeechRecognizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }
        
        let isAvailable = speechRecognizer.isAvailable
        let appleSupportsOnDevice = speechRecognizer.supportsOnDeviceRecognition
        // Only use CLM when compile succeeded and Apple reports on-device support.
        let canUseCustomLanguageModel =
            !languageModelCompilationFailed
            && appleSupportsOnDevice
            && ChessLanguageModel.configuration(for: currentLanguage) != nil
        logSpeechDiagnostic(
            "beginRecognitionTask(\(context)) generation=\(generation) isAvailable=\(isAvailable)"
                + " supportsOnDevice=\(appleSupportsOnDevice)"
                + " customLanguageModel=\(canUseCustomLanguageModel)"
        )
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = getChessVocabulary(for: currentLanguage)
        
        if canUseCustomLanguageModel,
           let config = ChessLanguageModel.configuration(for: currentLanguage) {
            recognitionRequest.requiresOnDeviceRecognition = true
            recognitionRequest.customizedLanguageModel = config
            logSpeechDiagnostic("beginRecognitionTask(\(context)) using customized on-device language model")
        } else if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
            logSpeechDiagnostic("beginRecognitionTask(\(context)) using cloud recognition (no custom language model)")
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            
            if let error {
                Task { @MainActor in
                    guard self.isRecording else { return }
                    
                    if Self.isBenignCancellationError(error) {
                        self.logSpeechDiagnostic(
                            "benign recognition error ignored: \(Self.errorDescription(error)) (generation=\(generation))"
                        )
                        return
                    }
                    
                    guard generation == self.recognitionGeneration else {
                        self.logSpeechDiagnostic(
                            "stale recognition error ignored: \(Self.errorDescription(error)) (generation=\(generation))"
                        )
                        return
                    }
                    
                    if Self.isRetryRecognitionError(error) {
                        self.logSpeechDiagnostic("recognition session ended (203 Retry) — recovering (generation=\(generation))")
                        self.consecutiveTerminalRecognitionFailures = 0
                        self.scheduleRecognitionRecovery(reason: "recognitionError:\(Self.errorDescription(error))")
                        return
                    }

                    self.logSpeechDiagnostic("recognition error: \(Self.errorDescription(error)) (generation=\(generation))")
                    self.logRecognitionFailureDiagnosticsIfEnabled(error: error, generation: generation)
                    self.consecutiveTerminalRecognitionFailures += 1
                    if self.consecutiveTerminalRecognitionFailures > self.maxTerminalRecognitionRecoveries {
                        self.abandonRecognitionRecovery(
                            message: "Speech recognition unavailable. Try again later."
                        )
                        return
                    }
                    self.scheduleRecognitionRecovery(reason: "recognitionError:\(Self.errorDescription(error))")
                }
                return
            }
            
            guard let result else { return }
            let bestASR = result.bestTranscription.formattedString
            let alternatives = result.transcriptions.map(\.formattedString)
            let selection = ASRHypothesisSelector.select(
                best: bestASR,
                alternatives: alternatives,
                previousChessyPartial: self.lastChessyASRPartial
            )
            if selection.replacedDigitOnlyBest, self.isSpeechPipelineTracingEnabled {
                self.logSpeechDiagnostic(
                    "ASR digit-only best rejected: \"\(bestASR)\" → \"\(selection.text)\""
                )
            }
            if ASRHypothesisSelector.containsLetter(selection.text) {
                self.lastChessyASRPartial = selection.text
            }
            let rawASR = selection.text
            self.lastASRTranscriptBeforeMerge = rawASR
            if self.isSpeechPipelineTracingEnabled {
                self.logSpeechDiagnostic(Self.formatASRCallbackTrace(result, generation: generation))
            }
            let newTranscript = self.mergeCaptureTranscriptCorrections(in: rawASR)
            
            Task { @MainActor in
                guard generation == self.recognitionGeneration else { return }
                if !newTranscript.isEmpty {
                    self.consecutiveTerminalRecognitionFailures = 0
                    self.recognitionSessionError = nil
                }
                if self.lastPartialLoggedGeneration != generation, !newTranscript.isEmpty {
                    self.lastPartialLoggedGeneration = generation
                    self.logSpeechDiagnostic(
                        "first partial transcript (generation=\(generation), isFinal=\(result.isFinal)): \"\(newTranscript)\""
                    )
                }
                self.rawTranscript = newTranscript
                self.updateLiveTranscript(from: newTranscript, isFinal: result.isFinal)
                self.handleTranscript(newTranscript, isFinal: result.isFinal)
            }
        }
        
        if recognitionTask == nil {
            logSpeechDiagnostic("beginRecognitionTask(\(context)) failed — recognitionTask is nil despite isAvailable=\(isAvailable)")
            throw NSError(domain: "SpeechRecognizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to start recognition task"])
        }
        
        logSpeechDiagnostic("beginRecognitionTask(\(context)) started recognition task (generation=\(generation))")
    }
    
    private static func isBenignCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // 216 = session cancelled (e.g. rotation/stop); 301/1110 = end-of-utterance variants
        return nsError.domain == "kAFAssistantErrorDomain"
            && [216, 301, 1110].contains(nsError.code)
    }
    
    private static func isRetryRecognitionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // 203 = "Retry" — task ended; start a fresh recognition request while still recording
        return nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 203
    }

    @MainActor
    private func abandonRecognitionRecovery(message: String) {
        recognitionRecoveryTask?.cancel()
        recognitionRecoveryTask = nil
        logSpeechDiagnostic("abandoning recognition recovery — \(message)")
        if isRecording {
            stopRecording()
        } else {
            stopRecognitionTask(endAudio: false)
        }
        // stopRecording clears this; restore so the live transcript can show the failure.
        recognitionSessionError = message
    }
    
    @MainActor
    private func updateLiveTranscript(from raw: String, isFinal: Bool) {
        guard !raw.isEmpty else { return }
        guard raw != lastDisplayedRawASR else { return }

        let now = Date()
        if !isFinal,
           now.timeIntervalSince(lastPartialNormalizeTime) < partialNormalizeMinInterval {
            pendingLiveTranscriptRaw = raw
            scheduleThrottledLiveTranscriptUpdate()
            return
        }

        applyLiveTranscriptDisplay(raw: raw)
    }

    @MainActor
    private func applyLiveTranscriptDisplay(raw: String) {
        pendingLiveTranscriptRaw = nil
        liveTranscriptThrottleTask?.cancel()
        liveTranscriptThrottleTask = nil

        transcript = ChessTranscriptNormalizer.normalizeForPhraseMatching(
            raw,
            language: currentLanguage
        )
        lastDisplayedRawASR = raw
        lastPartialNormalizeTime = Date()
    }

    @MainActor
    private func scheduleThrottledLiveTranscriptUpdate() {
        guard let pending = pendingLiveTranscriptRaw,
              pending != lastDisplayedRawASR else { return }

        liveTranscriptThrottleTask?.cancel()
        let delay = max(0, partialNormalizeMinInterval - Date().timeIntervalSince(lastPartialNormalizeTime))
        liveTranscriptThrottleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let pending = self.pendingLiveTranscriptRaw,
                  pending != self.lastDisplayedRawASR else { return }
            self.applyLiveTranscriptDisplay(raw: pending)
        }
    }

    @MainActor
    private func handleTranscript(_ text: String, isFinal: Bool) {
        guard !text.isEmpty else { return }
        
        if handleUndoIfNeeded(text) {
            stableTranscriptTask?.cancel()
            clearDictationPauseIndicator()
            return
        }

        if matchesLastAcceptedSpeech(text) {
            clearDictationPauseIndicator()
            stableTranscriptTask?.cancel()
            stableTranscriptTask = nil
            lastScheduledTranscript = nil
            return
        }
        
        let pauseNanoseconds = isFinal
            ? finalPauseNanoseconds
            : UInt64(dictationPauseSeconds * 1_000_000_000)
        scheduleProcessing(for: text, after: pauseNanoseconds)
    }

    private func speechComparisonKey(for text: String) -> String {
        correctedTranscript(for: text)
    }

    private func matchesLastAcceptedSpeech(_ text: String) -> Bool {
        guard let lastAcceptedSpeechKey,
              lastAcceptedAtGeneration == recognitionGeneration else { return false }
        return speechComparisonKey(for: text) == lastAcceptedSpeechKey
    }
    
    @MainActor
    private func clearDictationPauseIndicator() {
        dictationPauseDeadline = nil
        dictationPauseDuration = 0
    }
    
    @MainActor
    private func scheduleProcessing(for text: String, after nanoseconds: UInt64) {
        stableTranscriptTask?.cancel()
        lastScheduledTranscript = text
        
        let pauseSeconds = Double(nanoseconds) / 1_000_000_000
        dictationPauseDuration = pauseSeconds
        dictationPauseDeadline = Date().addingTimeInterval(pauseSeconds)
        
        stableTranscriptTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            guard text == self.rawTranscript else { return }
            guard self.lastScheduledTranscript == text else { return }
            self.clearDictationPauseIndicator()
            self.processTranscript(text)
        }
    }
    
    @MainActor
    private func processTranscript(_ text: String) {
        let tracer = isSpeechPipelineTracingEnabled ? SpeechPipelineTracer(enabled: true) : nil
        if let tracer {
            tracer.record("ASR", "Raw hypothesis", lastASRTranscriptBeforeMerge.isEmpty ? text : lastASRTranscriptBeforeMerge)
            if !lastASRTranscriptBeforeMerge.isEmpty, lastASRTranscriptBeforeMerge != text {
                tracer.record("ASR", "After capture-file merge", text)
            }
        }

        let correctedText = correctedTranscript(for: text, tracer: tracer)
        transcript = correctedText

        if correctedText == lastAcceptedTranscript,
           lastAcceptedAtGeneration == recognitionGeneration {
            tracer?.printReport(
                language: currentLanguage,
                failureReason: "Duplicate transcript — skipped"
            )
            return
        }

        let candidates = MoveInterpreter.candidates(
            from: correctedText,
            language: currentLanguage,
            personalVocabulary: vocabularyStore,
            transcriptAlreadyNormalized: true,
            tracer: tracer
        )
        guard !candidates.isEmpty else {
            tracer?.printReport(
                language: currentLanguage,
                failureReason: "No move candidates parsed"
            )
            noteProcessingFailure(correctedText, attemptedMoves: [])
            return
        }

        print("Move candidates: \(candidates.joined(separator: ", "))")

        let preferCaptures = MoveInterpreter.prefersCaptureResolution(
            from: correctedText,
            language: currentLanguage,
            transcriptAlreadyNormalized: true
        )

        if let acceptedMove = onMoveCandidatesDetected?(candidates, preferCaptures) {
            print("Accepted move from candidates: \(acceptedMove)")
            tracer?.printReport(language: currentLanguage, acceptedMove: acceptedMove)
            lastProcessedMove = acceptedMove
            lastAcceptedTranscript = correctedText
            lastAcceptedSpeechKey = correctedText
            lastAcceptedAtGeneration = recognitionGeneration
            pendingFailure = nil
            prepareForNextMove()
            return
        }

        if canAcceptVoiceMoves?() == false {
            tracer?.printReport(
                language: currentLanguage,
                failureReason: "Stale speech ignored — game not accepting moves"
            )
            prepareForNextMove()
            return
        }

        var rejectedMoves: [String] = []

        for move in candidates {
            if move == lastProcessedMove {
                continue
            }

            print("Trying move: \(move)")
            if onMoveDetected?(move) == true {
                print("Accepted move: \(move)")
                tracer?.printReport(language: currentLanguage, acceptedMove: move)
                lastProcessedMove = move
                lastAcceptedTranscript = correctedText
                lastAcceptedSpeechKey = correctedText
                lastAcceptedAtGeneration = recognitionGeneration
                pendingFailure = nil
                prepareForNextMove()
                return
            }

            print("Rejected move: \(move)")
            rejectedMoves.append(move)
        }

        tracer?.printReport(
            language: currentLanguage,
            rejectedMoves: rejectedMoves,
            failureReason: "No legal move matched"
        )
        if canAcceptVoiceMoves?() == false {
            prepareForNextMove()
            return
        }
        noteProcessingFailure(correctedText, attemptedMoves: rejectedMoves)
    }
    
    @MainActor
    private func noteProcessingFailure(_ text: String, attemptedMoves: [String]) {
        pendingFailure = RecognitionFailureContext(
            transcript: text,
            attemptedMoves: attemptedMoves
        )
        flushRecognitionBuffer()
    }

    @MainActor
    private func correctedTranscript(for text: String, tracer: SpeechPipelineTracer? = nil) -> String {
        let normalized = ChessTranscriptNormalizer.normalizeForPhraseMatching(
            text,
            language: currentLanguage,
            tracer: tracer
        )
        return vocabularyStore?.applyCorrections(
            to: normalized,
            language: currentLanguage,
            tracer: tracer
        ) ?? normalized
    }

    @MainActor
    private func mergeCaptureTranscriptCorrections(in raw: String) -> String {
        let preprocessed: String
        if currentLanguage == .german {
            preprocessed = ChessTranscriptNormalizer.repairGermanAFileMishearings(in: raw)
        } else {
            preprocessed = raw
        }
        let afterDroppedFile = mergeDroppedCaptureFile(in: preprocessed)
        return stabilizeCaptureDestinationFile(in: afterDroppedFile)
    }

    /// Restores a pawn file letter when ASR revises a partial like "d takes c4" into "takes c4".
    private func mergeDroppedCaptureFile(in raw: String) -> String {
        let lowered = raw
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return raw }

        let captureVerbPattern: String
        switch currentLanguage {
        case .english:
            captureVerbPattern = #"takes|take|captures|capture"#
        case .german:
            captureVerbPattern = #"schlagt|schlägt|schlaegt|schagt|nimmt"#
        }

        if let regex = try? NSRegularExpression(
            pattern: #"\b([a-h])\s+(\#(captureVerbPattern))\b"#
        ),
           let match = regex.firstMatch(
            in: lowered,
            range: NSRange(lowered.startIndex..., in: lowered)
           ),
           let fileRange = Range(match.range(at: 1), in: lowered),
           let file = lowered[fileRange].first {
            lastSeenCaptureFile = file
            return raw
        }

        guard let file = lastSeenCaptureFile else { return raw }
        guard lowered.range(
            of: #"^\s*(\#(captureVerbPattern))\b"#,
            options: .regularExpression
        ) != nil else {
            return raw
        }

        return "\(file) \(raw.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Keeps a capture destination file when ASR revises a partial like "dame schlagt a" into "dame schlagt e8".
    private func stabilizeCaptureDestinationFile(in raw: String) -> String {
        let lowered = raw
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else {
            lastPartialCaptureDestinationFile = nil
            return raw
        }

        let piecePattern: String
        let verbPattern: String
        switch currentLanguage {
        case .english:
            piecePattern = #"knight|night|bishop|rook|rock|look|queen|king|pawn"#
            verbPattern = #"takes|take|captures|capture"#
        case .german:
            piecePattern = #"springer|laufer|laeufer|läufer|turm|dame|konig|könig|bauer"#
            verbPattern = #"schlagt|schlägt|schlaegt|schagt|nimmt"#
        }

        let trailingFilePattern = #"(\#(piecePattern))\s+(\#(verbPattern))\s+([a-h])\s*$"#
        let completeSquarePattern = #"(\#(piecePattern))\s+(\#(verbPattern))\s+([a-h])([1-8])\s*$"#

        if let regex = try? NSRegularExpression(pattern: completeSquarePattern),
           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let fileRange = Range(match.range(at: 3), in: lowered),
           let rankRange = Range(match.range(at: 4), in: lowered),
           let partialFile = lastPartialCaptureDestinationFile {
            let heardFile = lowered[fileRange]
            let rank = lowered[rankRange]
            if heardFile != String(partialFile) {
                let squareRange = NSRange(
                    location: match.range(at: 3).location,
                    length: match.range(at: 3).length + match.range(at: 4).length
                )
                let replacement = String(partialFile) + rank
                let stabilized = (raw as NSString).replacingCharacters(in: squareRange, with: replacement)
                lastPartialCaptureDestinationFile = nil
                return stabilized
            }
            lastPartialCaptureDestinationFile = nil
            return raw
        }

        if let regex = try? NSRegularExpression(pattern: trailingFilePattern),
           let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
           let fileRange = Range(match.range(at: 3), in: lowered),
           let file = lowered[fileRange].first {
            lastPartialCaptureDestinationFile = file
            return raw
        }

        if lowered.range(of: verbPattern, options: .regularExpression) == nil {
            lastPartialCaptureDestinationFile = nil
        }

        return raw
    }
    
    private static let maxContextualStrings = 100

    private func getChessVocabulary(for language: RecognitionLanguage) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func appendUnique(_ strings: [String]) {
            for string in strings {
                let key = string.lowercased()
                guard seen.insert(key).inserted else { continue }
                result.append(string)
                if result.count >= Self.maxContextualStrings { return }
            }
        }

        switch language {
        case .english:
            appendUnique([
                "a", "b", "c", "d", "e", "f", "g", "h",
                "1", "2", "3", "4", "5", "6", "7", "8",
                "knight", "bishop", "rook", "queen", "king", "pawn",
                "one", "two", "three", "four", "five", "six", "seven", "eight",
                "see", "sea", "she", "cee", "bee", "dee", "gee", "aitch",
                "hey", "ay",
                "takes", "take", "captures", "capture", "castle", "castling",
                "castle kingside", "castle queenside", "castle on kingside", "castle on queenside",
                "d takes", "d takes c4", "e takes", "e takes d5",
                "e4", "d4", "nf3", "O-O"
            ])
        case .german:
            appendUnique([
                "a", "b", "c", "d", "e", "f", "g", "h",
                "ah",
                "1", "2", "3", "4", "5", "6", "7", "8",
                "eins", "zwei", "drei", "vier", "funf", "sechs", "sieben", "acht",
                "springer", "laufer", "läufer", "turm", "dame", "konig", "könig", "bauer",
                "schlagt", "schlägt", "nimmt", "rochade", "kleine rochade", "große rochade",
                "lange rochade", "lang rochade", "rochade auf damenseite", "rochade auf königsseite",
                "zuruck", "zurück", "rückgängig",
                "e4", "d4", "nf3", "O-O", "O-O-O"
            ])
        }

        if let vocabularyStore {
            appendUnique(vocabularyStore.contextualStrings(for: language))
        }

        return result
    }
    
    @MainActor
    private func handleUndoIfNeeded(_ text: String) -> Bool {
        let normalized = normalizeCommandText(text)
        guard let undoPhrase = trailingUndoCommand(in: normalized) else { return false }
        
        let now = Date()
        if normalized == lastHandledUndo,
           let lastUndoTime,
           now.timeIntervalSince(lastUndoTime) < undoCooldown {
            return true
        }
        
        lastHandledUndo = normalized
        lastUndoTime = now
        lastProcessedMove = nil
        lastAcceptedTranscript = nil
        lastAcceptedSpeechKey = nil
        lastAcceptedAtGeneration = -1
        
        print("Undo command detected: \(undoPhrase)")
        onUndoDetected?()
        prepareForNextMove()
        return true
    }
    
    private func trailingUndoCommand(in normalized: String) -> String? {
        let words = tokenizeCommandWords(normalized)
        guard !words.isEmpty else { return nil }
        
        let undoWords: Set<String> = [
            "undo", "back", "takeback", "reverse",
            "zuruck", "ruckgangig", "zuruckmachen", "zurucknehmen"
        ]
        
        if let last = words.last, undoWords.contains(last) {
            return last
        }
        
        if words.count >= 2 {
            let lastTwo = words.suffix(2).joined(separator: " ")
            if lastTwo == "take back" {
                return lastTwo
            }
        }
        
        return nil
    }
    
    private func tokenizeCommandWords(_ text: String) -> [String] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }
    
    private func normalizeCommandText(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ß", with: "ss")
    }
    
    private func stopRecognitionTask(endAudio: Bool = true) {
        recognitionTask?.cancel()
        recognitionTask = nil
        if endAudio {
            recognitionRequest?.endAudio()
        }
        recognitionRequest = nil
    }
    
    private func logSpeechDiagnostic(_ message: String) {
        print("SpeechRecognizer: \(message)")
    }

    private func logRecognitionFailureDiagnosticsIfEnabled(error: Error, generation: Int) {
        guard isSpeechRecognitionFailureDiagnosticsEnabled else { return }
        logSpeechDiagnostic(
            Self.formatRecognitionFailureDiagnostics(
                error: error,
                generation: generation,
                language: currentLanguage,
                speechRecognizer: speechRecognizer,
                recognitionRequest: recognitionRequest,
                languageModelCompilationFailed: languageModelCompilationFailed,
                hasCustomLanguageModel: ChessLanguageModel.configuration(for: currentLanguage) != nil
            )
        )
    }

    /// Compact pre-merge ASR dump: best + N-best + segment confidence/alts.
    private static func formatASRCallbackTrace(_ result: SFSpeechRecognitionResult, generation: Int) -> String {
        let best = result.bestTranscription
        var lines: [String] = [
            "ASR (gen=\(generation) final=\(result.isFinal)) best=\"\(best.formattedString)\""
        ]

        let nbest = result.transcriptions.prefix(3).map { "\"\($0.formattedString)\"" }
        if !nbest.isEmpty {
            lines.append("  nbest: \(nbest.joined(separator: " | "))")
        }

        let segments = best.segments.map { segment -> String in
            let conf = String(format: "%.2f", segment.confidence)
            var part = "\(segment.substring)(\(conf))"
            if !segment.alternativeSubstrings.isEmpty {
                part += "[\(segment.alternativeSubstrings.joined(separator: ","))]"
            }
            return part
        }
        if !segments.isEmpty {
            lines.append("  segs: \(segments.joined(separator: " | "))")
        }

        return lines.joined(separator: "\nSpeechRecognizer: ")
    }

    private static func formatRecognitionFailureDiagnostics(
        error: Error,
        generation: Int,
        language: RecognitionLanguage,
        speechRecognizer: SFSpeechRecognizer?,
        recognitionRequest: SFSpeechAudioBufferRecognitionRequest?,
        languageModelCompilationFailed: Bool,
        hasCustomLanguageModel: Bool
    ) -> String {
        let session = AVAudioSession.sharedInstance()
        #if targetEnvironment(simulator)
        let runtime = "simulator"
        #else
        let runtime = "device"
        #endif

        var lines: [String] = [
            "recognition failure diagnostics (gen=\(generation) runtime=\(runtime))",
            "  error: \(detailedErrorDescription(error))",
            "  language=\(language.rawValue) speechAuth=\(speechAuthorizationDescription()) micAuth=\(microphonePermissionDescription())",
            "  recognizer: available=\(speechRecognizer?.isAvailable ?? false) supportsOnDevice=\(speechRecognizer?.supportsOnDeviceRecognition ?? false) locale=\(speechRecognizer?.locale.identifier ?? "nil")",
            "  request: onDevice=\(recognitionRequest.map { String($0.requiresOnDeviceRecognition) } ?? "nil") customLM=\(recognitionRequest?.customizedLanguageModel != nil) contextualStrings=\(recognitionRequest?.contextualStrings.count ?? 0)",
            "  clm: compilationFailed=\(languageModelCompilationFailed) configPresent=\(hasCustomLanguageModel)",
            "  audio: category=\(session.category.rawValue) mode=\(session.mode.rawValue) options=\(session.categoryOptions.rawValue) sampleRate=\(session.sampleRate) ioBuffer=\(session.ioBufferDuration)",
            "  route: \(audioRouteDescription())"
        ]

        return lines.joined(separator: "\nSpeechRecognizer: ")
    }

    private static func detailedErrorDescription(_ error: Error, depth: Int = 0) -> String {
        let nsError = error as NSError
        var parts = [
            "\(nsError.domain) \(nsError.code) \"\(nsError.localizedDescription)\""
        ]
        if let reason = nsError.localizedFailureReason, !reason.isEmpty {
            parts.append("reason=\"\(reason)\"")
        }
        if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
            parts.append("suggestion=\"\(suggestion)\"")
        }

        let indent = String(repeating: "  ", count: depth + 1)
        var lines = [parts.joined(separator: " ")]

        if !nsError.userInfo.isEmpty {
            let keys = nsError.userInfo.keys.map(String.init(describing:)).sorted()
            for key in keys {
                if key == NSLocalizedDescriptionKey
                    || key == NSLocalizedFailureReasonErrorKey
                    || key == NSLocalizedRecoverySuggestionErrorKey {
                    continue
                }
                guard let value = nsError.userInfo[key] else { continue }
                if let underlying = value as? Error {
                    lines.append("\(indent)userInfo[\(key)] => \(detailedErrorDescription(underlying, depth: depth + 1))")
                } else {
                    lines.append("\(indent)userInfo[\(key)] = \(stringifyUserInfoValue(value))")
                }
            }
        }

        return lines.joined(separator: "\nSpeechRecognizer: ")
    }

    private static func stringifyUserInfoValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return "\"\(string)\""
        case let number as NSNumber:
            return number.stringValue
        case let url as URL:
            return url.absoluteString
        case let data as Data:
            return "Data(\(data.count) bytes)"
        case let array as [Any]:
            return "[\(array.map(stringifyUserInfoValue).joined(separator: ", "))]"
        case let dict as [AnyHashable: Any]:
            let body = dict.keys.map(String.init(describing:)).sorted().map { key in
                "\(key)=\(stringifyUserInfoValue(dict[key] as Any))"
            }.joined(separator: ", ")
            return "{\(body)}"
        default:
            return String(describing: value)
        }
    }
    
    private static func errorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code) \"\(nsError.localizedDescription)\""
    }
    
    private static func speechAuthorizationDescription() -> String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .authorized:
            return "authorized"
        @unknown default:
            return "unknown"
        }
    }

    private static func microphonePermissionDescription() -> String {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            return "undetermined"
        case .denied:
            return "denied"
        case .granted:
            return "granted"
        @unknown default:
            return "unknown"
        }
    }

    private static func audioRouteDescription() -> String {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute

        func portDescription(_ port: AVAudioSessionPortDescription) -> String {
            "\(port.portName) (\(port.portType.rawValue))"
        }

        let inputs = route.inputs.map(portDescription)
        let outputs = route.outputs.map(portDescription)
        let inputText = inputs.isEmpty ? "none" : inputs.joined(separator: ", ")
        let outputText = outputs.isEmpty ? "none" : outputs.joined(separator: ", ")

        var parts = ["input=\(inputText)", "output=\(outputText)"]

        if let preferred = session.preferredInput {
            parts.append("preferredInput=\(portDescription(preferred))")
        }

        if let available = session.availableInputs?.map(portDescription), !available.isEmpty {
            parts.append("availableInputs=[\(available.joined(separator: ", "))]")
        }

        return parts.joined(separator: " | ")
    }

    private static func shouldRecoverFromRouteChange(from notification: Notification) -> Bool {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return false
        }

        switch reason {
        case .categoryChange, .routeConfigurationChange:
            return false
        default:
            return true
        }
    }
    
    private static func routeChangeReasonDescription(from notification: Notification) -> String {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return "unknown"
        }
        
        switch reason {
        case .unknown:
            return "unknown"
        case .newDeviceAvailable:
            return "newDeviceAvailable"
        case .oldDeviceUnavailable:
            return "oldDeviceUnavailable"
        case .categoryChange:
            return "categoryChange"
        case .override:
            return "override"
        case .wakeFromSleep:
            return "wakeFromSleep"
        case .noSuitableRouteForCategory:
            return "noSuitableRouteForCategory"
        case .routeConfigurationChange:
            return "routeConfigurationChange"
        @unknown default:
            return "unknown(\(reasonValue))"
        }
    }
}
