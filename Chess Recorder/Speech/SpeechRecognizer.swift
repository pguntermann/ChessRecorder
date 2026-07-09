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
    
    private let undoCooldown: TimeInterval = 1.0
    private let finalPauseNanoseconds: UInt64 = 150_000_000
    var dictationPauseSeconds: Double = 0.9
    
    var onMoveDetected: ((String) -> Bool)?
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
        
        isRebuildingLanguageModel = true
        defer { isRebuildingLanguageModel = false }
        
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
        isRebuildingLanguageModel = true
        defer { isRebuildingLanguageModel = false }
        
        ChessLanguageModel.invalidate(for: language)
        if language == currentLanguage {
            await prepareLanguageModel(for: currentLanguage)
            if isRecording {
                restartRecognitionSession()
            }
        }
    }
    
    @MainActor
    func clearPendingFailure() {
        pendingFailure = nil
    }
    
    @MainActor
    func startup(with language: RecognitionLanguage) async {
        isInitializing = true
        defer {
            isInitializing = false
            hasCompletedStartup = true
        }
        
        await requestAuthorization()
        currentLanguage = language
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
        await prepareLanguageModel(for: language)
    }
    
    @MainActor
    func setLanguage(_ language: RecognitionLanguage) async {
        guard language != currentLanguage || !isLanguageModelReady else {
            if isRecording {
                restartRecognitionSession()
            }
            return
        }
        
        currentLanguage = language
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
        
        if hasCompletedStartup {
            isRebuildingLanguageModel = true
            defer { isRebuildingLanguageModel = false }
        }
        
        await prepareLanguageModel(for: language)
        
        if isRecording {
            restartRecognitionSession()
        }
    }
    
    @MainActor
    private func prepareLanguageModel(for language: RecognitionLanguage) async {
        isLanguageModelReady = false
        guard let vocabularyStore else { return }
        _ = vocabularyStore.seedCommonPhrasesIfNeeded(for: language)
        if await ChessLanguageModel.prepare(for: language, vocabulary: vocabularyStore) != nil {
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
        await requestSpeechAuthorization()
        await requestMicrophoneAuthorization()
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
    
    func startRecording() throws {
        stopRecognitionTask()
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        let inputNode = audioEngine.inputNode
        
        try beginRecognitionTask()
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        Task { @MainActor in
            isRecording = true
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        stopRecognitionTask()
        audioEngine = nil
        
        Task { @MainActor in
            isRecording = false
            clearSessionState()
        }
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
    private func restartRecognitionSession() {
        guard audioEngine != nil else {
            try? startRecording()
            return
        }
        
        stopRecognitionTask()
        try? beginRecognitionTask()
    }
    
    @MainActor
    private func prepareForNextMove() {
        transcript = ""
        rawTranscript = ""
        lastAcceptedTranscript = nil
        lastProcessedMove = nil
        clearFailureState()
        stableTranscriptTask?.cancel()
        stableTranscriptTask = nil
        restartRecognitionSession()
    }
    
    @MainActor
    private func flushRecognitionBuffer() {
        print("Flushing accumulated transcript")
        transcript = ""
        rawTranscript = ""
        lastAcceptedTranscript = nil
        clearDictationPauseIndicator()
        stableTranscriptTask?.cancel()
        stableTranscriptTask = nil
        restartRecognitionSession()
    }
    
    @MainActor
    private func beginRecognitionTask() throws {
        recognitionGeneration += 1
        let generation = recognitionGeneration
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = getChessVocabulary(for: currentLanguage)
        
        if let config = ChessLanguageModel.configuration(for: currentLanguage) {
            recognitionRequest.requiresOnDeviceRecognition = true
            recognitionRequest.customizedLanguageModel = config
        } else if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            
            if let error {
                guard !Self.isBenignRecognitionError(error) else { return }
                Task { @MainActor in
                    guard generation == self.recognitionGeneration else { return }
                    print("Recognition error: \(error.localizedDescription)")
                    self.restartRecognitionSession()
                }
                return
            }
            
            guard let result else { return }
            let newTranscript = result.bestTranscription.formattedString
            
            Task { @MainActor in
                guard generation == self.recognitionGeneration else { return }
                self.rawTranscript = newTranscript
                self.transcript = self.correctedTranscript(for: newTranscript)
                self.handleTranscript(newTranscript, isFinal: result.isFinal)
            }
        }
    }
    
    private static func isBenignRecognitionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == 301 || nsError.code == 1110
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
        let correctedText = correctedTranscript(for: text)

        if correctedText == lastAcceptedTranscript {
            return
        }
        
        let candidates = MoveInterpreter.candidates(
            from: correctedText,
            language: currentLanguage,
            personalVocabulary: vocabularyStore
        )
        guard !candidates.isEmpty else {
            noteProcessingFailure(correctedText, attemptedMoves: [])
            return
        }
        
        print("Move candidates: \(candidates.joined(separator: ", "))")
        
        var rejectedMoves: [String] = []
        
        for move in candidates {
            if move == lastProcessedMove {
                continue
            }
            
            print("Trying move: \(move)")
            if onMoveDetected?(move) == true {
                print("Accepted move: \(move)")
                lastProcessedMove = move
                lastAcceptedTranscript = correctedText
                pendingFailure = nil
                prepareForNextMove()
                return
            }
            
            print("Rejected move: \(move)")
            rejectedMoves.append(move)
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
    private func correctedTranscript(for text: String) -> String {
        let normalized = ChessTranscriptNormalizer.normalizeForPhraseMatching(text, language: currentLanguage)
        return vocabularyStore?.applyCorrections(to: normalized, language: currentLanguage) ?? normalized
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
                "see", "sea", "bee", "dee", "gee", "aitch",
                "takes", "take", "captures", "capture", "castle",
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
    
    private func stopRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }
}
