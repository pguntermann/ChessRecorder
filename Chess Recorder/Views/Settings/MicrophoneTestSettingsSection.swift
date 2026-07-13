//
//  MicrophoneTestSettingsSection.swift
//  Chess Recorder
//

import AVFoundation
import SwiftUI

struct MicrophoneTestSettingsSection: View {
    let onStopRecording: () -> Void

    @State private var monitor = MicrophoneLevelMonitor()
    @State private var permissionDenied = false

    var body: some View {
        Group {
            Button(monitor.isMonitoring ? "Stop microphone test" : "Test microphone") {
                toggleMicrophoneTest()
            }

            if monitor.isMonitoring {
                HStack {
                    Text("Microphone")
                    Spacer()
                    Text(monitor.inputDeviceName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                MicrophoneLevelMeterView(
                    displayLevel: monitor.displayLevel,
                    meterPeakLevel: monitor.meterPeakLevel,
                    assessedQuality: monitor.assessedQuality
                )

                if let hint = monitor.qualityHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(hintColor(for: monitor.assessedQuality))
                } else {
                    Text("Speak normally to check your input level.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if permissionDenied {
                Text("Microphone access is required. Enable it in Settings to test input levels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            monitor.stop()
        }
    }

    private func toggleMicrophoneTest() {
        if monitor.isMonitoring {
            monitor.stop()
            return
        }

        permissionDenied = false

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .denied:
            permissionDenied = true
            return
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    if granted {
                        startMicrophoneTest()
                    } else {
                        permissionDenied = true
                    }
                }
            }
            return
        @unknown default:
            permissionDenied = true
            return
        }

        startMicrophoneTest()
    }

    private func startMicrophoneTest() {
        onStopRecording()
        do {
            try monitor.start()
        } catch {
            monitor.stop()
        }
    }

    private func hintColor(for quality: MicrophoneLevelQuality?) -> Color {
        switch quality {
        case .tooQuiet, .tooLoud:
            return .orange
        case .good:
            return .secondary
        case nil:
            return .secondary
        }
    }
}

private struct MicrophoneLevelMeterView: View {
    let displayLevel: Float
    let meterPeakLevel: Float
    let assessedQuality: MicrophoneLevelQuality?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))

                    Capsule()
                        .fill(meterColor)
                        .frame(width: geometry.size.width * CGFloat(displayLevel))

                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2)
                        .offset(x: max(0, geometry.size.width * CGFloat(min(meterPeakLevel, 1)) - 1))
                }
            }
            .frame(height: 10)
            .animation(.easeOut(duration: 0.1), value: displayLevel)
            .animation(.easeOut(duration: 0.15), value: meterPeakLevel)

            HStack {
                Text("Input level")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(qualityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone input level")
        .accessibilityValue(qualityLabel)
    }

    private var meterColor: Color {
        switch assessedQuality {
        case .tooQuiet, .tooLoud:
            return .orange
        case .good:
            return .green
        case nil:
            return .accentColor
        }
    }

    private var qualityLabel: String {
        assessedQuality?.shortLabel ?? "Listening"
    }
}
