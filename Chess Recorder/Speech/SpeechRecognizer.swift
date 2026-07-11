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
    private var lastHandledUndo: String?
    private var lastUndoTime: Date?
    private var recognitionGeneration = 0
    private var stableTranscriptTask: Task<Void, Never>?
    private var lastScheduledTranscript: String?
    /// ASR sometimes drops the source file on the final hypothesis after a correct partial ("d takes c4" → "takes c4").
    private var lastSeenCaptureFile: Character?
    private var audioSessionObserverTokens: [NSObjectProtocol] = []
    private var recognitionRecoveryTask: Task<Void, Never>?
    private var recordingSessionStartedAt: Date?
    private var lastPartialLoggedGeneration = 0
    private var lastASRTranscriptBeforeMerge = ""
    var isSpeechPipelineTracingEnabled = false
    
    private let undoCooldown: TimeInterval = 1.0
    private let finalPauseNanoseconds: UInt64 = 150_000_000
    var dictationPauseSeconds: Double = 0.9
    
    var onMoveDetected: ((String) -> Bool)?
    var onMoveCandidatesDetected: (([String]) -> String?)?
    var onUndoDetected: (() -> Void)?
    
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
        guard let vocabularyStore else { return }

        setInitializationPhase(.preparingSpeechVocabulary)
        setInitializationStatusDetail("Loading built-in chess move phrases…")
        await yieldForSpeechModelUI()

        _ = vocabularyStore.seedCommonPhrasesIfNeeded(for: language)

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
        stopRecognitionTask()
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        logSpeechDiagnostic("audio session activated (category=record, mode=measurement)")
        
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        let inputNode = audioEngine.inputNode
        
        try beginRecognitionTask(context: "startRecording")
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        logSpeechDiagnostic(
            "installing input tap (sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount))"
        )
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
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
    private func clearSessionState() {
        transcript = ""
        rawTranscript = ""
        lastProcessedMove = nil
        lastAcceptedTranscript = nil
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
    private func scheduleRecognitionRecovery(reason: String) {
        let elapsed = recordingSessionStartedAt.map { Date().timeIntervalSince($0) } ?? -1
        logSpeechDiagnostic(
            "scheduling recognition recovery in 200ms (reason=\(reason), elapsedSinceStart=\(String(format: "%.2f", elapsed))s)"
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
            self.restartRecognitionSession(reason: reason)
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
                self.scheduleRecognitionRecovery(reason: "routeChange:\(reason)")
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
                self.scheduleRecognitionRecovery(reason: "interruptionEnded")
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
        transcript = ""
        rawTranscript = ""
        lastAcceptedTranscript = nil
        lastProcessedMove = nil
        lastSeenCaptureFile = nil
        clearFailureState()
        stableTranscriptTask?.cancel()
        stableTranscriptTask = nil
        restartRecognitionSession(reason: "prepareForNextMove")
    }
    
    @MainActor
    private func flushRecognitionBuffer() {
        print("Flushing accumulated transcript")
        transcript = ""
        rawTranscript = ""
        lastAcceptedTranscript = nil
        lastSeenCaptureFile = nil
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
        let supportsOnDevice = speechRecognizer.supportsOnDeviceRecognition
        logSpeechDiagnostic(
            "beginRecognitionTask(\(context)) generation=\(generation) isAvailable=\(isAvailable) supportsOnDevice=\(supportsOnDevice)"
        )
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = getChessVocabulary(for: currentLanguage)
        
        if let config = ChessLanguageModel.configuration(for: currentLanguage) {
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
                    } else {
                        self.logSpeechDiagnostic("recognition error: \(Self.errorDescription(error)) (generation=\(generation))")
                    }
                    self.scheduleRecognitionRecovery(reason: "recognitionError:\(Self.errorDescription(error))")
                }
                return
            }
            
            guard let result else { return }
            let rawASR = result.bestTranscription.formattedString
            self.lastASRTranscriptBeforeMerge = rawASR
            let newTranscript = self.mergeDroppedCaptureFile(in: rawASR)
            
            Task { @MainActor in
                guard generation == self.recognitionGeneration else { return }
                if self.lastPartialLoggedGeneration != generation, !newTranscript.isEmpty {
                    self.lastPartialLoggedGeneration = generation
                    self.logSpeechDiagnostic(
                        "first partial transcript (generation=\(generation), isFinal=\(result.isFinal)): \"\(newTranscript)\""
                    )
                }
                self.rawTranscript = newTranscript
                self.transcript = self.correctedTranscript(for: newTranscript)
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
    private func handleTranscript(_ text: String, isFinal: Bool) {
        guard !text.isEmpty else { return }
        
        if handleUndoIfNeeded(text) {
            stableTranscriptTask?.cancel()
            clearDictationPauseIndicator()
            return
        }
        
        let pauseNanoseconds = isFinal
            ? finalPauseNanoseconds
            : UInt64(dictationPauseSeconds * 1_000_000_000)
        scheduleProcessing(for: text, after: pauseNanoseconds)
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

        let correctedText = correctedTranscript(for: text)

        if correctedText == lastAcceptedTranscript {
            tracer?.printReport(
                language: currentLanguage,
                failureReason: "Duplicate transcript — skipped"
            )
            return
        }
        
        let candidates = MoveInterpreter.candidates(
            from: text,
            language: currentLanguage,
            personalVocabulary: vocabularyStore,
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

        if let acceptedMove = onMoveCandidatesDetected?(candidates) {
            print("Accepted move from candidates: \(acceptedMove)")
            tracer?.printReport(language: currentLanguage, acceptedMove: acceptedMove)
            lastProcessedMove = acceptedMove
            lastAcceptedTranscript = correctedText
            pendingFailure = nil
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
    private func correctedTranscript(for text: String) -> String {
        let normalized = ChessTranscriptNormalizer.normalizeForPhraseMatching(
            text,
            language: currentLanguage
        )
        return vocabularyStore?.applyCorrections(
            to: normalized,
            language: currentLanguage
        ) ?? normalized
    }

    /// Restores a pawn file letter when ASR revises a partial like "d takes c4" into "takes c4".
    private func mergeDroppedCaptureFile(in raw: String) -> String {
        let lowered = raw
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return raw }

        if let regex = try? NSRegularExpression(
            pattern: #"\b([a-h])\s+(takes|take|captures|capture)\b"#
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
            of: #"^\s*(takes|take|captures|capture)\b"#,
            options: .regularExpression
        ) != nil else {
            return raw
        }

        return "\(file) \(raw.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    
    private func getChessVocabulary(for language: RecognitionLanguage) -> [String] {
        var words: [String]
        switch language {
        case .english:
            words = [
                "a", "b", "c", "d", "e", "f", "g", "h",
                "1", "2", "3", "4", "5", "6", "7", "8",
                "knight", "bishop", "rook", "queen", "king", "pawn",
                "one", "two", "three", "four", "five", "six", "seven", "eight",
                "see", "sea", "she", "cee", "bee", "dee", "gee", "aitch",
                "hey", "ay", "a3",
                "takes", "take", "captures", "capture", "castle",
                "d takes", "d takes c4", "d takes e4", "detects", "detects c4",
                "e takes", "e takes d5", "e takes f5", "he takes", "he takes f5",
                "knight b to d7", "night to be 7", "knight bd7",
                "rook a to d1", "rook a d1", "look at d1",
                "e4", "d4", "exd5", "nf3", "nf6", "nc3", "nc6", "nxd4", "qxb4", "O-O"
            ]
        case .german:
            words = [
                "a", "b", "c", "d", "e", "f", "g", "h",
                "1", "2", "3", "4", "5", "6", "7", "8",
                "eins", "zwei", "drei", "vier", "funf", "sechs", "sieben", "acht",
                "springer", "laufer", "turm", "dame", "konig", "bauer",
                "schlagt", "schlägt", "nimmt", "rochiert", "rochade", "kleine rochade", "große rochade",
                "zuruck", "zurück", "rückgängig",
                "e4", "d4", "exd4", "exd5", "nf3", "nf6", "nc3", "nc6", "nxd4", "sf3", "sxd4", "dxb4", "O-O", "O-O-O"
            ]
        }
        
        if let vocabularyStore {
            words.append(contentsOf: vocabularyStore.contextualStrings(for: language))
        }
        
        return words
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
