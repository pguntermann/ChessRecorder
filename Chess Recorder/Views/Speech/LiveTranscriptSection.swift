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

/// Countdown label follows the processing deadline; the bar uses one linear animation per pause cycle.
private struct DictationPauseIndicator: View {
    let deadline: Date?
    let duration: TimeInterval
    let isActive: Bool

    @State private var barProgress: CGFloat = 0

    private static let reservedHeight: CGFloat = 28
    private static let labelRefreshInterval: TimeInterval = 0.1

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.labelRefreshInterval, paused: !isActive)) { timeline in
            indicatorContent(
                remaining: remainingSeconds(at: timeline.date),
                barProgress: barProgress
            )
        }
        .frame(height: Self.reservedHeight, alignment: .top)
        .padding(.top, 4)
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Interpreting move")
        .accessibilityValue(accessibilityValue(at: Date()))
        .accessibilityHidden(!isActive)
        .onChange(of: pauseCycleKey) { _, _ in
            restartBarAnimation()
        }
        .onAppear {
            restartBarAnimation()
        }
    }

    private var pauseCycleKey: String {
        guard isActive, let deadline else { return "inactive" }
        return "\(deadline.timeIntervalSinceReferenceDate)-\(duration)"
    }

    private func remainingSeconds(at date: Date) -> TimeInterval {
        guard isActive, let deadline, duration > 0 else { return 0 }
        return max(0, deadline.timeIntervalSince(date))
    }

    private func accessibilityValue(at date: Date) -> String {
        guard isActive else { return "" }
        return String(format: "%.1f seconds remaining", remainingSeconds(at: date))
    }

    private func displayedRemainingSeconds(_ remaining: TimeInterval) -> TimeInterval {
        (remaining * 10).rounded(.down) / 10
    }

    @ViewBuilder
    private func indicatorContent(remaining: TimeInterval, barProgress: CGFloat) -> some View {
        let displayedRemaining = displayedRemainingSeconds(remaining)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Interpreting in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f s", displayedRemaining))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }

            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .scaleEffect(x: min(max(barProgress, 0), 1), y: 1, anchor: .leading)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 4)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func restartBarAnimation() {
        guard isActive, let deadline, duration > 0 else {
            barProgress = 0
            return
        }

        let remaining = max(0, deadline.timeIntervalSinceNow)
        guard remaining > 0 else {
            barProgress = 0
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            barProgress = min(1, CGFloat(remaining / duration))
        }

        withAnimation(.linear(duration: remaining)) {
            barProgress = 0
        }
    }
}
