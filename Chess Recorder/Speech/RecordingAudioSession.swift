//
//  RecordingAudioSession.swift
//  Chess Recorder
//

import AVFoundation

enum RecordingAudioSession {
    /// Dedicated queue so `setActive` / `setPreferredInput` are not called on the main thread
    /// (AVAudioSession Hang Risk).
    private static let sessionQueue = DispatchQueue(label: "com.pguntermann.ChessRecorder.audioSession")

    /// Preference / cache state must not use `sessionQueue.sync` — that blocks the UI while
    /// AVAudioSession activate/deactivate is in flight on the session queue.
    private static let stateLock = NSLock()
    private static var _preferredInputUID: String?
    private static var _cachedCaptureInputs: [CachedCaptureInput] = []

    /// Empty / nil means Automatic (Bluetooth preferred over built-in).
    /// Set from app settings before activating capture.
    static var preferredInputUID: String? {
        get { withStateLock { _preferredInputUID } }
        set { withStateLock { _preferredInputUID = newValue } }
    }

    /// Last discovered capture inputs (Bluetooth-capable discovery). Safe to show in Settings
    /// immediately while a fresh discover runs in the background.
    static var cachedCaptureInputs: [CachedCaptureInput] {
        withStateLock { _cachedCaptureInputs }
    }

    /// Snapshot of a capture port for Settings UI (does not retain AVAudioSession objects).
    struct CachedCaptureInput: Sendable, Equatable, Identifiable {
        var id: String { uid }
        let uid: String
        let portName: String
        let portType: String
    }

    static func activateForCaptureAsync(log: (@Sendable (String) -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try activateForCaptureOnSessionQueue(log: log)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Deactivates then re-activates capture after an audio route change or mic preference change.
    static func reactivateForCaptureAsync(log: (@Sendable (String) -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setActive(false, options: .notifyOthersOnDeactivation)
                    try activateForCaptureOnSessionQueue(log: log)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Applies a sticky/automatic input preference with a full session rebuild so category
    /// options match (e.g. drop Bluetooth HFP when the built-in mic is forced).
    static func applyPreferredInputChangeAsync(log: (@Sendable (String) -> Void)? = nil) async {
        do {
            try await reactivateForCaptureAsync(log: log)
        } catch {
            log?("apply preferred input change failed: \(error.localizedDescription)")
        }
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

    /// Capture inputs currently offered by the system (requires an active playAndRecord session).
    static func availableCaptureInputs(
        session: AVAudioSession = .sharedInstance()
    ) -> [AVAudioSessionPortDescription] {
        session.availableInputs ?? []
    }

    /// Lightweight discovery for the Settings picker: enable Bluetooth-capable category options
    /// so AirPods appear, read `availableInputs`, and update the cache.
    /// Does not deactivate first (avoids the multi-second gap where the picker only shows Automatic).
    static func discoverCaptureInputsAsync() async throws -> [CachedCaptureInput] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CachedCaptureInput], Error>) in
            sessionQueue.async {
                do {
                    let inputs = try discoverCaptureInputsOnSessionQueue()
                    continuation.resume(returning: inputs)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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

    // MARK: - Session-queue work

    private static func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private static func preferredInputUIDLocked() -> String? {
        withStateLock { _preferredInputUID }
    }

    private static func storeCachedCaptureInputs(_ inputs: [CachedCaptureInput]) {
        withStateLock { _cachedCaptureInputs = inputs }
    }

    private static func discoverCaptureInputsOnSessionQueue() throws -> [CachedCaptureInput] {
        let session = AVAudioSession.sharedInstance()
        let discoverOptions = bluetoothCapableOptions()

        // Always discover with Bluetooth allowed so paired HFP devices remain listable,
        // even when the sticky preference currently forces built-in capture.
        try session.setCategory(.playAndRecord, mode: .measurement, options: discoverOptions)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let ports = session.availableInputs ?? []
        let cached = ports.map(cachedCaptureInput(from:))
        storeCachedCaptureInputs(cached)

        // Restore preference-based capture options so listing does not leave HFP enabled
        // after the user forced a non-Bluetooth mic.
        let target = resolvedPreferredInput(among: ports)
        let captureOptions = categoryOptions(forResolvedInput: target)
        if captureOptions != discoverOptions {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playAndRecord, mode: .measurement, options: captureOptions)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        }
        if let target {
            setPreferredInput(target, session: session, log: nil)
        } else {
            clearPreferredInput(session: session, log: nil, reason: "discover: no known microphone")
        }

        return cached
    }

    private static func cachedCaptureInput(from port: AVAudioSessionPortDescription) -> CachedCaptureInput {
        CachedCaptureInput(
            uid: port.uid,
            portName: port.portName,
            portType: port.portType.rawValue
        )
    }

    private static func activateForCaptureOnSessionQueue(log: (@Sendable (String) -> Void)?) throws {
        let session = AVAudioSession.sharedInstance()

        // Phase 1: allow Bluetooth so AirPods appear in `availableInputs` for discovery / Automatic.
        let discoverOptions = bluetoothCapableOptions()
        try session.setCategory(.playAndRecord, mode: .measurement, options: discoverOptions)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputs = session.availableInputs ?? []
        storeCachedCaptureInputs(inputs.map(cachedCaptureInput(from:)))
        let target = resolvedPreferredInput(among: inputs)
        let captureOptions = categoryOptions(forResolvedInput: target)

        // Phase 2: if we are forcing a non-Bluetooth mic (e.g. built-in) while AirPods are
        // paired, drop HFP from the session. Otherwise input can look like Built-In while
        // HFP still owns the route and speech recognition receives no usable audio.
        if captureOptions != discoverOptions {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playAndRecord, mode: .measurement, options: captureOptions)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            log?(
                "audio session reconfigured for non-Bluetooth capture (options=\(captureOptions.rawValue))"
            )
        } else {
            log?(
                "audio session activated (category=playAndRecord, mode=measurement, options=\(captureOptions.rawValue))"
            )
        }

        if let target {
            setPreferredInput(target, session: session, log: log)
        } else {
            clearPreferredInput(session: session, log: log, reason: "no known microphone in availableInputs")
        }
    }

    private static func bluetoothCapableOptions() -> AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.duckOthers, .allowBluetoothHFP]
        if #available(iOS 26.0, *) {
            options.insert(.bluetoothHighQualityRecording)
        }
        return options
    }

