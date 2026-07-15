//
//  OnDeviceRecognitionStatusRow.swift
//  Chess Recorder
//

import Speech
import SwiftUI

struct OnDeviceRecognitionStatusRow: View {
    let language: RecognitionLanguage

    @State private var supportsOnDevice: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("On-device recognition")
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(statusColor)
            }

            if supportsOnDevice == false {
                Text(
                    "Recognition accuracy is limited. Cloud recognition does not support the custom chess language model. Download Dictation for \(language.displayName) in iOS Settings → General → Keyboard if available."
                )
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

    private var statusLabel: String {
        switch supportsOnDevice {
        case true: "Available"
        case false: "Unavailable"
        case nil: "Checking…"
        }
    }

    private var statusColor: Color {
        switch supportsOnDevice {
        case true: .secondary
        case false: .orange
        case nil: .secondary
        }
    }

    private func refreshStatus() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
        supportsOnDevice = recognizer?.supportsOnDeviceRecognition == true
    }
}
