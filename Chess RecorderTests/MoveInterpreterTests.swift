import XCTest
@testable import Chess_Recorder

@MainActor
final class MoveInterpreterTests: XCTestCase {

    /// Position after 33... c4 — white to play; "Läufer schlägt c4" should be Bxc4, not bxc4.
    private static let lauferSchlaegtC4GameSANs: [String] = [
        "e4", "c5", "Nf3", "e6", "c4", "Nc6", "d4", "cxd4", "Nxd4", "Nf6",
        "Nxc6", "bxc6", "Bd3", "d5", "Nd2", "d4", "O-O", "e5", "Qa4", "Bd7",
        "Nf3", "c5", "Qa6", "Qb8", "Bg5", "Bc8", "Qa4+", "Bd7", "Qa3", "Qd6",
        "Rae1", "h6", "Bd2", "Be7", "Bc2", "O-O", "Re2", "Rfb8", "Rd1", "Rb7",
        "Ba5", "Rab8", "Bc3", "Bd8", "b3", "Qc7", "Bd2", "Ne8", "Ra1", "f6",
        "Rd1", "Nd6", "Rb1", "Nxc4", "Qa6", "Nxd2", "Rxd2", "Bb5", "Qa3", "Rb6",
        "Rc1", "Ra6", "Qb2", "Qa5", "Bd3", "c4"
    ]

    private func gameAfterBlack33C4() -> ChessGame {
        let game = ChessGame()
        for san in Self.lauferSchlaegtC4GameSANs {
            XCTAssertTrue(game.executeSAN(san), "Failed to play \(san)")
        }
        XCTAssertTrue(game.isAtLatestMove)
        XCTAssertEqual(game.currentTurn, .white)
        return game
    }

    func testLauferSchlaegtC4CandidatesPreferBxc4AfterBlackC4() {
        let game = gameAfterBlack33C4()

        let candidates = MoveInterpreter.candidates(
            from: "Läufer schlägt c4",
            language: .german,
            transcriptAlreadyNormalized: false
        )

        XCTAssertFalse(candidates.isEmpty, "Expected move candidates for \"Läufer schlägt c4\"")
        XCTAssertTrue(
            candidates.contains(where: { $0 == "Bxc4" }),
            "Candidates should include Bxc4, got: \(candidates.joined(separator: ", "))"
        )
        XCTAssertEqual(
            candidates.first,
            "Bxc4",
            "Bxc4 should be the top candidate, got: \(candidates.prefix(5).joined(separator: ", "))"
        )
        XCTAssertNotEqual(
            candidates.first,
            "bxc4",
            "bxc4 must not outrank Bxc4 for \"Läufer schlägt c4\", got: \(candidates.prefix(5).joined(separator: ", "))"
        )

        let matched = game.executeVoiceCandidates(candidates)
        XCTAssertEqual(
            matched?.trimmingCharacters(in: CharacterSet(charactersIn: "+#")),
            "Bxc4",
            "Voice execution should play Bxc4, got: \(matched ?? "nil")"
        )
        XCTAssertNotEqual(matched, "bxc4", "Voice execution must not play pawn bxc4, got: \(matched ?? "nil")")
        XCTAssertEqual(
            game.moves.last?.san.trimmingCharacters(in: CharacterSet(charactersIn: "+#")),
            "Bxc4"
        )
    }

    /// Position after 5... Nc6 — white to play; "Springer d b5" should be Ndb5 (d4→b5), not Nd5 (c3→d5).
    private static let springerDB5GameSANs: [String] = [
        "e4", "c5", "Nf3", "e6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "Nc6"
    ]

    private func gameAfterBlack5Nc6() -> ChessGame {
        let game = ChessGame()
        for san in Self.springerDB5GameSANs {
            XCTAssertTrue(game.executeSAN(san), "Failed to play \(san)")
        }
        XCTAssertTrue(game.isAtLatestMove)
        XCTAssertEqual(game.currentTurn, .white)
        return game
    }

