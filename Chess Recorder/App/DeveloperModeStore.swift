//
//  DeveloperModeStore.swift
//  Chess Recorder
//

import Foundation

@Observable
final class DeveloperModeStore {
    private enum Keys {
        static let screenshotModeEnabled = "screenshotModeEnabled"
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

    var showsDeveloperSettings: Bool {
        Self.isAvailable
    }

    var hidesStatusBar: Bool {
        Self.isAvailable && isScreenshotModeEnabled
    }

    init() {
        isScreenshotModeEnabled = UserDefaults.standard.bool(forKey: Keys.screenshotModeEnabled)
    }
}
