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
        result = result.replacingOccurrences(
            of: #"\b9\b"#,
            with: "knight",
            options: .regularExpression
        )
        
        let spokenLetters: [(String, String)] = [
            ("see ", "c "), (" bee ", " b "), (" dee ", " d "),
            (" ee ", " e "), (" gee ", " g "), (" aitch ", " h ")
        ]
        for (wrong, right) in spokenLetters {
            result = result.replacingOccurrences(of: wrong, with: right)
        }
        
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
        
        return result
    }
    
    /// Shared normalization for learned-phrase matching and move parsing.
    static func normalizeForPhraseMatching(_ text: String, language: RecognitionLanguage) -> String {
        var result = normalize(text, language: language)
        
        result = result
            .replacingOccurrences(of: "0-0-0", with: "o-o-o")
            .replacingOccurrences(of: "0-0", with: "o-o")
        
        let spokenLetters: [(String, String)] = [
            ("see ", "c "), (" see ", " c "), ("sea ", "c "),
            ("bee ", "b "), (" bee ", " b "),
            ("dee ", "d "), (" dee ", " d "),
            ("ee ", "e "), (" ee ", " e "),
            ("gee ", "g "), (" gee ", " g "),
            ("aitch ", "h "), (" aitch ", " h ")
        ]
        for (wrong, right) in spokenLetters {
            result = result.replacingOccurrences(of: wrong, with: right)
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
