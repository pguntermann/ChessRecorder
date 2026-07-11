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
    }
}
