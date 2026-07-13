//
//  ChessTranscriptNormalizerTests.swift
//  Chess RecorderTests
//

import XCTest
@testable import Chess_Recorder

final class ChessTranscriptNormalizerTests: XCTestCase {
    private struct NormalizationCase {
        let id: String
        let language: RecognitionLanguage
        let input: String
        let expected: String
    }

    private let cases: [NormalizationCase] = [
        NormalizationCase(id: "en.night-to-knight", language: .english, input: "night f3", expected: "knight f3"),
        NormalizationCase(id: "en.detects-capture", language: .english, input: "detects c4", expected: "d takes c4"),
        NormalizationCase(id: "en.hey-siri-a3", language: .english, input: "hey siri", expected: "a3"),
        NormalizationCase(id: "en.see-three-c3", language: .english, input: "see three", expected: "c3"),
        NormalizationCase(id: "en.d-takes", language: .english, input: "d takes e5", expected: "d takes e5"),
        NormalizationCase(id: "de.die-rank", language: .german, input: "die 4", expected: "d4"),
        NormalizationCase(id: "de.die-capture", language: .german, input: "die schlagt e4", expected: "d schlagt e4"),
        NormalizationCase(id: "de.haar-rank", language: .german, input: "haar 5", expected: "h5"),
        NormalizationCase(id: "de.arsch-rank", language: .german, input: "arsch drei", expected: "a 3"),
        NormalizationCase(id: "de.arsch-capture", language: .german, input: "arsch schlagt e4", expected: "a schlagt e4"),
        NormalizationCase(
            id: "de.arsch-piece-capture",
            language: .german,
            input: "dame schlagt arsch acht",
            expected: "dame schlagt a 8"
        ),
        NormalizationCase(id: "de.ah-homophone", language: .german, input: "ah 3", expected: "a3"),
        NormalizationCase(id: "de.coordinate-d7-d6", language: .german, input: "d7 d6", expected: "d7 d6"),
        NormalizationCase(id: "de.explicit-capture", language: .german, input: "d schlagt e6", expected: "d schlagt e6"),
        NormalizationCase(id: "de.inferred-capture", language: .german, input: "d e6", expected: "d schlagt e6"),
        NormalizationCase(id: "de.castle-lang-rochade", language: .german, input: "lang rochade", expected: "lange rochade"),
        NormalizationCase(
            id: "de.castle-queenside-wing",
            language: .german,
            input: "rochade auf damenseite",
            expected: "lange rochade"
        ),
        NormalizationCase(
            id: "de.castle-kingside-wing",
            language: .german,
            input: "rochade auf königsseite",
            expected: "kurze rochade"
        ),
        NormalizationCase(
            id: "de.castle-queenside-flugel",
            language: .german,
            input: "rochade auf damenflügel",
            expected: "lange rochade"
        ),
        NormalizationCase(id: "en.coordinate-e2-e4", language: .english, input: "e2 e4", expected: "e2 e4"),
        NormalizationCase(id: "en.inferred-capture", language: .english, input: "c d4", expected: "c takes d4")
    ]

    func testNormalizeForPhraseMatching() {
        for testCase in cases {
            let result = ChessTranscriptNormalizer.normalizeForPhraseMatching(
                testCase.input,
                language: testCase.language
            )
            XCTAssertEqual(
                result,
                testCase.expected,
                "Failed \(testCase.id): got '\(result)'"
            )
        }
    }

    func testRepairGermanAFileMishearingsOnRawASR() {
        let result = ChessTranscriptNormalizer.repairGermanAFileMishearings(in: "Dame schlägt Arsch")
        XCTAssertEqual(result, "dame schlagt a")
    }

    func testSpokenFileLetterUsesLexicon() {
        XCTAssertEqual(ChessTranscriptNormalizer.spokenFileLetter(for: "ah", language: .german), "a")
        XCTAssertEqual(ChessTranscriptNormalizer.spokenFileLetter(for: "see", language: .english), "c")
    }

    func testGermanCastlingMoveCandidates() {
        let cases: [(input: String, expected: String)] = [
            ("lang rochade", "O-O-O"),
            ("lange rochade", "O-O-O"),
            ("rochade auf damenseite", "O-O-O"),
            ("rochade auf damenflügel", "O-O-O"),
            ("rochade auf königsseite", "O-O"),
            ("rochade auf königsflügel", "O-O"),
            ("kurz rochade", "O-O")
        ]

        for testCase in cases {
            let candidates = MoveInterpreter.candidates(from: testCase.input, language: .german)
            XCTAssertEqual(
                candidates.first,
                testCase.expected,
                "Failed for '\(testCase.input)': got \(candidates)"
            )
        }
    }

