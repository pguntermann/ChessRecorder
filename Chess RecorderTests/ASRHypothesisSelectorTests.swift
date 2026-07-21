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

    func testRejectsLetterTripleDigitHypotheses() {
        XCTAssertTrue(ASRHypothesisSelector.isRejectableLetterTripleDigitHypothesis("C554"))
        XCTAssertTrue(ASRHypothesisSelector.isRejectableLetterTripleDigitHypothesis("c 5 5 4"))
        XCTAssertFalse(ASRHypothesisSelector.isRejectableLetterTripleDigitHypothesis("C5D4"))
        XCTAssertFalse(ASRHypothesisSelector.isRejectableLetterTripleDigitHypothesis("C5"))
        XCTAssertFalse(ASRHypothesisSelector.isRejectableLetterTripleDigitHypothesis("554"))
        XCTAssertFalse(ASRHypothesisSelector.isRejectableLetterTripleDigitHypothesis("Knight 554"))
    }

    func testLooksLikeCoordinatePair() {
        XCTAssertTrue(ASRHypothesisSelector.looksLikeCoordinatePair("C5D4"))
        XCTAssertTrue(ASRHypothesisSelector.looksLikeCoordinatePair("c 5 d 4"))
        XCTAssertFalse(ASRHypothesisSelector.looksLikeCoordinatePair("C554"))
        XCTAssertFalse(ASRHypothesisSelector.looksLikeCoordinatePair("C5"))
    }

    func testPrefersCoordinatePairNBestOverLetterTripleDigitBest() {
        let selection = ASRHypothesisSelector.select(
            best: "C554",
            alternatives: ["C554", "C5D4"],
            previousChessyPartial: "C5"
        )
        XCTAssertEqual(selection.text, "C5D4")
        XCTAssertTrue(selection.replacedDigitOnlyBest)
    }

    func testFallsBackToPreviousCoordinatePairForLetterTripleDigitBest() {
        let selection = ASRHypothesisSelector.select(
            best: "C554",
            alternatives: ["C554"],
            previousChessyPartial: "C5D4"
        )
        XCTAssertEqual(selection.text, "C5D4")
        XCTAssertTrue(selection.replacedDigitOnlyBest)
    }

    func testKeepsLetterTripleDigitBestWhenNoCoordinatePairFallback() {
        let selection = ASRHypothesisSelector.select(
            best: "C554",
            alternatives: ["C554", "Knight"],
            previousChessyPartial: "C5"
        )
        XCTAssertEqual(selection.text, "C554")
        XCTAssertFalse(selection.replacedDigitOnlyBest)
    }
}