    func testSpringerDB5CandidatesPreferNdb5AfterNc6() {
        let game = gameAfterBlack5Nc6()

        let candidates = MoveInterpreter.candidates(
            from: "Springer d b5",
            language: .german,
            transcriptAlreadyNormalized: false
        )

        XCTAssertFalse(candidates.isEmpty, "Expected move candidates for \"Springer d b5\"")
        XCTAssertTrue(
            candidates.contains(where: { $0.caseInsensitiveCompare("Ndb5") == .orderedSame }),
            "Candidates should include Ndb5, got: \(candidates.joined(separator: ", "))"
        )
        XCTAssertEqual(
            candidates.first?.lowercased(),
            "ndb5",
            "Ndb5 should be the top candidate, got: \(candidates.prefix(5).joined(separator: ", "))"
        )
        XCTAssertFalse(
            candidates.first?.lowercased() == "nd5",
            "Nd5 must not outrank Ndb5 for \"Springer d b5\", got: \(candidates.prefix(5).joined(separator: ", "))"
        )

        let matched = game.executeVoiceCandidates(candidates)
        XCTAssertEqual(matched?.lowercased(), "ndb5", "Voice execution should play Ndb5, got: \(matched ?? "nil")")
        XCTAssertEqual(game.moves.last?.san, "Ndb5")
        XCTAssertEqual(game.moves.last?.from.notation, "d4")
    }

    /// Diagnostic: replays the pipeline with tracing enabled. Run alone in Xcode to inspect console output.
    func testSpringerDB5PipelineTrace() {
        let game = gameAfterBlack5Nc6()
        let tracer = SpeechPipelineTracer(enabled: true)

        let normalized = ChessTranscriptNormalizer.normalizeForPhraseMatching(
            "Springer d b5",
            language: .german,
            tracer: tracer
        )
        let candidates = MoveInterpreter.candidates(
            from: normalized,
            language: .german,
            transcriptAlreadyNormalized: true,
            tracer: tracer
        )
        let matched = game.executeVoiceCandidates(candidates)

        tracer.printReport(
            language: .german,
            acceptedMove: matched,
            rejectedMoves: candidates.filter { $0 != matched }
        )
    }

    /// Position after 26. Rcd1 — black to play; spoken "Turm e8" should be Re8, not Ra8.
    private static let turmE8GameSANs: [String] = [
        "Nf3", "Nf6", "d4", "e6", "e3", "b6", "Be2", "Bb7", "O-O", "d5",
        "b3", "Ba6", "Bb2", "c5", "Nbd2", "h5", "h3", "Qc7", "dxc5", "Bxc5",
        "c4", "Nc6", "Rc1", "O-O", "Bxf6", "gxf6", "Bd3", "Rae8", "Qc2", "Nb4",
        "Bh7+", "Kg7", "Qb1", "f5", "Bxf5", "exf5", "a3", "Nc6", "b4", "f4",
        "bxc5", "fxe3", "fxe3", "Rxe3", "Rfe1", "d4", "cxb6", "Qxb6", "Qa1", "f6",
        "Rcd1"
    ]

    private func gameAfterWhite26Rcd1() -> ChessGame {
        let game = ChessGame()
        for san in Self.turmE8GameSANs {
            XCTAssertTrue(game.executeSAN(san), "Failed to play \(san)")
        }
        XCTAssertTrue(game.isAtLatestMove)
        XCTAssertEqual(game.currentTurn, .black)
        return game
    }

    /// Diagnostic: replays the pipeline with tracing enabled. Run alone in Xcode to inspect console output.
    func testTurmE8PipelineTrace() {
        let game = gameAfterWhite26Rcd1()
        let tracer = SpeechPipelineTracer(enabled: true)

        let normalized = ChessTranscriptNormalizer.normalizeForPhraseMatching(
            "Turm e8",
            language: .german,
            tracer: tracer
        )
        let candidates = MoveInterpreter.candidates(
            from: normalized,
            language: .german,
            transcriptAlreadyNormalized: true,
            tracer: tracer
        )
        let matched = game.executeVoiceCandidates(candidates)

        tracer.printReport(
            language: .german,
            acceptedMove: matched,
            rejectedMoves: candidates.filter { $0 != matched }
        )
    }

