//
//  ChessSpeechLexicon.swift
//  Chess Recorder
//
//  Single source of truth for chess speech vocabulary shared across
//  normalization, seeding, language-model building, and runtime hints.
//

import Foundation

enum ChessSpeechLexicon {
    static let files: [String] = Array("abcdefgh").map(String.init)
    static let digitRanks = (1...8).map(String.init)

    struct LanguageLexicon {
        let pieces: [String]
        let pieceAliases: [String]
        let seedPieceVariants: [String]
        let captureVerbs: [String]
        let seedCaptureVerbs: [String]
        let clmCaptureVerbs: [String]
        let spokenRanks: [String]
        let spokenFileLetters: [String: Character]
        let ambiguousFileTokens: Set<String>
        let movePrepositions: [String]
        let runtimeHomophoneTokens: [String]

        var piecePattern: String {
            pieceAliases.joined(separator: "|")
        }

        var captureVerbPattern: String {
            captureVerbs.joined(separator: "|")
        }

        var rankPattern: String {
            switch spokenRanks.first == "one" {
            case true:
                return "one|two|three|four|five|six|seven|eight|[1-8]"
            case false:
                return "[1-8]|eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht"
            }
        }

        func spokenFilePatternGroups() -> [(pattern: String, file: String)] {
            var groups: [Character: [String]] = [:]
            for (spoken, file) in spokenFileLetters {
                groups[file, default: []].append(spoken)
            }
            if spokenFileLetters.values.contains(Character("a")) {
                groups["a", default: []].append("a")
            }
            for file in ChessSpeechLexicon.files {
                groups[Character(file), default: []].append(file)
            }
            return groups.map { file, words in
                (words.joined(separator: "|"), String(file))
            }
        }

        func pawnCaptureMishearingPatterns() -> [(String, String)] {
            spokenFileLetters.map { spoken, file in
                let escaped = NSRegularExpression.escapedPattern(for: spoken)
                return (
                    "\\b\(escaped)\\s+(\(captureVerbPattern))\\b",
                    "\(file) $2"
                )
            }
        }

        func spokenFileHomophoneSpacingReplacements() -> [(String, String)] {
            spokenFileLetters.keys.flatMap { spoken -> [(String, String)] in
                [("\(spoken) ", "\(spokenFileLetters[spoken]!) ")]
            }
        }
    }

    static func lexicon(for language: RecognitionLanguage) -> LanguageLexicon {
        switch language {
        case .english:
            return LanguageLexicon(
                pieces: ["knight", "bishop", "rook", "queen", "king", "pawn"],
                pieceAliases: ["knight", "night", "bishop", "rook", "rock", "look", "queen", "king", "pawn"],
                seedPieceVariants: ["knight", "bishop", "rook", "queen", "king", "pawn"],
                captureVerbs: ["takes", "take", "captures", "capture"],
                seedCaptureVerbs: ["takes", "take", "captures", "capture"],
                clmCaptureVerbs: ["takes", "take", "captures", "capture"],
                spokenRanks: ["one", "two", "three", "four", "five", "six", "seven", "eight"],
                spokenFileLetters: [
                    "see": "c", "sea": "c", "cee": "c", "she": "c",
                    "bee": "b", "be": "b",
                    "de": "d", "dee": "d",
                    "ee": "e", "he": "e",
                    "gee": "g",
                    "aitch": "h", "each": "h", "age": "h",
                    "eff": "f", "ef": "f",
                    "a": "a"
                ],
                ambiguousFileTokens: ["hey", "ay"],
                movePrepositions: ["to", "too", "two"],
                runtimeHomophoneTokens: ["see", "sea", "bee", "dee", "gee", "aitch", "hey", "ay", "age"]
            )
        case .german:
            return LanguageLexicon(
                pieces: ["springer", "läufer", "turm", "dame", "könig", "bauer"],
                pieceAliases: [
                    "springer", "laufer", "laeufer", "lauferin", "läufer",
                    "turm", "dame", "konig", "könig", "bauer"
                ],
                seedPieceVariants: ["springer", "laufer", "läufer", "turm", "dame", "konig", "könig", "bauer"],
                captureVerbs: ["schlagt", "schlaegt", "schagt", "schaegt", "nimmt"],
                seedCaptureVerbs: ["schlägt", "schlagt", "schlaegt", "nimmt"],
                clmCaptureVerbs: ["schlägt", "schlagt", "nimmt"],
                spokenRanks: ["eins", "zwei", "drei", "vier", "funf", "fünf", "sechs", "sieben", "acht"],
                spokenFileLetters: [
                    "zee": "c", "cee": "c", "see": "c", "sea": "c",
                    "be": "b", "bee": "b",
                    "de": "d", "dee": "d",
                    "ge": "g", "gee": "g",
                    "ha": "h", "hache": "h", "ache": "h", "haar": "h",
                    "ef": "f", "eff": "f",
                    "ah": "a"
                ],
                ambiguousFileTokens: [],
                movePrepositions: ["nach", "auf"],
                runtimeHomophoneTokens: ["ah"]
            )
        }
    }

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

    static func spokenFileLetter(for token: String, language: RecognitionLanguage) -> Character? {
        let word = token.lowercased()
        if word.count == 1, let char = word.first, files.contains(word) {
            return char
        }
        return lexicon(for: language).spokenFileLetters[word]
    }

    static func isAmbiguousEnglishFileToken(_ token: String) -> Bool {
        lexicon(for: .english).ambiguousFileTokens.contains(token.lowercased())
    }

    static func isAmbiguousEnglishFileRankUtterance(_ words: [String]) -> Bool {
        guard words.count >= 2 else { return false }
        let fileToken = words[words.count - 2]
        let rankToken = words[words.count - 1]
        guard isAmbiguousEnglishFileToken(fileToken) else { return false }
        return spokenRankDigit(for: rankToken, language: .english) != nil
    }
}
