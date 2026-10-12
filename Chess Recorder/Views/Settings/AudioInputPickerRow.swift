//
//  AudioInputPickerRow.swift
//  Chess Recorder
//

import AVFoundation
import SwiftUI

/// Settings control for Automatic vs a specific capture input.
struct AudioInputPickerRow: View {
    @Bindable var settingsStore: SettingsStore
    let onStopRecording: () -> Void
    var onInputChanged: (() -> Void)? = nil

    @State private var availableInputs: [CaptureInputOption] = []
    @State private var activeAutomaticInputLabel: String?
    @State private var refreshFailed = false
    @State private var refreshTask: Task<Void, Never>?

    private static let automaticSelectionID = ""

    private var isAutomatic: Bool {
        settingsStore.settings.preferredAudioInputUID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Microphone", selection: selectionBinding) {
                Text(automaticPickerLabel).tag(Self.automaticSelectionID)
                ForEach(availableInputs) { input in
                    Text(input.label).tag(input.id)
                }
                if let orphan = orphanManualSelection {
                    Text(orphan.label).tag(orphan.id)
                }
            }
            .accessibilityLabel(
                isAutomatic
                    ? (activeAutomaticInputLabel.map { "Microphone Automatic using \($0)" } ?? "Microphone Automatic")
                    : "Microphone"
            )

            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            seedFromCache()
            scheduleRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
        .onChange(of: settingsStore.settings.preferredAudioInputUID) { _, _ in
            refreshActiveAutomaticInputLabel()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            scheduleRefresh()
        }
    }

    private var automaticPickerLabel: String {
        if let activeAutomaticInputLabel {
            return "Automatic — \(activeAutomaticInputLabel)"
        }
        return "Automatic"
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.preferredAudioInputUID },
            set: { newValue in
                // Keep this setter instant: session rebuild runs off the main thread via
                // ContentView.onChange(preferredAudioInputUID).
                settingsStore.update { $0.preferredAudioInputUID = newValue }
                if !newValue.isEmpty {
                    activeAutomaticInputLabel = nil
                }
                onStopRecording()
                onInputChanged?()
            }
        )
    }

    private var orphanManualSelection: CaptureInputOption? {
        let uid = settingsStore.settings.preferredAudioInputUID
        guard !uid.isEmpty, !availableInputs.contains(where: { $0.id == uid }) else { return nil }
        return CaptureInputOption(
            id: uid,
            label: "Unavailable device",
            portType: ""
        )
    }

    private var footerText: String {
        if refreshFailed {
            return "Could not list microphones. Grant microphone access, then reopen Settings."
        }
        if isAutomatic {
            return "Automatic prefers a Bluetooth or headset mic when available, otherwise the built-in mic."
        }
        return "If the selected microphone disconnects, Chess Recorder falls back to Automatic until it returns."
    }

    private func seedFromCache() {
        let cached = RecordingAudioSession.cachedCaptureInputs
        guard !cached.isEmpty else { return }
        availableInputs = cached.map(Self.option(from:))
        refreshActiveAutomaticInputLabel()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await refreshAvailableInputs()
        }
    }

    @MainActor
    private func refreshAvailableInputs() async {
        refreshFailed = false
        do {
            let inputs = try await RecordingAudioSession.discoverCaptureInputsAsync()
            guard !Task.isCancelled else { return }
            availableInputs = inputs.map(Self.option(from:))
            refreshActiveAutomaticInputLabel()
        } catch {
            guard !Task.isCancelled else { return }
            if availableInputs.isEmpty {
                refreshFailed = true
                activeAutomaticInputLabel = nil
            }
        }
    }

    private func refreshActiveAutomaticInputLabel() {
        guard isAutomatic else {
            activeAutomaticInputLabel = nil
            return
        }

        if let routeInput = AVAudioSession.sharedInstance().currentRoute.inputs.first {
            activeAutomaticInputLabel = Self.displayName(
                portName: routeInput.portName,
                portType: routeInput.portType.rawValue
            )
            return
        }

        if let preferred = AVAudioSession.sharedInstance().preferredInput {
            activeAutomaticInputLabel = Self.displayName(
                portName: preferred.portName,
                portType: preferred.portType.rawValue
            )
            return
        }

        let fallback = RecordingAudioSession.activeCaptureInputDisplayName()
        activeAutomaticInputLabel = fallback.isEmpty ? nil : fallback
    }

    private static func option(from cached: RecordingAudioSession.CachedCaptureInput) -> CaptureInputOption {
        CaptureInputOption(
            id: cached.uid,
            label: displayName(portName: cached.portName, portType: cached.portType),
            portType: cached.portType
        )
    }

    private static func displayName(portName: String, portType: String) -> String {
        let typeLabel: String
        switch AVAudioSession.Port(rawValue: portType) {
        case .bluetoothHFP, .bluetoothLE:
            typeLabel = "Bluetooth"
        case .builtInMic:
            typeLabel = "Built-in"
        case .headsetMic:
            typeLabel = "Headset"
        case .usbAudio:
            typeLabel = "USB"
        case .carAudio:
            typeLabel = "Car"
        default:
            typeLabel = portType
        }
        return "\(portName) (\(typeLabel))"
    }
}

private struct CaptureInputOption: Identifiable, Hashable {
    let id: String
    let label: String
    let portType: String
}
