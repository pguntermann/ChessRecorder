//
//  ChessTranscriptNormalizer.swift
//  Chess Recorder
//
//  Fallback corrections when the custom language model is unavailable
//  or the recognizer still mishears domain phrases.
//

import Foundation

enum ChessTranscriptNormalizer {

    // MARK: - Public API (facade over lexicon + rule engine)

    static let ambiguousEnglishFileTokens: Set<String> =
        ChessSpeechLexicon.lexicon(for: .english).ambiguousFileTokens

    static func isAmbiguousEnglishFileToken(_ token: String) -> Bool {
        ChessSpeechLexicon.isAmbiguousEnglishFileToken(token)
    }

    static func isAmbiguousEnglishFileRankUtterance(_ words: [String]) -> Bool {
        ChessSpeechLexicon.isAmbiguousEnglishFileRankUtterance(words)
    }

    static func spokenFileLetter(for token: String, language: RecognitionLanguage) -> Character? {
        ChessSpeechLexicon.spokenFileLetter(for: token, language: language)
    }

    static func spokenRankDigit(for token: String, language: RecognitionLanguage) -> String? {
        ChessSpeechLexicon.spokenRankDigit(for: token, language: language)
    }

    static func normalizeSpokenRankToken(_ token: String, language: RecognitionLanguage) -> String {
        ChessSpeechLexicon.normalizeSpokenRankToken(token, language: language)
    }

    static func repairGermanAFileMishearings(in text: String) -> String {
        var prepared = text
            .precomposedStringWithCanonicalMapping
            .lowercased()
        prepared = normalizeUnicode(prepared)
        return TranscriptReplacementEngine.apply(
            prepared,
            language: .german,
            stages: [.rawASR]
        )
    }

    static func englishPieceMoveMishearingPatterns() -> [(String, String)] {
        TranscriptReplacementRules.rules(for: .english, stage: .phraseMatching)
            .filter { $0.id.hasPrefix("en.piece-") || $0.id.hasPrefix("en.look-at") }
            .map { ($0.pattern, $0.replacement) }
    }

    static func englishDetectsMishearingPatterns() -> [(String, String)] {
        TranscriptReplacementRules.rules(for: .english, stage: .phraseMatching)
            .filter { $0.id.hasPrefix("en.detect") || $0.id == "en.d-e-takes" }
            .map { ($0.pattern, $0.replacement) }
    }

    static func englishPawnCaptureBoostPhrases(
        fileCount: Int = 450,
        misheardCount: Int = 420
    ) -> [(phrase: String, count: Int)] {
        pawnCaptureBoostPhrases(
            for: .english,
            fileCount: fileCount,
            misheardCount: misheardCount
        )
    }

    static func germanPawnCaptureBoostPhrases(
        fileCount: Int = 450,
        misheardCount: Int = 420
    ) -> [(phrase: String, count: Int)] {
        pawnCaptureBoostPhrases(
            for: .german,
            fileCount: fileCount,
            misheardCount: misheardCount
        )
    }

    // MARK: - Normalization pipeline

    static func normalize(
        _ text: String,
        language: RecognitionLanguage,
        tracer: SpeechPipelineTracer? = nil
    ) -> String {
        var result = text
            .precomposedStringWithCanonicalMapping
            .lowercased()

        result = normalizeUnicode(result)
        tracer?.record("Normalization", "Unicode fold", result)

        result = TranscriptReplacementEngine.apply(
            result,
            language: language,
            stages: [.locale],
            tracer: tracer
        )
        tracer?.record("Normalization", "\(language.displayName) locale rules", result)

        return result
    }

