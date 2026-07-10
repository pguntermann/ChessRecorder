//
//  ChessTranscriptNormalizer.swift
//  Chess Recorder
//
//  Fallback corrections when the custom language model is unavailable
//  or the recognizer still mishears domain phrases.
//

import Foundation

enum ChessTranscriptNormalizer {
    
    /// Applies locale-aware ASR corrections before move parsing.
    static func normalize(_ text: String, language: RecognitionLanguage) -> String {
        var result = text
            .precomposedStringWithCanonicalMapping
            .lowercased()
        
        result = normalizeUnicode(result)
        
        switch language {
        case .english:
            result = normalizeEnglish(result)
        case .german:
            result = normalizeGerman(result)
        }
        
        return result
    }
    
    private static func normalizeUnicode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ß", with: "ss")
    }
    
    private static func normalizeEnglish(_ text: String) -> String {
        var result = text

        // ASR occasionally turns "knight" into "9".
        result = applyRegexReplacements(result, patterns: [
            (#"\b9\b"#, "knight"),
            (#"\bpet\s*shop\b"#, "bishop"),
            (#"\bbee\s*shop\b"#, "bishop"),
            (#"\bbit\s*shop\b"#, "bishop"),
            (#"\bpetshop\b"#, "bishop"),
            (#"\bbeeshop\b"#, "bishop"),
            (#"\bbishup\b"#, "bishop"),
            (#"\bbishopp\b"#, "bishop"),
            (#"\bbishop\s+shop\b"#, "bishop"),
            (#"\b(bishop|knight|night|rook|queen|king)\s+shop\b"#, "$1"),
            (#"\bshop\s+(?=takes|take|to|captures|capture)\b"#, ""),
            (#"\bbrooke\b"#, "rook"),
            (#"\brock\b"#, "rook"),
            (#"\blook\s+(takes|take|captures|capture|to)\b"#, "rook $1"),
            (#"\blook\s+([a-h][1-8])\b"#, "rook $1"),
            (#"\blook\s+([a-h])\s+(to|takes|take|captures|capture)\b"#, "rook $1 $2"),
            (#"\blook\s+([a-h])\s+(one|two|three|four|five|six|seven|eight|[1-8])\b"#, "rook $1 $2"),
            (#"\b([a-h][18])\s+(rock|look)\b"#, "$1 rook"),
            (#"\b(rock|look)\s+([a-h][18])\b"#, "rook $2"),
            (#"\bknit\b"#, "knight"),
            (#"\bnite\b"#, "knight"),
            (#"\bnight\b"#, "knight")
        ])
        result = fixEnglishDetectsMishearing(in: result)
        
        result = applyRegexReplacements(result, patterns: [
            (#"\b(see|sea|cee|she)\s+(?=\#(englishRankToken))\b"#, "c "),
            (#"\b(hey|ay)\s+(?=\#(englishRankToken))\b"#, "a "),
            (#"\b(bee|be)\s+(?=\#(englishRankToken))\b"#, "b "),
            (#"\bdee\s+(?=\#(englishRankToken))\b"#, "d "),
            (#"\b(he|ee)\s+(?=\#(englishRankToken))\b"#, "e "),
            (#"\bgee\s+(?=\#(englishRankToken))\b"#, "g "),
            (#"\b(aitch|each)\s+(?=\#(englishRankToken))\b"#, "h "),
            (#"\b(eff|ef)\s+(?=\#(englishRankToken))\b"#, "f ")
        ])
        result = fixEnglishPawnCaptureMishearings(in: result)
        result = fixEnglishAFileMishearings(in: result)
        
        return result
    }

    /// a-file is often misheard — especially "a3" → "hey siri" (Siri wake phrase).
    private static func fixEnglishAFileMishearings(in text: String) -> String {
        applyRegexReplacements(text, patterns: [
            (#"\b(hey|ay)\s+siri\b"#, "a3"),
            (#"\b(hey|ay)\s+sir\b"#, "a3"),
            (#"\b(hey|ay)\s+seri\b"#, "a3"),
            (#"\b(hey|ay)\s+sery\b"#, "a3"),
            (#"\b(hey|ay)\s+cery\b"#, "a3"),
            (#"\b(hey|ay)\s+three\b"#, "a3"),
            (#"\b(hey|ay)\s+tree\b"#, "a3"),
            (#"\b(hey|ay)\s+free\b"#, "a3"),
            (#"\ba\s+siri\b"#, "a3"),
            (#"\ba\s+sir\b"#, "a3"),
            (#"\b8\s+3\b"#, "a3"),
            (#"\b83\b"#, "a3"),
            (#"^\s*hey\s*$"#, "a"),
            (#"^\s*ay\s*$"#, "a")
        ])
    }

    /// ASR sometimes merges "knight e5 to d7" into digit blobs like "9527".
    private static func fixEnglishCompactMoveBlobs(in text: String) -> String {
        applyRegexReplacements(text, patterns: [
            (#"\b9([a-h])([1-8])([a-h])([1-8])\b"#, "knight $1$2 to $3$4"),
            (#"\b9([a-h])([1-8])2([1-8])\b"#, "knight $1$2 to $3"),
            (#"\b9([1-8])2([1-8])\b"#, "knight $1 to $2"),
            (#"\b9([a-h])([1-8])\s+to\s+([1-8])\b"#, "knight $1$2 to $3"),
            (#"\b9([1-8])\s+to\s+([1-8])\b"#, "knight $1 to $2")
        ])
    }
    
    private static func normalizeGerman(_ text: String) -> String {
        var result = text
        
        // Keep common bishop spellings aligned after umlaut stripping.
        result = result.replacingOccurrences(
            of: #"\blaeufer(in)?\b"#,
            with: "laufer$1",
            options: .regularExpression
        )

        // Letter "e" misheard as "je" (ja)
        result = result.replacingOccurrences(
            of: #"\bje\s+"#,
            with: "e ",
            options: .regularExpression
        )
        
        // "d4" misheard as "die 4" — only before a rank, not "die Dame"
        result = result.replacingOccurrences(
            of: #"\bdie\s+(?=[1-8]|eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht)\b"#,
            with: "d ",
            options: .regularExpression
        )

        // ASR hears d-file captures as "die schlägt" (confused with article "die")
        result = result.replacingOccurrences(
            of: #"\bdie\s+(schlagt|schlaegt|schagt|schaegt|nimmt)\b"#,
            with: "d $1",
            options: .regularExpression
        )
        
        // ASR merges "e schlägt" into "e4 schlägt"
        result = result.replacingOccurrences(
            of: #"([a-h])[1-8]\s+(schlagt|schlaegt|nimmt)\s"#,
            with: "$1 $2 ",
            options: .regularExpression
        )
        
        let spokenLetters: [(String, String)] = [
            (" dee ", " d "), (" tee ", " t "), (" bee ", " b "),
            (" eh ", " e ")
        ]
        for (wrong, right) in spokenLetters {
            result = result.replacingOccurrences(of: wrong, with: right)
        }

        result = applyGermanFileMishearings(result)
        
        return result
    }

    private static let englishRankToken =
        "one|two|three|four|five|six|seven|eight|[1-8]"

    private static let germanRankPattern =
        "[1-8]|eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht"

    private static let englishSpokenFileLetters: [String: Character] = [
        "see": "c", "sea": "c", "cee": "c", "she": "c",
        "bee": "b", "be": "b",
        "de": "d", "dee": "d",
        "ee": "e", "he": "e",
        "gee": "g",
        "aitch": "h", "each": "h",
        "eff": "f", "ef": "f",
        "hey": "a", "ay": "a"
    ]

    private static let germanSpokenFileLetters: [String: Character] = [
        "zee": "c", "cee": "c", "see": "c", "sea": "c",
        "be": "b", "bee": "b",
        "de": "d", "dee": "d",
        "ge": "g", "gee": "g",
        "ha": "h", "hache": "h", "ache": "h", "haar": "h",
        "ef": "f", "eff": "f",
        "ah": "a"
    ]

    /// Maps a spoken file homophone ("hey", "dee", …) or file letter to a–h.
    static func spokenFileLetter(for token: String, language: RecognitionLanguage) -> Character? {
        let word = token.lowercased()
        if word.count == 1, let char = word.first, "abcdefgh".contains(char) {
            return char
        }
        switch language {
        case .english:
            return englishSpokenFileLetters[word]
        case .german:
            return germanSpokenFileLetters[word]
        }
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
        guard "abcdefgh".contains(file) else { return nil }
        return String(file) + String(rank)
    }

    private static func englishSpokenFilePatternGroups() -> [(String, String)] {
        var groups: [Character: [String]] = [:]
        for (spoken, file) in englishSpokenFileLetters {
            groups[file, default: []].append(spoken)
        }
        for file in "abcdefgh" {
            groups[file, default: []].append(String(file))
        }
        return groups.map { file, words in
            (words.joined(separator: "|"), String(file))
        }
    }

    private static func germanSpokenFilePatternGroups() -> [(String, String)] {
        var groups: [Character: [String]] = [:]
        for (spoken, file) in germanSpokenFileLetters {
            groups[file, default: []].append(spoken)
        }
        groups["a", default: []].append("a")
        return groups.map { file, words in
            (words.joined(separator: "|"), String(file))
        }
    }

    /// ASR often hears "d takes" as "detects" (merged) or "de takes" (split).
    private static func fixEnglishDetectsMishearing(in text: String) -> String {
        applyRegexReplacements(text, patterns: englishDetectsMishearingPatterns())
    }

    /// Fixes piece-move homophones without guessing destination files.
    /// "be 7" is left for square coalescing → b7; rank-only destinations use the legal-move resolver.
    private static func fixEnglishPieceMoveMishearings(in text: String) -> String {
        applyRegexReplacements(text, patterns: englishPieceMoveMishearingPatterns())
    }

    static func englishPieceMoveMishearingPatterns() -> [(String, String)] {
        let pieces = "knight|bishop|rook|queen|king"
        return [
            // "night to be 7" — ASR dropped the b-file disambiguator before "to"
            (#"\b(\#(pieces))\s+to\s+(bee|be)\s+"#, "$1 b to "),
            // "knight be to d7" — homophone "be" used as the b-file disambiguator
            (#"\b(\#(pieces))\s+(bee|be)\s+(?=to\b)"#, "$1 b ")
        ]
    }

    static func englishDetectsMishearingPatterns() -> [(String, String)] {
        let homophones = englishSpokenFileLetters.keys
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
        let captureTarget = "(?:\(homophones)|[a-h])(?:[1-8]|\\s+(?:\(englishRankToken)))"
        return [
            (#"\bdetects\s*(?=\#(captureTarget))"#, "d takes "),
            (#"\bdetects(?=[a-h][1-8]\b)"#, "d takes "),
            (#"\bdetect\s*(?=\#(captureTarget))"#, "d take "),
            (#"\bdetect(?=[a-h][1-8]\b)"#, "d take "),
            (#"\bd\s+e\s+(takes|take|captures|capture)\b"#, "d $1")
        ]
    }

    private static func fixEnglishPawnCaptureMishearings(in text: String) -> String {
        applyRegexReplacements(text, patterns: englishPawnCaptureMishearingPatterns())
    }

    /// Maps misheard file letters before a capture verb — target square is handled separately.
    static func englishPawnCaptureMishearingPatterns() -> [(String, String)] {
        englishSpokenFileLetters.map { spoken, file in
            (
                "\\b\(NSRegularExpression.escapedPattern(for: spoken))\\s+(takes|take|captures|capture)\\b",
                "\(file) $2"
            )
        }
    }

    static func englishPawnCaptureBoostPhrases(
        fileCount: Int = 450,
        misheardCount: Int = 420
    ) -> [(phrase: String, count: Int)] {
        let captureVerbs = ["takes", "take", "captures", "capture"]
        let misheardFiles = Dictionary(grouping: englishSpokenFileLetters, by: \.value)
            .mapValues { pairs in pairs.map(\.key) }

        var phrases: [(String, Int)] = []
        for file in "abcdefgh" {
            for verb in captureVerbs {
                phrases.append(("\(file) \(verb)", fileCount))
            }
        }
        for (_, mishears) in misheardFiles {
            for mishear in mishears {
                for verb in captureVerbs {
                    phrases.append(("\(mishear) \(verb)", misheardCount))
                }
            }
        }
        return phrases
    }

    /// Digit 8 is never a valid file — ASR often uses it for the a-file ("a3" → "83").
    private static func fixInvalidDigitFileSquares(in text: String) -> String {
        applyRegexReplacements(text, patterns: [
            (#"\b8([1-8])\b"#, "a$1"),
            (#"\b8\s+([1-8])\b"#, "a$1")
        ])
    }

    private static func fixEnglishSquareGarbage(in text: String) -> String {
        applyRegexReplacements(text, patterns: [
            (#"\bsince\s+we\b"#, "c3"),
            (#"\bher\s+siri\b"#, "c3"),
            (#"\bsee\s+we\b"#, "c3"),
            (#"\bsea\s+we\b"#, "c3"),
            (#"\bsee\s+three\b"#, "c3"),
            (#"\bsea\s+three\b"#, "c3"),
            (#"\bc\s+tree\b"#, "c3"),
            (#"\bsee\s+free\b"#, "c3"),
            (#"\bcee\s+three\b"#, "c3"),
            (#"^\s*sea\s*$"#, "c3"),
            (#"^\s*see\s+three\s*$"#, "c3"),
            (#"^\s*sea\s+three\s*$"#, "c3")
        ])
    }

    private static func fixSpokenFileRankPhrases(in text: String, language: RecognitionLanguage) -> String {
        let rankToken = language == .english ? englishRankToken : germanRankPattern
        let mappings = language == .english
            ? englishSpokenFilePatternGroups()
            : germanSpokenFilePatternGroups()

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

    private static func applyGermanFileMishearings(_ text: String) -> String {
        let pieces = "springer|laufer|laeufer|lauferin|turm|dame|konig|bauer"
        return applyRegexReplacements(text, patterns: [
            (#"\b(\#(pieces))haar\b"#, "$1 h"),
            (#"\b(\#(pieces))hache\b"#, "$1 h"),
            (#"\b(\#(pieces))ha\s+(?=auf|nach|schlagt|schlaegt|schagt|schaegt|nimmt)\b"#, "$1 h "),
            (#"\bhaar\s+(?=\#(germanRankPattern))\b"#, "h "),
            (#"\bhaar\s+auf\b"#, "h auf"),
            (#"\bhaar\s+(schlagt|schlaegt|schagt|schaegt|nimmt)\b"#, "h $1"),
            (#"\bha\s+(?=\#(germanRankPattern))\b"#, "h "),
            (#"\bha\s+auf\b"#, "h auf"),
            (#"\bhache\s+(?=\#(germanRankPattern))\b"#, "h "),
            (#"\bache\s+(?=\#(germanRankPattern))\b"#, "h "),
            (#"\bhaar\b"#, "h")
        ])
    }

    /// Maps spoken file homophones directly before a destination square ("she d4" → "c d4").
    private static func resolveSpokenFileBeforeDestinationSquare(in text: String, language: RecognitionLanguage) -> String {
        let mappings: [String: Character]
        switch language {
        case .english:
            mappings = englishSpokenFileLetters
        case .german:
            mappings = germanSpokenFileLetters
        }

        var result = text
        for (spoken, file) in mappings {
            let escaped = NSRegularExpression.escapedPattern(for: spoken)
            result = applyRegexReplacements(result, patterns: [
                (#"\b\#(escaped)\s+(?=[a-h][1-8]\b)"#, "\(file) "),
                (#"\b\#(escaped)\s+(?=[a-h]\s+(?:[1-8]|one|two|three|four|five|six|seven|eight|eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht)\b)"#, "\(file) ")
            ])
        }
        return result
    }

    /// ASR often drops the capture verb entirely ("c d 4" / "she d4" → "c d4").
    private static func inferDroppedPawnCapture(in text: String, language: RecognitionLanguage) -> String {
        let lowered = text.lowercased()
        let captureVerbs = language == .english
            ? ["takes", "take", "captures", "capture"]
            : ["schlagt", "schlaegt", "schagt", "nimmt"]
        if captureVerbs.contains(where: { lowered.contains($0) }) {
            return text
        }

        let movePrepositions = ["nach", "auf", "to", "too", "two"]
        if movePrepositions.contains(where: { lowered.contains($0) }) {
            return text
        }

        let pieceNames = language == .english
            ? ["knight", "night", "bishop", "rook", "rock", "look", "queen", "king", "pawn"]
            : ["springer", "laufer", "laeufer", "lauferin", "turm", "dame", "konig", "bauer"]
        if pieceNames.contains(where: { lowered.contains($0) }) {
            return text
        }

        switch language {
        case .english:
            return applyRegexReplacements(text, patterns: [
                (#"\b([a-h](?:[1-8])?)\s+([a-h])\s+([1-8])\b"#, "$1 takes $2$3"),
                (#"\b([a-h](?:[1-8])?)\s+([a-h][1-8])\b"#, "$1 takes $2")
            ])
        case .german:
            return applyRegexReplacements(text, patterns: [
                (#"\b([a-h](?:[1-8])?)\s+([a-h])\s+([1-8])\b"#, "$1 schlagt $2$3"),
                (#"\b([a-h](?:[1-8])?)\s+([a-h][1-8])\b"#, "$1 schlagt $2")
            ])
        }
    }

    /// ASR often substitutes a capture verb with an article ("c a d4" for "c takes d4").
    /// Must run before `stripSpokenArticles`, which would otherwise leave "c d4".
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

    /// Removes articles ASR often inserts before squares ("bishop takes the e7").
    static func stripSpokenArticles(from text: String, language: RecognitionLanguage) -> String {
        switch language {
        case .english:
            return applyRegexReplacements(text, patterns: [
                (#"\b(the|an)\s+"#, ""),
                (#"\s+\b(the|an)\b"#, ""),
                (#"\ba\s+(?=[a-h][1-8]\b)"#, ""),
                (#"\ba\s+(?=(?:see|sea|cee|bee|be|dee|gee|aitch|each|eff|ef|ay)\s+(?:one|two|three|four|five|six|seven|eight|[1-8]))"#, "")
            ])
        case .german:
            return applyRegexReplacements(text, patterns: [
                (#"\b(der|das|ein|eine)\s+(?=[a-h][1-8]\b)"#, ""),
                (#"\b(der|das|ein|eine)\s+(?=[a-h]\s+(?:[1-8]|eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht))"#, ""),
                (#"\bdie\s+(?=[a-h][1-8]\b)"#, ""),
                (#"\bdie\s+(?=[a-h]\s+(?:[1-8]|eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht))"#, "")
            ])
        }
    }

    /// Removes trailing spoken check/checkmate annotations users often add after a move.
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

    private static func applyRegexReplacements(
        _ text: String,
        patterns: [(String, String)]
    ) -> String {
        patterns.reduce(text) { current, pattern in
            current.replacingOccurrences(
                of: pattern.0,
                with: pattern.1,
                options: .regularExpression
            )
        }
    }
    
    /// Shared normalization for learned-phrase matching and move parsing.
    static func normalizeForPhraseMatching(_ text: String, language: RecognitionLanguage) -> String {
        var result = normalize(text, language: language)

        if language == .english {
            result = fixEnglishDetectsMishearing(in: result)
            result = fixEnglishPieceMoveMishearings(in: result)
        }
        
        result = result
            .replacingOccurrences(of: "0-0-0", with: "o-o-o")
            .replacingOccurrences(of: "0-0", with: "o-o")
        
        let spokenLetters: [(String, String)] = [
            ("see ", "c "), (" see ", " c "), ("sea ", "c "), (" sea ", " c "),
            ("she ", "c "), (" she ", " c "),
            ("hey ", "a "), (" hey ", " a "), ("ay ", "a "), (" ay ", " a "),
            ("bee ", "b "), (" bee ", " b "),
            ("dee ", "d "), (" dee ", " d "),
            ("ee ", "e "), (" ee ", " e "),
            ("he ", "e "), (" he ", " e "),
            ("gee ", "g "), (" gee ", " g "),
            ("aitch ", "h "), (" aitch ", " h ")
        ]
        for (wrong, right) in spokenLetters {
            result = result.replacingOccurrences(of: wrong, with: right)
        }

        result = resolveSpokenFileBeforeDestinationSquare(in: result, language: language)
        result = fixSpokenFileRankPhrases(in: result, language: language)
        result = inferArticleAsCaptureVerb(in: result, language: language)
        result = stripSpokenArticles(from: result, language: language)
        if language == .english {
            result = fixEnglishSquareGarbage(in: result)
            result = fixEnglishAFileMishearings(in: result)
            result = fixEnglishPawnCaptureMishearings(in: result)
        }
        result = fixMisheardSplitSquares(in: result, language: language)
        result = stripSpokenCheckAnnotations(from: result, language: language)
        
        if language == .german {
            let germanNumbers: [(String, String)] = [
                ("eins", "1"), ("zwei", "2"), ("drei", "3"), ("vier", "4"),
                ("funf", "5"), ("fünf", "5"), ("sechs", "6"), ("sieben", "7"), ("acht", "8")
            ]
            for (spoken, digit) in germanNumbers {
                result = result.replacingOccurrences(of: spoken, with: digit)
            }
        } else {
            let englishNumbers: [(String, String)] = [
                ("one", "1"), ("two", "2"), ("three", "3"), ("four", "4"),
                ("five", "5"), ("six", "6"), ("seven", "7"), ("eight", "8")
            ]
            for (spoken, digit) in englishNumbers {
                result = result.replacingOccurrences(of: spoken, with: digit)
            }
            result = fixEnglishCompactMoveBlobs(in: result)
            result = fixInvalidDigitFileSquares(in: result)
        }

        result = inferDroppedPawnCapture(in: result, language: language)
        
        return result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// ASR often mishears ranks like "f6" as "f3 six" (f-three-six).
    static func spokenRankDigit(for token: String, language: RecognitionLanguage) -> String? {
        let normalized = normalizeSpokenRankToken(token, language: language)
        guard normalized.count == 1, "12345678".contains(normalized) else { return nil }
        return normalized
    }

    static func normalizeSpokenRankToken(_ token: String, language: RecognitionLanguage) -> String {
        switch token.lowercased() {
        case "one", "eins", "1": return "1"
        case "two", "zwei", "2": return "2"
        case "three", "drei", "3": return "3"
        case "four", "vier", "4": return "4"
        case "five", "funf", "fünf", "5": return "5"
        case "six", "sechs", "6": return "6"
        case "seven", "sieben", "7": return "7"
        case "eight", "acht", "8": return "8"
        default:
            let digits = token.filter(\.isNumber)
            return digits.count == 1 ? digits : token
        }
    }

    private static func fixMisheardSplitSquares(in text: String, language: RecognitionLanguage) -> String {
        let spokenPattern =
            "one|two|three|four|five|six|seven|eight|" +
            "eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht"
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
}
