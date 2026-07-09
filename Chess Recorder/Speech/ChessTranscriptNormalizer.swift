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
            (#"\bbrooke\b"#, "rook"),
            (#"\bknit\b"#, "knight"),
            (#"\bnite\b"#, "knight")
        ])
        
        result = applyRegexReplacements(result, patterns: [
            (#"\b(see|sea|cee)\s+(?=\#(englishRankToken))\b"#, "c "),
            (#"\b(bee|be)\s+(?=\#(englishRankToken))\b"#, "b "),
            (#"\bdee\s+(?=\#(englishRankToken))\b"#, "d "),
            (#"\bgee\s+(?=\#(englishRankToken))\b"#, "g "),
            (#"\b(aitch|each)\s+(?=\#(englishRankToken))\b"#, "h ")
        ])
        
        let spokenLetters: [(String, String)] = [
            ("see ", "c "), (" bee ", " b "), (" dee ", " d "),
            (" ee ", " e "), (" gee ", " g "), (" aitch ", " h ")
        ]
        for (wrong, right) in spokenLetters {
            result = result.replacingOccurrences(of: wrong, with: right)
        }

        result = fixEnglishSquareGarbage(in: result)
        result = fixEnglishPawnCaptureMishearings(in: result)
        
        return result
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

    private static func fixEnglishPawnCaptureMishearings(in text: String) -> String {
        applyRegexReplacements(text, patterns: englishPawnCaptureMishearingPatterns())
    }

    /// Maps misheard file letters before a capture verb — target square is handled separately.
    static func englishPawnCaptureMishearingPatterns() -> [(String, String)] {
        [
            (#"\b(she|see|sea|cee)\s+(takes|take|captures|capture)\b"#, "c $2"),
            (#"\b(bee|be)\s+(takes|take|captures|capture)\b"#, "b $2"),
            (#"\bdee\s+(takes|take|captures|capture)\b"#, "d $2"),
            (#"\bee\s+(takes|take|captures|capture)\b"#, "e $2"),
            (#"\bgee\s+(takes|take|captures|capture)\b"#, "g $2"),
            (#"\b(aitch|each)\s+(takes|take|captures|capture)\b"#, "h $2"),
            (#"\b(eff|ef)\s+(takes|take|captures|capture)\b"#, "f $2"),
            (#"\bay\s+(takes|take|captures|capture)\b"#, "a $2")
        ]
    }

    static func englishPawnCaptureBoostPhrases(
        fileCount: Int = 450,
        misheardCount: Int = 420
    ) -> [(phrase: String, count: Int)] {
        let captureVerbs = ["takes", "take", "captures", "capture"]
        let misheardFiles: [(String, [String])] = [
            ("c", ["she", "see", "sea", "cee"]),
            ("b", ["bee", "be"]),
            ("d", ["dee"]),
            ("e", ["ee"]),
            ("g", ["gee"]),
            ("h", ["aitch", "each"]),
            ("f", ["eff", "ef"]),
            ("a", ["ay"])
        ]

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
        let mappings: [(String, String)] = language == .english ? [
            ("see|sea|cee", "c"),
            ("bee|be", "b"),
            ("dee", "d"),
            ("gee", "g"),
            ("aitch|each", "h"),
            ("eff|ef", "f"),
            ("ay|a", "a")
        ] : [
            ("zee|cee|see|sea", "c"),
            ("be|bee", "b"),
            ("de|dee", "d"),
            ("ge|gee", "g"),
            ("ha|hache", "h"),
            ("ef|eff", "f"),
            ("ah|a", "a")
        ]

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
        applyRegexReplacements(text, patterns: [
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
        
        result = result
            .replacingOccurrences(of: "0-0-0", with: "o-o-o")
            .replacingOccurrences(of: "0-0", with: "o-o")
        
        let spokenLetters: [(String, String)] = [
            ("see ", "c "), (" see ", " c "), ("sea ", "c "), (" sea ", " c "),
            ("bee ", "b "), (" bee ", " b "),
            ("dee ", "d "), (" dee ", " d "),
            ("ee ", "e "), (" ee ", " e "),
            ("gee ", "g "), (" gee ", " g "),
            ("aitch ", "h "), (" aitch ", " h ")
        ]
        for (wrong, right) in spokenLetters {
            result = result.replacingOccurrences(of: wrong, with: right)
        }

        result = fixSpokenFileRankPhrases(in: result, language: language)
        if language == .english {
            result = fixEnglishSquareGarbage(in: result)
            result = fixEnglishPawnCaptureMishearings(in: result)
        }
        result = fixMisheardSplitSquares(in: result, language: language)
        
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
        }
        
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
