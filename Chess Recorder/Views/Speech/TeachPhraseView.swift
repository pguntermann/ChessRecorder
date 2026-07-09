//
//  TeachPhraseView.swift
//  Chess Recorder
//

import AVFoundation
import Speech
import SwiftUI

struct TeachPhraseView: View {
    @Environment(\.dismiss) private var dismiss
    
    let language: RecognitionLanguage
    let initialTranscript: String
    let attemptedMoves: [String]
    let onSave: (String, String) async -> Void
    
    @State private var phrase: String
    @State private var moveNotation: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var recorder: PhraseRecorder
    
    init(
        language: RecognitionLanguage,
        context: RecognitionFailureContext,
        onSave: @escaping (String, String) async -> Void
    ) {
        self.language = language
        self.initialTranscript = context.transcript
        self.attemptedMoves = context.attemptedMoves
        self.onSave = onSave
        _phrase = State(initialValue: context.transcript)
        _moveNotation = State(initialValue: context.attemptedMoves.first ?? "")
        _recorder = State(initialValue: PhraseRecorder(language: language))
    }

    init(
        language: RecognitionLanguage,
        initialPhrase: String = "",
        attemptedMoves: [String] = [],
        onSave: @escaping (String, String) async -> Void
    ) {
        self.language = language
        self.initialTranscript = initialPhrase
        self.attemptedMoves = attemptedMoves
        self.onSave = onSave
        _phrase = State(initialValue: initialPhrase)
        _moveNotation = State(initialValue: attemptedMoves.first ?? "")
        _recorder = State(initialValue: PhraseRecorder(language: language))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("When you say a phrase, the app will boost it in speech recognition and map it to your move notation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("What you said") {
                    TextField("Spoken phrase", text: $phrase, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await toggleRecording() }
                    } label: {
                        Label(
                            recorder.isRecording ? "Stop listening" : "Speak phrase",
                            systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill"
                        )
                    }
                    .disabled(!recorder.canRecord && !recorder.isRecording)

                    if recorder.isRecording || !recorder.transcript.isEmpty {
                        Text(recorder.transcript.isEmpty ? "Listening..." : recorder.transcript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Intended move (SAN)") {
                    TextField("e.g. bxa5, Nf3, O-O", text: $moveNotation)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    if !attemptedMoves.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tried:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(attemptedMoves.joined(separator: ", "))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Teach Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await recorder.prepare()
            }
            .onChange(of: recorder.transcript) { _, newValue in
                guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                phrase = newValue
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }
    
    private var canSave: Bool {
        !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !moveNotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        let trimmedMove = moveNotation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ChessPosition(notation: String(trimmedMove.suffix(2))) != nil ||
              ChessKitMapping.parseCoordinateMove(trimmedMove) != nil ||
              trimmedMove.caseInsensitiveCompare("O-O") == .orderedSame ||
              trimmedMove.caseInsensitiveCompare("O-O-O") == .orderedSame ||
              trimmedMove.contains("x") ||
              trimmedMove.first?.isLetter == true else {
            errorMessage = "Enter a valid move like bxa5, e4, Nf3, or g1f3."
            return
        }
        
        recorder.stop()
        await onSave(phrase, trimmedMove)
        dismiss()
    }

    private func toggleRecording() async {
        errorMessage = nil

        if recorder.isRecording {
            recorder.stop()
            return
        }

        do {
            try await recorder.start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@Observable
@MainActor
private final class PhraseRecorder {
    var transcript = ""
    var isRecording = false
    var canRecord = false

    private let language: RecognitionLanguage
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    init(language: RecognitionLanguage) {
        self.language = language
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
    }

    func prepare() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        canRecord = status == .authorized
    }

    func start() async throws {
        guard canRecord else {
            throw NSError(domain: "TeachPhraseView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission is required."])
        }

        stop()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw NSError(domain: "TeachPhraseView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is unavailable right now."])
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stop()
                    }
                }
            } else if error != nil {
                Task { @MainActor in
                    self.stop()
                }
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        recognitionRequest = request
        isRecording = true
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
    }
}
