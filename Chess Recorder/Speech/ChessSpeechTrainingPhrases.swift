//
//  ChessSpeechTrainingPhrases.swift
//  Chess Recorder
//

import Foundation

/// Balanced speech-training phrases so no chess file (a–h) is boosted over another.
enum ChessSpeechTrainingPhrases {
    static let files = ChessSpeechLexicon.files
    static let digitRanks = ChessSpeechLexicon.digitRanks

    static func germanSpokenRanks() -> [String] {
        ChessSpeechLexicon.lexicon(for: .german).spokenRanks
    }

    static func englishSpokenRanks() -> [String] {
        ChessSpeechLexicon.lexicon(for: .english).spokenRanks
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

    /// Balanced `<piece> <verb> <file> <spokenRank>` phrases (e.g. "dame schlägt a acht").
    static func balancedPieceCaptureSpokenRankPhrases(
        pieces: [String],
        captureVerbs: [String],
        spokenRanks: [String],
        count: Int = 300
    ) -> [(phrase: String, count: Int)] {
        var result: [(String, Int)] = []
        for piece in pieces {
            for verb in captureVerbs {
                for file in files {
                    for spoken in spokenRanks {
                        result.append(("\(piece) \(verb) \(file) \(spoken)", count))
                    }
                }
            }
        }
        return result
    }

    /// Balanced `<piece> <verb> <file> <rank>` phrases (e.g. "dame schlägt a 8").
    static func balancedPieceCaptureDigitRankPhrases(
        pieces: [String],
        captureVerbs: [String],
        count: Int = 280
    ) -> [(phrase: String, count: Int)] {
        var result: [(String, Int)] = []
        for piece in pieces {
            for verb in captureVerbs {
                for file in files {
                    for rank in digitRanks {
                        result.append(("\(piece) \(verb) \(file) \(rank)", count))
                    }
                }
            }
        }
        return result
    }

    /// Runtime-generated recognition boosts (not persisted in vocabulary JSON).
    static func generatedRecognitionPhraseCounts(
        for language: RecognitionLanguage
    ) -> [(phrase: String, count: Int)] {
        var phrases: [(String, Int)] = []
        for file in files {
            phrases.append((String(file), 320))
        }
        for rank in digitRanks {
            phrases.append((rank, 200))
        }

        switch language {
        case .english:
            let lexicon = ChessSpeechLexicon.lexicon(for: .english)
            let spokenRanks = lexicon.spokenRanks
            for word in spokenRanks {
                phrases.append((word, 160))
            }
            for word in lexicon.runtimeHomophoneTokens where !spokenRanks.contains(word) {
                phrases.append((word, word == "hey" || word == "ay" ? 240 : 220))
            }
            for piece in lexicon.seedPieceVariants {
                phrases.append((piece, 480))
            }
            phrases.append(contentsOf: balancedFileDigitRankPhrases())
            phrases.append(contentsOf: balancedFileSpokenRankPhrases(spokenRanks: spokenRanks))
            phrases.append(contentsOf: ChessTranscriptNormalizer.englishPawnCaptureBoostPhrases(
                fileCount: 380,
                misheardCount: 360
            ))
            phrases.append(contentsOf: balancedPieceCaptureSpokenRankPhrases(
                pieces: lexicon.seedPieceVariants,
                captureVerbs: lexicon.seedCaptureVerbs,
                spokenRanks: spokenRanks,
                count: 260
            ))
            phrases.append(contentsOf: balancedPieceCaptureDigitRankPhrases(
                pieces: lexicon.seedPieceVariants,
                captureVerbs: lexicon.seedCaptureVerbs,
                count: 240
            ))
            for phrase in englishCuratedRecognitionExamples() {
                phrases.append((phrase, 300))
            }
        case .german:
            let lexicon = ChessSpeechLexicon.lexicon(for: .german)
            let spokenRanks = lexicon.spokenRanks
            for word in spokenRanks {
                phrases.append((word, 160))
            }
            for word in lexicon.runtimeHomophoneTokens {
                phrases.append((word, 240))
            }
            for piece in lexicon.seedPieceVariants {
                phrases.append((piece, 480))
            }
            phrases.append(contentsOf: balancedFileDigitRankPhrases())
            phrases.append(contentsOf: balancedFileSpokenRankPhrases(spokenRanks: spokenRanks))
            phrases.append(contentsOf: ChessTranscriptNormalizer.germanPawnCaptureBoostPhrases(
                fileCount: 380,
                misheardCount: 360
            ))
            phrases.append(contentsOf: balancedPieceCaptureSpokenRankPhrases(
                pieces: lexicon.seedPieceVariants,
                captureVerbs: lexicon.seedCaptureVerbs,
                spokenRanks: spokenRanks,
                count: 260
            ))
            phrases.append(contentsOf: balancedPieceCaptureDigitRankPhrases(
                pieces: lexicon.seedPieceVariants,
                captureVerbs: lexicon.seedCaptureVerbs,
                count: 240
            ))
            for phrase in germanCuratedRecognitionExamples() {
                phrases.append((phrase, 300))
            }
        }

        return phrases
    }

    private static func englishCuratedRecognitionExamples() -> [String] {
        [
            "c3", "c 3", "see three", "sea three", "see 3", "sea 3",
            "bishop b5 check", "knight f3 check", "rook d1 check",
            "bishop takes d7", "bishop takes 7",
            "bishop e4 to e5", "bishop f1 to c4", "bishop takes e5",
            "bishop to e5", "bishop e5", "knight to f3", "knight f3",
            "knight g1 to f3", "knight f3 to e5", "knight takes d4",
            "d takes c4", "d takes e4", "c takes d4", "e takes d5", "e takes f5",
            "he takes d5", "he takes f5",
            "detects c4", "detects c 4", "detects e4", "de takes c4", "de takes c 4",
            "knight e5 to d7", "night e5 to d7", "knight e5 to 7",
            "knight b to d7", "night b to d7", "knight be to d7", "night to be 7",
            "knight bd7", "night bd7",
            "rook f to d1", "rook g1 to f3", "rook e1 to e8", "rook to d1",
            "rook a to d1", "rook a d1", "look at d1", "look at d 1",
            "queen d1 to h5", "queen to h5", "king e1 to e2", "pawn to e4"
        ]
    }

    private static func germanCuratedRecognitionExamples() -> [String] {
        [
            "ah 3", "ah drei", "dame schlägt ah acht",
            "turm f auf d1", "springer g1 auf f3", "turm f1 auf d1",
            "turm h auf g1", "turm h auf h1",
            "d schlagt e4", "d schlagt e vier",
            "läufer h auf g5", "springer h auf f3", "h auf f3", "h schlagt g5",
            "läufer auf e5", "läufer e5", "springer auf f3", "springer f3",
            "turm auf d1", "dame auf h5",
            "läufer b5 schach", "springer f3 schach", "turm d1 schach",
            "läufer auf e5 schach",
            "f1 läufer"
        ]
    }

    /// Former promotion-square collocations that over-weighted e8/g8/f8.
    static func retiredPromotionBiasedRecognitionPhrases(for language: RecognitionLanguage) -> [String] {
        switch language {
        case .german:
            return [
                "g8 turm", "e8 dame", "f8 springer", "e8 läufer",
                "turm g8", "dame e8", "f schlägt e8 turm", "g8 umwandlung turm"
            ]
        case .english:
            return [
                "g8 rook", "e8 queen", "f8 knight", "e8 bishop",
                "rook g8", "queen e8", "f takes e8 rook", "g8 promote rook"
            ]
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
