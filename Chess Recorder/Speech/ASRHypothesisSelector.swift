//
//  ASRHypothesisSelector.swift
//  Chess Recorder
//

import Foundation

/// Prefers chess-usable ASR text when Apple’s best hypothesis collapses to digit noise.
enum ASRHypothesisSelector {
    struct Selection: Equatable {
        let text: String
        /// True when `text` came from N-best or a prior partial instead of `best`.
        let replacedDigitOnlyBest: Bool
    }

    /// Multi-digit, letters-free hypotheses like "986" / "9 8 6" — not a chess move on their own.
    static func isRejectableDigitOnlyHypothesis(_ text: String) -> Bool {
        let trimmed = text
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let withoutSpaces = trimmed.filter { !$0.isWhitespace }
        guard !withoutSpaces.isEmpty, withoutSpaces.allSatisfy(\.isNumber) else { return false }
        // Keep a lone rank digit ("4") as in-progress speech; reject "86", "986", …
        return withoutSpaces.count >= 2
    }

    static func containsLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// When `best` is digit-only noise, prefer a letter-containing N-best entry, else the last
    /// chessy partial from this utterance.
    static func select(
        best: String,
        alternatives: [String],
        previousChessyPartial: String?
    ) -> Selection {
        guard isRejectableDigitOnlyHypothesis(best) else {
            return Selection(text: best, replacedDigitOnlyBest: false)
        }

        for alternative in alternatives {
            let trimmed = alternative.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isRejectableDigitOnlyHypothesis(trimmed), containsLetter(trimmed) else {
                continue
            }
            // Skip duplicates of best.
            if trimmed.caseInsensitiveCompare(best.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                continue
            }
            return Selection(text: trimmed, replacedDigitOnlyBest: true)
        }

        if let previous = previousChessyPartial?.trimmingCharacters(in: .whitespacesAndNewlines),
           !previous.isEmpty,
           containsLetter(previous),
           !isRejectableDigitOnlyHypothesis(previous) {
            return Selection(text: previous, replacedDigitOnlyBest: true)
        }

        return Selection(text: best, replacedDigitOnlyBest: false)
    }
}
