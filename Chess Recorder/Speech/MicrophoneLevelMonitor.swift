//
//  MicrophoneLevelMonitor.swift
//  Chess Recorder
//

import AVFoundation
import Foundation

enum MicrophoneLevelQuality: Equatable {
    case tooQuiet
    case good
    case tooLoud

    var hint: String {
        switch self {
        case .tooQuiet:
            return "Too quiet — move closer to the microphone."
        case .good:
            return "Good input level for speech."
        case .tooLoud:
            return "Very loud — step back slightly to avoid clipping."
        }
    }

    var shortLabel: String {
        switch self {
        case .tooQuiet:
            return "Too quiet"
        case .good:
            return "Good"
        case .tooLoud:
            return "Too loud"
        }
    }
}

@Observable
@MainActor
final class MicrophoneLevelMonitor {
    private(set) var inputDeviceName = ""
    /// Smoothed level for the live meter bar.
    private(set) var displayLevel: Float = 0
    /// Peak marker on the meter; falls slowly when level drops.
    private(set) var meterPeakLevel: Float = 0
    private(set) var isMonitoring = false
    /// Quality assessment based on session peaks, not the live meter level.
    private(set) var assessedQuality: MicrophoneLevelQuality?

    private var audioEngine: AVAudioEngine?
    private var routeObserverToken: NSObjectProtocol?
    private var routeChangeRecoveryTask: Task<Void, Never>?
    private var didRefreshInputAfterCapture = false
    private var sessionPeakRMS: Float = 0
    private var sessionPeakAmplitude: Float = 0

    var qualityHint: String? {
        assessedQuality?.hint
    }

    func start() throws {
        guard !isMonitoring else { return }

        resetLevels()
        try startAudioCapture()
        isMonitoring = true
        installRouteObserver()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard isMonitoring else { return }
            refreshInputDeviceName()
        }
    }

    func stop() {
        guard isMonitoring else { return }

        routeChangeRecoveryTask?.cancel()
        routeChangeRecoveryTask = nil
        removeRouteObserver()
        stopAudioCapture()
        isMonitoring = false
        inputDeviceName = ""
        didRefreshInputAfterCapture = false
        resetLevels()
    }

    private func startAudioCapture(reactivating: Bool = false) throws {
        if reactivating {
            try RecordingAudioSession.reactivateForCapture()
        } else {
            try RecordingAudioSession.activateForCapture()
        }

        let engine = AVAudioEngine()

        RecordingAudioSession.installInputTap(on: engine) { [weak self] buffer, _ in
            guard let metrics = AudioPCMBufferLevel.analyze(buffer) else { return }
            Task { @MainActor in
                self?.ingest(metrics)
            }
        }

        try engine.start()
        audioEngine = engine
        refreshInputDeviceName()
    }

    private func stopAudioCapture() {
        guard let engine = audioEngine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    private func scheduleCaptureRestart(from notification: Notification) {
        guard Self.shouldRecoverFromRouteChange(from: notification) else {
            refreshInputDeviceName()
            return
        }

        refreshInputDeviceName()

        routeChangeRecoveryTask?.cancel()
        routeChangeRecoveryTask = Task { @MainActor in
            // Debounce so chained route notifications settle before we rebuild capture.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, isMonitoring else { return }
            await performCaptureRestart()
        }
    }

    private func performCaptureRestart(attempt: Int = 0) async {
        guard isMonitoring else { return }

        displayLevel = 0
        meterPeakLevel = 0
        didRefreshInputAfterCapture = false
        stopAudioCapture()

        do {
            try startAudioCapture(reactivating: true)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard isMonitoring else { return }
                refreshInputDeviceName()
            }
        } catch {
            guard attempt < 4, isMonitoring else { return }
            try? await Task.sleep(for: .milliseconds(300 * (attempt + 1)))
            guard !Task.isCancelled, isMonitoring else { return }
            await performCaptureRestart(attempt: attempt + 1)
        }
    }

    private func refreshInputDeviceName() {
        inputDeviceName = RecordingAudioSession.activeCaptureInputDisplayName()
    }

    private func resetLevels() {
        displayLevel = 0
        meterPeakLevel = 0
        sessionPeakRMS = 0
        sessionPeakAmplitude = 0
        assessedQuality = nil
    }

    private func ingest(_ metrics: AudioPCMBufferLevel.Metrics) {
        if !didRefreshInputAfterCapture {
            didRefreshInputAfterCapture = true
            refreshInputDeviceName()
        }

        if metrics.displayLevel > displayLevel {
            displayLevel = displayLevel * 0.25 + metrics.displayLevel * 0.75
        } else {
            displayLevel = displayLevel * 0.9 + metrics.displayLevel * 0.1
        }

        meterPeakLevel = max(meterPeakLevel * 0.992, metrics.displayLevel)

        if metrics.rms > sessionPeakRMS {
            sessionPeakRMS = metrics.rms
        }
        if metrics.peakAmplitude > sessionPeakAmplitude {
            sessionPeakAmplitude = metrics.peakAmplitude
        }

        assessedQuality = Self.quality(peakRMS: sessionPeakRMS, peakAmplitude: sessionPeakAmplitude)
    }

    private enum LevelThreshold {
        /// Roughly -50 dBFS; between built-in mic sensitivity and genuinely too-quiet speech.
        static let tooQuietRMS: Float = 0.003
        /// Minimum RMS before showing an assessment (filters silence).
        static let speechPresentRMS: Float = 0.001
        /// Peak sample amplitude near digital full scale — clipping territory.
        static let tooLoudPeak: Float = 0.95
    }

    private static func quality(peakRMS: Float, peakAmplitude: Float) -> MicrophoneLevelQuality? {
        guard peakRMS >= LevelThreshold.speechPresentRMS else { return nil }

        if peakAmplitude >= LevelThreshold.tooLoudPeak {
            return .tooLoud
        }
        if peakRMS < LevelThreshold.tooQuietRMS {
            return .tooQuiet
        }
        return .good
    }

    private func installRouteObserver() {
        removeRouteObserver()
        routeObserverToken = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.isMonitoring else { return }
                self.scheduleCaptureRestart(from: notification)
            }
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

    private func removeRouteObserver() {
        if let routeObserverToken {
            NotificationCenter.default.removeObserver(routeObserverToken)
            self.routeObserverToken = nil
        }
    }
}
