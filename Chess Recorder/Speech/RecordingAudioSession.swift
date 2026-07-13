//
//  RecordingAudioSession.swift
//  Chess Recorder
//

import AVFoundation

enum RecordingAudioSession {
    static func activateForCapture(log: ((String) -> Void)? = nil) throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.duckOthers, .allowBluetoothHFP]
        if #available(iOS 26.0, *) {
            options.insert(.bluetoothHighQualityRecording)
        }
        try session.setCategory(.playAndRecord, mode: .measurement, options: options)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        log?("audio session activated (category=playAndRecord, mode=measurement, options=\(options.rawValue))")
        updatePreferredInput(session: session, log: log)
    }

    /// Deactivates then re-activates capture after an audio route change.
    static func reactivateForCapture(log: ((String) -> Void)? = nil) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        try activateForCapture(log: log)
    }

    static func inputTapFormat(for inputNode: AVAudioInputNode) -> AVAudioFormat {
        inputNode.outputFormat(forBus: 0)
    }

    /// Installs an input tap using `nil` format so AVAudioEngine delivers its negotiated
    /// hardware format. The tap must be installed before `prepare()` so the graph has an input node.
    static func installInputTap(
        on engine: AVAudioEngine,
        bufferSize: AVAudioFrameCount = 1024,
        handler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        let inputNode = engine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil, block: handler)
        engine.prepare()
    }

    static func updatePreferredInput(
        session: AVAudioSession = .sharedInstance(),
        log: ((String) -> Void)? = nil
    ) {
        guard let inputs = session.availableInputs, !inputs.isEmpty else {
            clearPreferredInput(session: session, log: log, reason: "no availableInputs")
            return
        }

        if let bluetoothInput = inputs.first(where: { $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE }) {
            setPreferredInput(bluetoothInput, session: session, log: log)
            return
        }

        if let builtInInput = inputs.first(where: { $0.portType == .builtInMic }) {
            setPreferredInput(builtInInput, session: session, log: log)
            return
        }

        clearPreferredInput(session: session, log: log, reason: "no known microphone in availableInputs")
    }

    static func activeCaptureInputDisplayName() -> String {
        let session = AVAudioSession.sharedInstance()

        if let routeInput = session.currentRoute.inputs.first {
            return routeInput.portName
        }

        if let preferred = session.preferredInput {
            return preferred.portName
        }

        return String(localized: "Microphone")
    }

    static func currentInputDisplayName() -> String {
        activeCaptureInputDisplayName()
    }

    private static func setPreferredInput(
        _ input: AVAudioSessionPortDescription,
        session: AVAudioSession,
        log: ((String) -> Void)?
    ) {
        do {
            try session.setPreferredInput(input)
            log?("preferred input set to \(input.portName) (\(input.portType.rawValue))")
        } catch {
            log?("preferred input failed for \(input.portName): \(error.localizedDescription)")
        }
    }

    private static func clearPreferredInput(
        session: AVAudioSession,
        log: ((String) -> Void)?,
        reason: String
    ) {
        do {
            try session.setPreferredInput(nil)
            log?("preferred input cleared (\(reason))")
        } catch {
            log?("preferred input clear failed (\(reason)): \(error.localizedDescription)")
        }
    }
}
