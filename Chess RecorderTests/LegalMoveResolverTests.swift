import ChessKit
import XCTest
@testable import Chess_Recorder

final class LegalMoveResolverTests: XCTestCase {

    func testDisambiguatedKnightCaptureMatchesByFile() {
        let fen = "5k2/8/8/3p3/1N3N2/8/8/4K3 w - - 0 1"
        guard let position = Position(fen: fen) else {
            return XCTFail("Invalid FEN")
        }

        let board = Board(position: position)
        let legalMoves = Self.legalMoves(on: board)

        let bCapture = LegalMoveResolver.match(notation: "Nbxd5", among: legalMoves)
        XCTAssertEqual(bCapture?.start.notation, "b4")

        let fCapture = LegalMoveResolver.match(notation: "Nfxd5", among: legalMoves)
        XCTAssertEqual(fCapture?.start.notation, "f4")
    }

    func testMatchBestReturnsNilForAmbiguousKnightCapture() {
        let fen = "5k2/8/8/3p3/1N3N2/8/8/4K3 w - - 0 1"
        guard let position = Position(fen: fen) else {
            return XCTFail("Invalid FEN")
        }

        let board = Board(position: position)
        let legalMoves = Self.legalMoves(on: board)

        XCTAssertNil(LegalMoveResolver.matchBest(candidates: ["Nxd5"], among: legalMoves))
    }

    func testRequiresExplicitSourceMatch() {
        XCTAssertTrue(LegalMoveResolver.requiresExplicitSourceMatch("Nbxd5"))
        XCTAssertTrue(LegalMoveResolver.requiresExplicitSourceMatch("Ncxe2"))
        XCTAssertFalse(LegalMoveResolver.requiresExplicitSourceMatch("Nf3"))
        XCTAssertFalse(LegalMoveResolver.requiresExplicitSourceMatch("e4"))
    }

    func testPawnFileCaptureDoesNotMatchBishopCaptureWithSameSquare() {
        // Both bxc5 (pawn b4) and Bxc5 (bishop d6) are legal; lowercase notation must pick the pawn.
        let fen = "4k3/8/3B4/2q5/1P6/8/8/RN2K1R w - - 0 1"
        guard let position = Position(fen: fen) else {
            return XCTFail("Invalid FEN")
        }

        let board = Board(position: position)
        let legalMoves = Self.legalMoves(on: board)

        let pawnCapture = LegalMoveResolver.match(notation: "bxc5", among: legalMoves)
        XCTAssertEqual(pawnCapture?.piece.kind, .pawn)
        XCTAssertEqual(pawnCapture?.start.notation, "b4")

        let bishopCapture = LegalMoveResolver.match(notation: "Bxc5", among: legalMoves)
        XCTAssertEqual(bishopCapture?.piece.kind, .bishop)
        XCTAssertEqual(bishopCapture?.start.notation, "d6")
    }

    func testMatchBestPrefersPawnFileCaptureCandidate() {
        let fen = "4k3/8/3B4/2q5/1P6/8/8/RN2K1R w - - 0 1"
        guard let position = Position(fen: fen) else {
            return XCTFail("Invalid FEN")
        }

        let board = Board(position: position)
        let legalMoves = Self.legalMoves(on: board)

        let matched = LegalMoveResolver.matchBest(candidates: ["bxc5", "bxe5"], among: legalMoves)
        XCTAssertEqual(matched?.piece.kind, .pawn)
        XCTAssertEqual(matched?.san, "bxc5")
    }

    private static func legalMoves(on board: Board) -> [Move] {
        var moves: [Move] = []
        let side = board.position.sideToMove

        for piece in board.position.pieces where piece.color == side {
            let start = piece.square
            for end in board.legalMoves(forPieceAt: start) {
                var trialBoard = board
                guard let move = trialBoard.move(pieceAt: start, to: end) else { continue }

                if case .promotion = trialBoard.state {
                    for kind in [Piece.Kind.queen, .rook, .bishop, .knight] {
                        var promotionBoard = board
                        guard promotionBoard.move(pieceAt: start, to: end) != nil else { continue }
                        guard case .promotion(let promotionMove) = promotionBoard.state else { continue }
                        moves.append(promotionBoard.completePromotion(of: promotionMove, to: kind))
                    }
                } else {
                    moves.append(move)
                }
            }
        }

        return moves
    }
}
