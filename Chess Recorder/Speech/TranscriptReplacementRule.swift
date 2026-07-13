//
//  TranscriptReplacementRule.swift
//  Chess Recorder
//

import Foundation

enum TranscriptReplacementStage: CaseIterable {
  /// First-pass locale rules inside `normalize()`.
  case locale
  /// Rules applied during `normalizeForPhraseMatching()` after shared transforms.
  case phraseMatching
  /// Subset applied to raw ASR text before capture stabilization.
  case rawASR
}

struct TranscriptReplacementRule: Identifiable {
  let id: String
  let pattern: String
  let replacement: String
}

enum TranscriptReplacementEngine {
  static func apply(
    _ text: String,
    rules: [TranscriptReplacementRule],
    tracer: SpeechPipelineTracer? = nil,
    stageLabel: String? = nil
  ) -> String {
    rules.reduce(text) { current, rule in
      let updated = current.replacingOccurrences(
        of: rule.pattern,
        with: rule.replacement,
        options: .regularExpression
      )
      if updated != current, let tracer, let stageLabel {
        tracer.record("Normalization", "\(stageLabel): \(rule.id)", updated)
      }
      return updated
    }
  }

  static func apply(
    _ text: String,
    language: RecognitionLanguage,
    stages: [TranscriptReplacementStage],
    tracer: SpeechPipelineTracer? = nil
  ) -> String {
    stages.reduce(text) { current, stage in
      let rules = TranscriptReplacementRules.rules(for: language, stage: stage)
      let label = stageLabel(for: stage, language: language)
      return apply(current, rules: rules, tracer: tracer, stageLabel: label)
    }
  }

  private static func stageLabel(
    for stage: TranscriptReplacementStage,
    language: RecognitionLanguage
  ) -> String {
    switch stage {
    case .locale:
      return "\(language.displayName) locale"
    case .phraseMatching:
      return "\(language.displayName) phrase matching"
    case .rawASR:
      return "\(language.displayName) raw ASR"
    }
  }
}
