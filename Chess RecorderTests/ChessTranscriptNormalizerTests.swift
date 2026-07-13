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