    private static func categoryOptions(
        forResolvedInput input: AVAudioSessionPortDescription?
    ) -> AVAudioSession.CategoryOptions {
        if let input, isBluetoothPort(input) {
            return bluetoothCapableOptions()
        }

        let manualNonBluetooth: Bool = {
            guard let uid = preferredInputUIDLocked(), !uid.isEmpty else { return false }
            guard let input else { return true }
            return !isBluetoothPort(input)
        }()

        if manualNonBluetooth {
            // Keep HFP out of the route so built-in / wired capture actually works.
            return [.duckOthers, .defaultToSpeaker]
        }

        // Automatic (or unresolved): keep Bluetooth allowed.
        return bluetoothCapableOptions()
    }

    private static func resolvedPreferredInput(
        among inputs: [AVAudioSessionPortDescription]
    ) -> AVAudioSessionPortDescription? {
        let preferredUID = preferredInputUIDLocked()
        if let preferredUID, !preferredUID.isEmpty,
           let manual = inputs.first(where: { $0.uid == preferredUID }) {
            return manual
        }

        if let preferredUID, !preferredUID.isEmpty {
            // Sticky device missing — fall back to automatic for this activation.
        }

        if let bluetoothInput = inputs.first(where: isBluetoothPort) {
            return bluetoothInput
        }

        if let externalInput = inputs.first(where: {
            $0.portType == .headsetMic
                || $0.portType == .usbAudio
                || $0.portType == .carAudio
        }) {
            return externalInput
        }

        return inputs.first(where: { $0.portType == .builtInMic })
    }

    private static func isBluetoothPort(_ port: AVAudioSessionPortDescription) -> Bool {
        port.portType == .bluetoothHFP || port.portType == .bluetoothLE
    }

    private static func setPreferredInput(
        _ input: AVAudioSessionPortDescription,
        session: AVAudioSession,
        log: (@Sendable (String) -> Void)?
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
        log: (@Sendable (String) -> Void)?,
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
