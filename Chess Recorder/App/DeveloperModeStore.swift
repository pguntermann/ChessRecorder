//
//  DeveloperModeStore.swift
//  Chess Recorder
//

import Foundation

@Observable
final class DeveloperModeStore {
    private enum Keys {
        static let screenshotModeEnabled = "screenshotModeEnabled"
        static let speechPipelineTracingEnabled = "speechPipelineTracingEnabled"
        static let speechRecognitionFailureDiagnosticsEnabled = "speechRecognitionFailureDiagnosticsEnabled"
        static let moveAssessmentTracingEnabled = "moveAssessmentTracingEnabled"
    }

    static var isAvailable: Bool {
        #if DEVELOPER_MODE
        return true
        #else
        return false
        #endif
    }

    var isScreenshotModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isScreenshotModeEnabled, forKey: Keys.screenshotModeEnabled)
        }
    }

    /// Logs each ASR → normalization → move-candidate step to the Xcode console.
    var isSpeechPipelineTracingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSpeechPipelineTracingEnabled, forKey: Keys.speechPipelineTracingEnabled)
        }
    }

    /// Logs expanded NSError + recognizer/request/audio context on recognition failures.
    var isSpeechRecognitionFailureDiagnosticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                isSpeechRecognitionFailureDiagnosticsEnabled,
                forKey: Keys.speechRecognitionFailureDiagnosticsEnabled
            )
        }
    }

    /// Logs move-assessment enqueue / book / engine / apply / failure events to the console.
    var isMoveAssessmentTracingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                isMoveAssessmentTracingEnabled,
                forKey: Keys.moveAssessmentTracingEnabled
            )
        }
    }

    var showsDeveloperSettings: Bool {
        Self.isAvailable
    }

    var hidesStatusBar: Bool {
        Self.isAvailable && isScreenshotModeEnabled
    }

    init() {
        isScreenshotModeEnabled = UserDefaults.standard.bool(forKey: Keys.screenshotModeEnabled)
        if UserDefaults.standard.object(forKey: Keys.speechPipelineTracingEnabled) == nil {
            isSpeechPipelineTracingEnabled = true
        } else {
            isSpeechPipelineTracingEnabled = UserDefaults.standard.bool(forKey: Keys.speechPipelineTracingEnabled)
        }
        isSpeechRecognitionFailureDiagnosticsEnabled = UserDefaults.standard.bool(
            forKey: Keys.speechRecognitionFailureDiagnosticsEnabled
        )
        isMoveAssessmentTracingEnabled = UserDefaults.standard.bool(
            forKey: Keys.moveAssessmentTracingEnabled
        )
    }
}