    func testTurmE8CandidatesPreferRe8AfterRcd1() {
        let game = gameAfterWhite26Rcd1()

        let candidates = MoveInterpreter.candidates(
            from: "Turm e8",
            language: .german,
            transcriptAlreadyNormalized: false
        )

        XCTAssertFalse(candidates.isEmpty, "Expected move candidates for \"Turm e8\"")
        XCTAssertTrue(
            candidates.contains(where: { $0.caseInsensitiveCompare("Re8") == .orderedSame }),
            "Candidates should include Re8, got: \(candidates.joined(separator: ", "))"
        )
        XCTAssertEqual(
            candidates.first?.lowercased(),
            "re8",
            "Re8 should be the top candidate, got: \(candidates.prefix(5).joined(separator: ", "))"
        )
        XCTAssertFalse(
            candidates.first?.lowercased() == "ra8",
            "Ra8 must not outrank Re8 for \"Turm e8\", got: \(candidates.prefix(5).joined(separator: ", "))"
        )

        let matched = game.executeVoiceCandidates(candidates)
        XCTAssertEqual(matched?.lowercased(), "ree8", "Voice execution should play Ree8, got: \(matched ?? "nil")")
        XCTAssertEqual(game.moves.last?.san, "Ree8")
    }

    func testTurmE8SpacedTokensPreferRe8AfterRcd1() {
        let game = gameAfterWhite26Rcd1()

        let candidates = MoveInterpreter.candidates(
            from: "turm e 8",
            language: .german,
            transcriptAlreadyNormalized: false
        )

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertEqual(
            candidates.first?.lowercased(),
            "re8",
            "Split \"turm e 8\" should still prefer Re8, got: \(candidates.prefix(5).joined(separator: ", "))"
        )

        let matched = game.executeVoiceCandidates(candidates)
        XCTAssertEqual(matched?.lowercased(), "ree8")
        XCTAssertEqual(game.moves.last?.san, "Ree8")
    }

    func testTurmF3CandidatesPreferRf3NotPawnF3() {
        for utterance in ["Turm f3", "turm f3", "turmf3"] {
            let candidates = MoveInterpreter.candidates(
                from: utterance,
                language: .german,
                transcriptAlreadyNormalized: false
            )
            XCTAssertFalse(candidates.isEmpty, "Expected candidates for \"\(utterance)\"")
            XCTAssertTrue(
                candidates.contains(where: { $0 == "Rf3" }),
                "\"\(utterance)\" should include Rf3, got: \(candidates.joined(separator: ", "))"
            )
            XCTAssertEqual(
                candidates.first,
                "Rf3",
                "\"\(utterance)\" should prefer Rf3 over pawn f3, got: \(candidates.prefix(5).joined(separator: ", "))"
            )
        }
    }

    func testRookF3CandidatesPreferRf3NotPawnF3() {
        for utterance in ["Rook f3", "rook f3", "rookf3"] {
            let candidates = MoveInterpreter.candidates(
                from: utterance,
                language: .english,
                transcriptAlreadyNormalized: false
            )
            XCTAssertFalse(candidates.isEmpty, "Expected candidates for \"\(utterance)\"")
            XCTAssertTrue(
                candidates.contains(where: { $0 == "Rf3" }),
                "\"\(utterance)\" should include Rf3, got: \(candidates.joined(separator: ", "))"
            )
            XCTAssertEqual(
                candidates.first,
                "Rf3",
                "\"\(utterance)\" should prefer Rf3 over pawn f3, got: \(candidates.prefix(5).joined(separator: ", "))"
            )
        }
    }
}
