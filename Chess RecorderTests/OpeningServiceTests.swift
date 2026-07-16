import XCTest
@testable import Chess_Recorder

@MainActor
final class OpeningServiceTests: XCTestCase {

    private static let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    func testStartingPositionHasBookContinuations() async {
        let service = OpeningService()
        await service.prepare()
        XCTAssertTrue(service.isLoaded)
        XCTAssertGreaterThan(service.indexedBookPositionCount, 1000, "ECO databases should load from the app bundle")

        let continuations = service.continuations(from: Self.startingFEN)
        XCTAssertFalse(continuations.isEmpty, "Starting position should have book moves like e4/d4")
        XCTAssertLessThanOrEqual(continuations.count, OpeningService.maxContinuationsPerNode)

        let sans = Set(continuations.map(\.san))
        XCTAssertTrue(sans.contains("e4") || sans.contains("d4") || sans.contains("Nf3"))

        for continuation in continuations {
            XCTAssertFalse(continuation.display.name.isEmpty)
            XCTAssertFalse(continuation.display.eco.isEmpty)
            XCTAssertTrue(service.isBookPosition(fen: continuation.fenAfter))
        }
    }

    func testContinuationChildrenCanBeExpanded() async {
        let service = OpeningService()
        await service.prepare()

        let root = service.continuations(from: Self.startingFEN)
        guard let e4 = root.first(where: { $0.san == "e4" }) else {
            XCTFail("Expected e4 continuation from starting position")
            return
        }
        XCTAssertEqual(e4.from.notation, "e2")
        XCTAssertEqual(e4.to.notation, "e4")

        let afterE4 = service.continuations(from: e4.fenAfter)
        XCTAssertFalse(afterE4.isEmpty, "After 1.e4 there should be book replies")
        XCTAssertTrue(afterE4.contains(where: { ["e5", "c5", "e6", "c6"].contains($0.san) }))
    }

    func testRefreshTracksInBookState() async {
        let service = OpeningService()
        await service.prepare()

        let game = ChessGame()
        service.refresh(game: game)
        XCTAssertTrue(service.isInBook)
        XCTAssertEqual(service.display.name, "Starting Position")
        XCTAssertNotNil(service.currentBookFEN)

        XCTAssertTrue(game.executeSAN("e4"))
        service.refresh(game: game)
        XCTAssertTrue(service.isInBook)
        XCTAssertNotNil(service.currentBookFEN)
        XCTAssertNotEqual(service.display.name, "Starting Position")
        XCTAssertGreaterThanOrEqual(service.pathToCurrent.count, 2)
        XCTAssertEqual(service.pathToCurrent.first?.display.name, "Starting Position")
        XCTAssertEqual(service.pathToCurrent.last?.moveSAN, "e4")
    }

    func testPathTracksOpeningTransitions() async {
        let service = OpeningService()
        await service.prepare()

        let game = ChessGame()
        XCTAssertTrue(game.executeSAN("e4"))
        XCTAssertTrue(game.executeSAN("e5"))
        XCTAssertTrue(game.executeSAN("Nf3"))
        service.refresh(game: game)

        let path = service.pathToCurrent
        XCTAssertGreaterThanOrEqual(path.count, 2)
        XCTAssertNil(path.first?.moveSAN)
        XCTAssertEqual(path.first?.display, .starting)

        let transitionSANs = path.compactMap(\.moveSAN)
        XCTAssertTrue(transitionSANs.contains("e4"))
        // Distinct opening labels only — consecutive identical names are collapsed.
        let labels = path.map(\.display.label)
        XCTAssertEqual(labels.count, Set(labels).count)
    }
}