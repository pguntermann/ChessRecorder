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
    @State private var isStarting = false

    var body: some View {
        Group {
            Button {
                toggleMicrophoneTest()
            } label: {
                HStack(spacing: 8) {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Starting test…")
                    } else {
                        Image(systemName: monitor.isMonitoring ? "stop.fill" : "mic")
                            .imageScale(.medium)
                            .frame(width: 20)
                        Text(monitor.isMonitoring ? "Stop microphone test" : "Test microphone")
                    }
                }
                .foregroundStyle(buttonForegroundColor)
            }
            .disabled(isStarting)
            .accessibilityLabel(
                isStarting
                    ? "Starting microphone test"
                    : (monitor.isMonitoring ? "Stop microphone test" : "Test microphone")
            )

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
            isStarting = false
            monitor.stop()
        }
    }

    private var buttonForegroundColor: Color {
        if isStarting {
            return .secondary
        }
        if monitor.isMonitoring {
            return .red
        }
        return .blue
    }

    private func toggleMicrophoneTest() {
        if monitor.isMonitoring {
            monitor.stop()
            isStarting = false
            return
        }

        guard !isStarting else { return }

        permissionDenied = false

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginMicrophoneTest()
        case .denied:
            permissionDenied = true
        case .undetermined:
            isStarting = true
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    if granted {
                        await runMicrophoneTestStartup()
                    } else {
                        permissionDenied = true
                        isStarting = false
                    }
                }
            }
        @unknown default:
            permissionDenied = true
        }
    }

    private func beginMicrophoneTest() {
        isStarting = true
        Task { @MainActor in
            await runMicrophoneTestStartup()
        }
    }

    @MainActor
    private func runMicrophoneTestStartup() async {
        defer { isStarting = false }

        onStopRecording()
        await Task.yield()

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