    static func normalizeForPhraseMatching(
        _ text: String,
        language: RecognitionLanguage,
        tracer: SpeechPipelineTracer? = nil
    ) -> String {
        tracer?.record("Normalization", "Input", text)
        var result = normalize(text, language: language, tracer: tracer)

        result = result
            .replacingOccurrences(of: "0-0-0", with: "o-o-o")
            .replacingOccurrences(of: "0-0", with: "o-o")
        tracer?.record("Normalization", "Castling digit fix", result)

        result = applySpokenFileHomophoneSpacing(result, language: language)
        tracer?.record("Normalization", "Spoken file homophones", result)

        result = tracer?.recordTransform("Normalization", "File before destination square", result) {
            resolveSpokenFileBeforeDestinationSquare(in: $0, language: language)
        } ?? resolveSpokenFileBeforeDestinationSquare(in: result, language: language)

        result = tracer?.recordTransform("Normalization", "Spoken file + rank phrases", result) {
            fixSpokenFileRankPhrases(in: $0, language: language)
        } ?? fixSpokenFileRankPhrases(in: result, language: language)

        result = tracer?.recordTransform("Normalization", "Article as capture verb", result) {
            inferArticleAsCaptureVerb(in: $0, language: language)
        } ?? inferArticleAsCaptureVerb(in: result, language: language)

        result = tracer?.recordTransform("Normalization", "Strip spoken articles", result) {
            stripSpokenArticles(from: $0, language: language)
        } ?? stripSpokenArticles(from: result, language: language)

        result = TranscriptReplacementEngine.apply(
            result,
            language: language,
            stages: [.phraseMatching],
            tracer: tracer
        )

        result = tracer?.recordTransform("Normalization", "Split square repair", result) {
            fixMisheardSplitSquares(in: $0, language: language)
        } ?? fixMisheardSplitSquares(in: result, language: language)

        result = tracer?.recordTransform("Normalization", "Strip check annotations", result) {
            stripSpokenCheckAnnotations(from: $0, language: language)
        } ?? stripSpokenCheckAnnotations(from: result, language: language)

        result = normalizeSpokenRanksToDigits(result, language: language, tracer: tracer)

        result = tracer?.recordTransform("Normalization", "Dropped pawn capture inference", result) {
            inferDroppedPawnCapture(in: $0, language: language)
        } ?? inferDroppedPawnCapture(in: result, language: language)

        result = result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        tracer?.record("Normalization", "Final normalized transcript", result)
        return result
    }

    /// Normalizes a two-character square token, including digit-file mishearings (8→a).
    static func normalizeSquareToken(_ token: String) -> String? {
        let cleaned = token
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == 2,
              let rank = cleaned.last,
              "12345678".contains(rank) else {
            return nil
        }

        var file = cleaned.first!
        if file.isNumber {
            guard file == "8" else { return nil }
            file = "a"
        }
        guard ChessSpeechLexicon.files.contains(String(file)) else { return nil }
        return String(file) + String(rank)
    }

