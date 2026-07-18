import XCTest
@testable import Chess_Recorder

final class ASRHypothesisSelectorTests: XCTestCase {
    func testRejectsMultiDigitOnlyHypotheses() {
        XCTAssertTrue(ASRHypothesisSelector.isRejectableDigitOnlyHypothesis("986"))
        XCTAssertTrue(ASRHypothesisSelector.isRejectableDigitOnlyHypothesis("9 8 6"))
        XCTAssertTrue(ASRHypothesisSelector.isRejectableDigitOnlyHypothesis("86"))
        XCTAssertFalse(ASRHypothesisSelector.isRejectableDigitOnlyHypothesis("4"))
        XCTAssertFalse(ASRHypothesisSelector.isRejectableDigitOnlyHypothesis("Knight 86"))
        XCTAssertFalse(ASRHypothesisSelector.isRejectableDigitOnlyHypothesis("e4"))
        XCTAssertFalse(ASRHypothesisSelector.isRejectableDigitOnlyHypothesis(""))
    }

    func testPrefersLetterContainingNBestOverDigitOnlyBest() {
        let selection = ASRHypothesisSelector.select(
            best: "986",
            alternatives: ["986", "Knight 86", "Knight eight"],
            previousChessyPartial: "Knight"
        )
        XCTAssertEqual(selection.text, "Knight 86")
        XCTAssertTrue(selection.replacedDigitOnlyBest)
    }

    func testFallsBackToPreviousChessyPartialWhenNBestHasNoLetters() {
        let selection = ASRHypothesisSelector.select(
            best: "986",
            alternatives: ["986"],
            previousChessyPartial: "Knight eight"
        )
        XCTAssertEqual(selection.text, "Knight eight")
        XCTAssertTrue(selection.replacedDigitOnlyBest)
    }

    func testKeepsBestWhenNotDigitOnly() {
        let selection = ASRHypothesisSelector.select(
            best: "Knight eight",
            alternatives: ["Knight eight", "Night eight"],
            previousChessyPartial: "Knight"
        )
        XCTAssertEqual(selection.text, "Knight eight")
        XCTAssertFalse(selection.replacedDigitOnlyBest)
    }

    func testKeepsDigitOnlyBestWhenNoFallbackExists() {
        let selection = ASRHypothesisSelector.select(
            best: "986",
            alternatives: ["986", "989"],
            previousChessyPartial: nil
        )
        XCTAssertEqual(selection.text, "986")
        XCTAssertFalse(selection.replacedDigitOnlyBest)
    }
}
