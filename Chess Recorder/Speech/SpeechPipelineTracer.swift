//
//  SpeechPipelineTracer.swift
//  Chess Recorder
//

import Foundation

/// Records each transformation from raw ASR through normalization to move candidates.
/// Only emits output when `isEnabled` is true (developer builds with tracing toggled on).
final class SpeechPipelineTracer {
    private struct Step {
        let section: String
        let stage: String
        let value: String
    }

    let isEnabled: Bool
    private var steps: [Step] = []

    init(enabled: Bool) {
        self.isEnabled = enabled
    }

    func record(_ section: String, _ stage: String, _ value: String) {
        guard isEnabled else { return }
        steps.append(Step(section: section, stage: stage, value: value))
    }

    @discardableResult
    func recordTransform(
        _ section: String,
        _ stage: String,
        _ input: String,
        transform: (String) -> String
    ) -> String {
        let output = transform(input)
        record(section, stage, output)
        return output
    }

    func printReport(
        language: RecognitionLanguage,
        acceptedMove: String? = nil,
        rejectedMoves: [String] = [],
        failureReason: String? = nil
    ) {
        guard isEnabled, !steps.isEmpty else { return }

        print("SpeechPipeline: ═══════════════════════════════════════")
        print("SpeechPipeline: Trace (\(language.displayName))")

        var currentSection = ""
        for (index, step) in steps.enumerated() {
            if step.section != currentSection {
                currentSection = step.section
                print("SpeechPipeline:")
                print("SpeechPipeline: [\(currentSection)]")
            }
            print("SpeechPipeline:   \(index + 1). \(step.stage): \"\(step.value)\"")
        }

        print("SpeechPipeline:")
        print("SpeechPipeline: [Outcome]")
        if let acceptedMove {
            print("SpeechPipeline:   Accepted: \(acceptedMove)")
        } else if let failureReason {
            print("SpeechPipeline:   Failed: \(failureReason)")
        } else {
            print("SpeechPipeline:   No move accepted")
        }
        if !rejectedMoves.isEmpty {
            print("SpeechPipeline:   Rejected: \(rejectedMoves.joined(separator: ", "))")
        }
        print("SpeechPipeline: ═══════════════════════════════════════")
    }
}