    static func stripSpokenArticles(from text: String, language: RecognitionLanguage) -> String {
        let lexicon = ChessSpeechLexicon.lexicon(for: language)
        switch language {
        case .english:
            let homophones = lexicon.spokenFileLetters.keys
                .sorted { $0.count > $1.count }
                .joined(separator: "|")
            let ambiguous = lexicon.ambiguousFileTokens.sorted().joined(separator: "|")
            return applyRegexReplacements(text, patterns: [
                (#"\b(the|an)\s+"#, ""),
                (#"\s+\b(the|an)\b"#, ""),
                (#"\ba\s+(?=[a-h][1-8]\b)"#, ""),
                (#"\ba\s+(?=(?:\#(homophones)|\#(ambiguous))\s+(?:\#(lexicon.rankPattern)))"#, "")
            ])
        case .german:
            return applyRegexReplacements(text, patterns: [
                (#"\b(der|das|ein|eine)\s+(?=[a-h][1-8]\b)"#, ""),
                (#"\b(der|das|ein|eine)\s+(?=[a-h]\s+(?:\#(lexicon.rankPattern)))"#, ""),
                (#"\bdie\s+(?=[a-h][1-8]\b)"#, ""),
                (#"\bdie\s+(?=[a-h]\s+(?:\#(lexicon.rankPattern)))"#, "")
            ])
        }
    }

    static func stripSpokenCheckAnnotations(from text: String, language: RecognitionLanguage) -> String {
        let patterns: [(String, String)]
        switch language {
        case .english:
            patterns = [
                (#"\s+checkmate\b"#, ""),
                (#"\s+check\s+mate\b"#, ""),
                (#"\s+check\b"#, ""),
                (#"\s+mate\b"#, "")
            ]
        case .german:
            patterns = [
                (#"\s+schachmatt\b"#, ""),
                (#"\s+schach\s+matt\b"#, ""),
                (#"\s+schach\b"#, ""),
                (#"\s+matt\b"#, "")
            ]
        }

        var result = applyRegexReplacements(text, patterns: patterns)
        while result.last == "+" || result.last == "#" {
            result.removeLast()
        }
        return result
    }

    // MARK: - Private helpers

    private static func normalizeUnicode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ß", with: "ss")
    }

    private static func applySpokenFileHomophoneSpacing(
        _ text: String,
        language: RecognitionLanguage
    ) -> String {
        let lexicon = ChessSpeechLexicon.lexicon(for: language)
        return lexicon.spokenFileHomophoneSpacingReplacements().reduce(text) { current, pair in
            current.replacingOccurrences(of: pair.0, with: pair.1)
        }
    }

    private static func normalizeSpokenRanksToDigits(
        _ text: String,
        language: RecognitionLanguage,
        tracer: SpeechPipelineTracer?
    ) -> String {
        let lexicon = ChessSpeechLexicon.lexicon(for: language)
        let replacements = lexicon.spokenRanks.map { spoken -> (String, String) in
            let digit = ChessSpeechLexicon.normalizeSpokenRankToken(spoken, language: language)
            return (spoken, digit)
        }
        let result = replacements.reduce(text) { current, pair in
            current.replacingOccurrences(of: pair.0, with: pair.1)
        }
        tracer?.record("Normalization", "\(language.displayName) spoken numbers", result)
        return result
    }

    private static func pawnCaptureBoostPhrases(
        for language: RecognitionLanguage,
        fileCount: Int,
        misheardCount: Int
    ) -> [(phrase: String, count: Int)] {
        let lexicon = ChessSpeechLexicon.lexicon(for: language)
        let misheardFiles = Dictionary(grouping: lexicon.spokenFileLetters, by: \.value)
            .mapValues { pairs in pairs.map(\.key) }

        var phrases: [(String, Int)] = []
        for file in ChessSpeechLexicon.files {
            for verb in lexicon.captureVerbs {
                phrases.append((file + " " + verb, fileCount))
            }
        }
        for (_, mishears) in misheardFiles {
            for mishear in mishears {
                for verb in lexicon.captureVerbs {
                    phrases.append((mishear + " " + verb, misheardCount))
                }
            }
        }
        return phrases
    }

    private static func fixSpokenFileRankPhrases(in text: String, language: RecognitionLanguage) -> String {
        let lexicon = ChessSpeechLexicon.lexicon(for: language)
        let rankToken = lexicon.rankPattern
        let mappings = lexicon.spokenFilePatternGroups()

        var result = text
        for (filePattern, file) in mappings {
            guard let regex = try? NSRegularExpression(
                pattern: "\\b(\(filePattern))\\s+(\(rankToken))\\b",
                options: [.caseInsensitive]
            ) else { continue }

            let nsText = result as NSString
            let matches = regex.matches(
                in: result,
                range: NSRange(location: 0, length: nsText.length)
            )

            for match in matches.reversed() {
                let rankRaw = nsText.substring(with: match.range(at: 2))
                guard let rank = spokenRankDigit(for: rankRaw, language: language) else { continue }
                let replacement = "\(file)\(rank)"
                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        return result
    }

    private static func resolveSpokenFileBeforeDestinationSquare(
        in text: String,
        language: RecognitionLanguage
    ) -> String {
        let mappings = ChessSpeechLexicon.lexicon(for: language).spokenFileLetters
        let rankPattern = ChessSpeechLexicon.lexicon(for: language).rankPattern

        var result = text
        for (spoken, file) in mappings {
            let escaped = NSRegularExpression.escapedPattern(for: spoken)
            result = applyRegexReplacements(result, patterns: [
                (#"\b\#(escaped)\s+(?=[a-h][1-8]\b)"#, "\(file) "),
                (#"\b\#(escaped)\s+(?=[a-h]\s+(?:\(rankPattern))\b)"#, "\(file) ")
            ])
        }
        return result
    }

    private static func inferDroppedPawnCapture(in text: String, language: RecognitionLanguage) -> String {
        let lexicon = ChessSpeechLexicon.lexicon(for: language)
        let lowered = text.lowercased()
        if lexicon.captureVerbs.contains(where: { lowered.contains($0) }) {
            return text
        }
        if lexicon.movePrepositions.contains(where: { lowered.contains($0) }) {
            return text
        }
        if lexicon.pieceAliases.contains(where: { lowered.contains($0) }) {
            return text
        }
        if isCoordinateSquarePairNotation(lowered) {
            return text
        }

        let captureVerb = language == .english ? "takes" : "schlagt"
        return applyRegexReplacements(text, patterns: [
            // "c d 4" / "see d 4" — split destination square, optional source rank on file
            (#"\b([a-h](?:[1-8])?)\s+([a-h])\s+([1-8])\b"#, "$1 \(captureVerb) $2$3"),
            // "c d4" — single file letter + square only (not "d7 d6" coordinate pairs)
            (#"\b([a-h])\s+([a-h][1-8])\b"#, "$1 \(captureVerb) $2")
        ])
    }

    /// Two full squares like "d7 d6" or "e2 e4" — coordinate notation, not a dropped capture verb.
    private static func isCoordinateSquarePairNotation(_ text: String) -> Bool {
        text.range(of: #"^[a-h][1-8]\s+[a-h][1-8]$"#, options: .regularExpression) != nil
    }

    private static func inferArticleAsCaptureVerb(in text: String, language: RecognitionLanguage) -> String {
        switch language {
        case .english:
            return applyRegexReplacements(text, patterns: [
                (#"\b([a-h])\s+(?:a|the|an)\s+([a-h][1-8])\b"#, "$1 takes $2")
            ])
        case .german:
            return applyRegexReplacements(text, patterns: [
                (#"\b([a-h])\s+(?:die|der|das|ein|eine)\s+([a-h][1-8])\b"#, "$1 schlagt $2")
            ])
        }
    }

    private static func fixMisheardSplitSquares(in text: String, language: RecognitionLanguage) -> String {
        let spokenPattern = ChessSpeechLexicon.lexicon(for: .english).spokenRanks.joined(separator: "|")
            + "|eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht"
        guard let regex = try? NSRegularExpression(
            pattern: "\\b([a-h])([1-8])\\s+(\(spokenPattern)|6|7|8)\\b",
            options: .caseInsensitive
        ) else {
            return text
        }

        let nsText = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches.reversed() {
            let wrongRank = nsText.substring(with: match.range(at: 2))
            let spoken = nsText.substring(with: match.range(at: 3))
            guard let intendedRank = spokenRankDigit(for: spoken, language: language)
                    ?? (spoken.allSatisfy(\.isNumber) ? spoken : nil),
                  intendedRank.count == 1,
                  "12345678".contains(intendedRank),
                  intendedRank != wrongRank else {
                continue
            }

            let file = nsText.substring(with: match.range(at: 1)).lowercased()
            result = (result as NSString).replacingCharacters(in: match.range, with: "\(file)\(intendedRank)")
        }

        return result
    }

    private static func applyRegexReplacements(
        _ text: String,
        patterns: [(String, String)]
    ) -> String {
        TranscriptReplacementEngine.apply(
            text,
            rules: patterns.map { TranscriptReplacementRule(id: $0.0, pattern: $0.0, replacement: $0.1) }
        )
    }
}
