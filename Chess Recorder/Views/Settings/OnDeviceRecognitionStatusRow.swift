//
//  OnDeviceRecognitionStatusRow.swift
//  Chess Recorder
//

import Speech
import SwiftUI

struct OnDeviceRecognitionStatusRow: View {
    let language: RecognitionLanguage
    /// Custom chess language model is ready for this language.
    var isLanguageModelReady: Bool = false
    /// Custom model preparation failed for this session (next cold boot may retry).
    var languageModelCompilationFailed: Bool = false

    @State private var supportsOnDevice: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("On-device recognition")
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(statusColor)
            }

            if let explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .task(id: language) {
            refreshStatus()
            // Apple can report false on the first read; re-check after assets resolve.
            try? await Task.sleep(for: .seconds(1.5))
            refreshStatus()
        }
    }

    private var displayState: DisplayState {
        if languageModelCompilationFailed {
            return .customModelUnavailable
        }
        switch supportsOnDevice {
        case true:
            return isLanguageModelReady ? .availableWithModel : .availableWithoutModel
        case false:
            return .unavailable
        case nil:
            return .checking
        }
    }

    private enum DisplayState {
        case checking
        case unavailable
        case customModelUnavailable
        case availableWithModel
        case availableWithoutModel
    }

    private var statusLabel: String {
        switch displayState {
        case .checking: "Checking…"
        case .unavailable, .customModelUnavailable: "Unavailable"
        case .availableWithModel, .availableWithoutModel: "Available"
        }
    }

    private var explanation: String? {
        switch displayState {
        case .checking:
            nil
        case .unavailable:
            "Recognition accuracy is limited. Cloud recognition does not support the custom chess language model. Download Dictation for \(language.displayName) in iOS Settings → General → Keyboard if available."
        case .customModelUnavailable:
            "The custom chess language model is not available. Speech recognition still works without it, but accuracy for chess terms is limited."
        case .availableWithModel:
            "The app uses on-device recognition for \(language.displayName), including the custom chess language model. No extra setup is required."
        case .availableWithoutModel:
            "On-device recognition is available for \(language.displayName). The custom chess language model is not active yet."
        }
    }

    private var statusColor: Color {
        switch displayState {
        case .checking: .secondary
        case .unavailable, .customModelUnavailable: .orange
        case .availableWithModel, .availableWithoutModel: .green
        }
    }

    private func refreshStatus() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
        supportsOnDevice = recognizer?.supportsOnDeviceRecognition == true
    }
}
