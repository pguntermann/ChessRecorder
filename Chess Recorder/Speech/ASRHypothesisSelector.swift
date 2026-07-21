//
//  ASRHypothesisSelector.swift
//  Chess Recorder
//

import Foundation

/// Prefers chess-usable ASR text when Apple’s best hypothesis collapses to digit noise
/// or a letter + three-digit blob (e.g. `C554` instead of `C5D4`).
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

    /// Letter followed by three digits, e.g. `C554` / `C 5 5 4` — often a revised `C5D4`.
    static func isRejectableLetterTripleDigitHypothesis(_ text: String) -> Bool {
        let compact = alphanumerics(in: text)
        guard compact.count == 4 else { return false }
        let chars = Array(compact)
        return chars[0].isLetter
            && chars[1].isNumber
            && chars[2].isNumber
            && chars[3].isNumber
    }

    /// Compact from–to coordinates: letter-digit-letter-digit (`C5D4`, `c 5 d 4`).
    static func looksLikeCoordinatePair(_ text: String) -> Bool {
        let compact = alphanumerics(in: text)
        guard compact.count == 4 else { return false }
        let chars = Array(compact)
        return chars[0].isLetter
            && chars[1].isNumber
            && chars[2].isLetter
            && chars[3].isNumber
    }

    static func containsLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// Prefer a chess-usable hypothesis when `best` is digit-only noise or a letter+triple-digit blob.
    static func select(
        best: String,
        alternatives: [String],
        previousChessyPartial: String?
    ) -> Selection {
        if isRejectableDigitOnlyHypothesis(best) {
            return selectReplacement(
                for: best,
                alternatives: alternatives,
                previousChessyPartial: previousChessyPartial,
                isAcceptable: { text in
                    containsLetter(text) && !isRejectableDigitOnlyHypothesis(text)
                }
            )
        }

        if isRejectableLetterTripleDigitHypothesis(best) {
            return selectReplacement(
                for: best,
                alternatives: alternatives,
                previousChessyPartial: previousChessyPartial,
                isAcceptable: looksLikeCoordinatePair
            )
        }

        return Selection(text: best, replacedDigitOnlyBest: false)
    }

    // MARK: - Private

    private static func alphanumerics(in text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func selectReplacement(
        for best: String,
        alternatives: [String],
        previousChessyPartial: String?,
        isAcceptable: (String) -> Bool
    ) -> Selection {
        let trimmedBest = best.trimmingCharacters(in: .whitespacesAndNewlines)

        for alternative in alternatives {
            let trimmed = alternative.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isAcceptable(trimmed) else { continue }
            if trimmed.caseInsensitiveCompare(trimmedBest) == .orderedSame {
                continue
            }
            return Selection(text: trimmed, replacedDigitOnlyBest: true)
        }

        if let previous = previousChessyPartial?.trimmingCharacters(in: .whitespacesAndNewlines),
           !previous.isEmpty,
           isAcceptable(previous),
           previous.caseInsensitiveCompare(trimmedBest) != .orderedSame {
            return Selection(text: previous, replacedDigitOnlyBest: true)
        }

        return Selection(text: best, replacedDigitOnlyBest: false)
    }
}
