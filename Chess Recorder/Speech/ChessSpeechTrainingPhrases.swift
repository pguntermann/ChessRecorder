//
//  ChessSpeechTrainingPhrases.swift
//  Chess Recorder
//

import Foundation

/// Balanced speech-training phrases so no chess file (a–h) is boosted over another.
enum ChessSpeechTrainingPhrases {
    static let files = Array("abcdefgh")
    static let digitRanks = (1...8).map(String.init)

    static func germanSpokenRanks() -> [String] {
        ["eins", "zwei", "drei", "vier", "funf", "fünf", "sechs", "sieben", "acht"]
    }

    static func englishSpokenRanks() -> [String] {
        ["one", "two", "three", "four", "five", "six", "seven", "eight"]
    }

    /// Phrases like `a6` and `a 6` for every file and digit rank.
    static func balancedFileDigitRankPhrases(
        compactCount: Int = 280,
        spacedCount: Int = 260
    ) -> [(phrase: String, count: Int)] {
        var result: [(String, Int)] = []
        for file in files {
            for rank in digitRanks {
                result.append(("\(file)\(rank)", compactCount))
                result.append(("\(file) \(rank)", spacedCount))
            }
        }
        return result
    }

    /// Phrases like `a sechs` for every file and spoken rank.
    static func balancedFileSpokenRankPhrases(
        spokenRanks: [String],
        count: Int = 280
    ) -> [(phrase: String, count: Int)] {
        var result: [(String, Int)] = []
        for file in files {
            for spoken in spokenRanks {
                result.append(("\(file) \(spoken)", count))
            }
        }
        return result
    }

    /// All 64 squares with equal weight.
    static func allSquarePhrases(count: Int = 300) -> [(phrase: String, count: Int)] {
        files.flatMap { file in
            digitRanks.map { rank in
                ("\(file)\(rank)", count)
            }
        }
    }

    /// Former e-file / h-file-only recognition boosts to remove from persisted vocabulary.
    static func retiredFileBiasedRecognitionPhrases(for language: RecognitionLanguage) -> [String] {
        switch language {
        case .german:
            var retired: [String] = []
            for rank in digitRanks {
                retired.append("e\(rank)")
                retired.append("e \(rank)")
                retired.append("h\(rank)")
                retired.append("h \(rank)")
            }
            for spoken in germanSpokenRanks() {
                retired.append("e \(spoken)")
            }
            return retired
        case .english:
            return [
                "a3", "a 3", "hey three", "hey 3", "ay three", "ay 3",
                "a6", "a 6", "hey six", "ay six", "hey 6"
            ]
        }
    }
}