    func testEnglishCastlingMoveCandidates() {
        let cases: [(input: String, expected: String)] = [
            ("castle queenside", "O-O-O"),
            ("castling queenside", "O-O-O"),
            ("castle on queenside", "O-O-O"),
            ("castle kingside", "O-O"),
            ("castling kingside", "O-O"),
            ("castle on kingside", "O-O")
        ]

        for testCase in cases {
            let candidates = MoveInterpreter.candidates(from: testCase.input, language: .english)
            XCTAssertEqual(
                candidates.first,
                testCase.expected,
                "Failed for '\(testCase.input)': got \(candidates)"
            )
        }
    }

    func testGermanPieceFileCaptureMoveCandidates() {
        let cases: [(input: String, expected: String)] = [
            ("springer b schlagt d7", "Nbxd7"),
            ("laufer h schlagt g5", "Bhxg5"),
            ("turm f schlagt d1", "Rfxd1")
        ]

        for testCase in cases {
            let candidates = MoveInterpreter.candidates(from: testCase.input, language: .german)
            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "Expected \(testCase.expected) in candidates for '\(testCase.input)', got \(candidates)"
            )
        }
    }

    func testGermanPieceFileCaptureWithSplitSquare() {
        let candidates = MoveInterpreter.candidates(
            from: "springer c schlagt e 2",
            language: .german
        )
        XCTAssertEqual(candidates.first, "Ncxe2", "got \(candidates)")
    }

    func testGermanPawnFileCaptureMoveCandidates() {
        let cases: [(input: String, expected: String)] = [
            ("b schlagt c5", "bxc5"),
            ("B schlagt c5", "bxc5"),
            ("b schlägt c5", "bxc5")
        ]

        for testCase in cases {
            let candidates = MoveInterpreter.candidates(from: testCase.input, language: .german)
            XCTAssertEqual(
                candidates.first,
                testCase.expected,
                "Expected \(testCase.expected) first for '\(testCase.input)', got \(candidates)"
            )
        }
    }

    func testPieceRankDisambiguationMoveCandidates() {
        let priorityCases: [(input: String, expected: String, language: RecognitionLanguage)] = [
            ("springer 5f3", "N5f3", .german),
            ("Springer 5F3", "N5f3", .german),
            ("springer 5 f3", "N5f3", .german),
            ("springer fünf f3", "N5f3", .german),
            ("springer 5 f 3", "N5f3", .german),
            ("knight 5 f3", "N5f3", .english),
            ("knight 5f3", "N5f3", .english),
            ("rook 1 d1", "R1d1", .english),
            ("turm 1 d1", "R1d1", .german)
        ]

        for testCase in priorityCases {
            let candidates = MoveInterpreter.candidates(from: testCase.input, language: testCase.language)
            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "Expected \(testCase.expected) in candidates for '\(testCase.input)', got \(candidates)"
            )
            XCTAssertEqual(
                candidates.first,
                testCase.expected,
                "Expected \(testCase.expected) first for '\(testCase.input)', got \(candidates)"
            )
        }

        let supportedCases: [(input: String, expected: String, language: RecognitionLanguage)] = [
            ("springer 5 auf f3", "N5f3", .german),
            ("springer 5 nach f3", "N5f3", .german),
            ("knight 5 to f3", "N5f3", .english)
        ]

        for testCase in supportedCases {
            let candidates = MoveInterpreter.candidates(from: testCase.input, language: testCase.language)
            XCTAssertTrue(
                candidates.contains(testCase.expected),
                "Expected \(testCase.expected) in candidates for '\(testCase.input)', got \(candidates)"
            )
        }
    }

    func testReplacementRulesAreUniquePerStage() {
        for language in RecognitionLanguage.allCases {
            for stage in TranscriptReplacementStage.allCases {
                let rules = TranscriptReplacementRules.rules(for: language, stage: stage)
                let ids = rules.map(\.id)
                XCTAssertEqual(
                    Set(ids).count,
                    ids.count,
                    "Duplicate rule ids in \(language) \(stage)"
                )
            }
        }
    }
}
