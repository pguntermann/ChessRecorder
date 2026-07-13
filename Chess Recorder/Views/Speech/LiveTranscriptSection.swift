//
//  LiveTranscriptSection.swift
//  Chess Recorder
//

import SwiftUI

/// Observes only live speech UI state so transcript/timer updates do not redraw the board or PGN.
struct LiveTranscriptSection: View {
    @Bindable var speechRecognizer: SpeechRecognizer
    var onTeachPhrase: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Transcript")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(displayTranscript)
                .font(.caption)
                .foregroundStyle(speechRecognizer.transcript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: speechRecognizer.transcript)

            DictationPauseIndicator(
                deadline: speechRecognizer.dictationPauseDeadline,
                duration: speechRecognizer.dictationPauseDuration,
                isActive: speechRecognizer.isRecording
                    && speechRecognizer.dictationPauseDeadline != nil
                    && speechRecognizer.dictationPauseDuration > 0
                    && !speechRecognizer.transcript.isEmpty
            )

            if let pendingFailure = speechRecognizer.pendingFailure {
                LiveTranscriptFailureView(
                    pendingFailure: pendingFailure,
                    onTeachPhrase: onTeachPhrase,
                    onDismiss: { speechRecognizer.clearPendingFailure() }
                )
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    private var displayTranscript: String {
        if !speechRecognizer.transcript.isEmpty {
            return speechRecognizer.transcript
        }
        if speechRecognizer.isRebuildingLanguageModel {
            return "Updating speech model…"
        }
        return speechRecognizer.isRecording ? "Listening..." : "Tap Record to start"
    }
}

private struct LiveTranscriptFailureView: View {
    let pendingFailure: RecognitionFailureContext
    var onTeachPhrase: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't find a valid move for what was heard.")
                .font(.caption)
                .foregroundStyle(.orange)

            HStack {
                Button("Teach phrase") {
                    onTeachPhrase?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !pendingFailure.attemptedMoves.isEmpty {
                Text("Tried: \(pendingFailure.attemptedMoves.joined(separator: ", "))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

/// Smooth countdown driven by a single linear animation instead of 60 Hz layout passes.
private struct DictationPauseIndicator: View {
    let deadline: Date?
    let duration: TimeInterval
    let isActive: Bool

    @State private var progress: CGFloat = 0

    private static let reservedHeight: CGFloat = 28

    var body: some View {
        indicatorContent
            .frame(height: Self.reservedHeight, alignment: .top)
            .padding(.top, 4)
            .opacity(isActive ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isActive)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Interpreting move")
            .accessibilityValue(accessibilityValue)
            .accessibilityHidden(!isActive)
            .onChange(of: pauseCycleKey) { _, _ in
                restartAnimation()
            }
            .onAppear {
                restartAnimation()
            }
    }

    private var pauseCycleKey: String {
        guard isActive, let deadline else { return "inactive" }
        return "\(deadline.timeIntervalSinceReferenceDate)-\(duration)"
    }

    private var remaining: TimeInterval {
        guard isActive, duration > 0 else { return 0 }
        return max(0, progress * duration)
    }

    private var accessibilityValue: String {
        guard isActive else { return "" }
        return String(format: "%.1f seconds remaining", remaining)
    }

    @ViewBuilder
    private var indicatorContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Interpreting in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f s", remaining))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: remaining)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)
        }
    }

    private func restartAnimation() {
        guard isActive, let deadline, duration > 0 else {
            progress = 0
            return
        }

        let remainingDuration = max(0, deadline.timeIntervalSinceNow)
        guard remainingDuration > 0 else {
            progress = 0
            return
        }

        let startProgress = CGFloat(remainingDuration / duration)
        progress = startProgress
        withAnimation(.linear(duration: remainingDuration)) {
            progress = 0
        }
    }
}
