import XCTest
import LucidEngine
@testable import Chess_Recorder

/// Regression fixture: late mating move from a game that previously marked
/// almost every Black move as a blunder while delivering mate.
@MainActor
final class MoveAssessmentExampleGameTests: XCTestCase {

    /// Clean movetext from the reported game (assessment symbols removed).
    private static let examplePGN = """
        1. e4 c5 2. Nf3 e6 3. c3 Nc6 4. d3 d5 5. Nbd2 d4 6. cxd4 Nxd4 7. Nxd4 cxd4 \
        8. e5 Qa5 9. f4 f6 10. Qe2 Ne7 11. h3 Nd5 12. Qf2 Be7 13. Be2 O-O 14. Qxd4 fxe5 \
        15. fxe5 Rf4 16. Qg1 Bc5 17. b4 Qxb4 18. a3 Qb5 19. d4 Qa5 20. dxc5 Qc3 \
        21. Bb2 Qxb2 22. Nb3 Qc3+ 23. Kd1 Ne3+ 24. Qxe3 Qxe3 25. Nd2 Bd7 26. Rb1 Bc6 \
        27. Nc4 Qd4+ 28. Kc2 Raf8 29. Rbd1 Qxc5 30. Bf1 Bd5 31. g3 Rf2+ 32. Rd2 Bxc4 \
        33. Bd3 Rxd2+ 34. Kxd2 Bxd3 35. a4 Qc2+ 36. Ke3 Rf5 37. Rg1 Rxe5+ 38. Kf4 Rf5+ \
        39. Ke3 Qc5+ 40. Kxd3 Qxg1 41. g4 Rf4 42. a5 Qe1 43. a6 bxa6 44. Kc2 Rd4 \
        45. Kb2 Rc4 46. Ka2 Qb4 47. g5 Rc5 48. g6 Ra5#
        """

    /// 48... Ra5# — delivering mate must not be classified as a blunder.
    private static let matingMoveIndex = 95

    func testExampleGameMatingMoveIsNotBlunder() async throws {
        let game = replayExampleGame()
        XCTAssertEqual(game.moves.count, 96)
        XCTAssertEqual(normalizedSAN(game.moves[Self.matingMoveIndex].san), "Ra5")
        XCTAssertTrue(game.moves[Self.matingMoveIndex].isCheckmate)

        let fens = game.fenSequenceFromStart()
        let configuration = try EngineConfiguration(
            defaultDepth: 10,
            threadCount: 1,
            hashSizeMB: 16,
            timeoutSeconds: 60
        )
        let engine = MoveAssessmentEngine(configuration: configuration)
        try await engine.prepare()

        let result: MoveAssessmentResult
        do {
            result = try await engine.assessMove(
                fenBefore: fens[Self.matingMoveIndex],
                fenAfter: fens[Self.matingMoveIndex + 1],
                depth: 10
            )
        } catch {
            await engine.shutdown()
            throw error
        }
        await engine.shutdown()

        XCTAssertEqual(
            result.quality,
            .good,
            """
            Ra5# should be good; got \(result.quality) cpl=\(result.centipawnLoss) \
            before=\(String(describing: result.scoreBefore)) \
            rawAfter=\(String(describing: result.rawScoreAfter))
            """
        )
    }

    private func replayExampleGame() -> ChessGame {
        let sans = Self.parseSANs(from: Self.examplePGN)
        let game = ChessGame()
        for san in sans {
            XCTAssertTrue(game.executeSAN(san), "Failed to play \(san)")
        }
        return game
    }

    private func normalizedSAN(_ san: String?) -> String {
        guard var value = san else { return "" }
        while let last = value.last, "+#!?".contains(last) {
            value.removeLast()
        }
        return value
    }

    private static func parseSANs(from pgn: String) -> [String] {
        pgn
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                guard let first = token.first else { return false }
                if first.isNumber { return false }
                return true
            }
            .map { token in
                var san = token
                while san.last == "." { san.removeLast() }
                return san
            }
    }
}
