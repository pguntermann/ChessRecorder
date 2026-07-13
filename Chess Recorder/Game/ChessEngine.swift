//
//  ChessEngine.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import Foundation

class ChessEngine {
    let game: ChessGame

    init(game: ChessGame) {
        self.game = game
    }

    func executeMove(notation: String) -> Bool {
        let success = game.executeSAN(notation)
        if !success {
            print("Could not execute move '\(notation)'")
        }
        return success
    }

    @discardableResult
    func executeVoiceCandidates(_ candidates: [String], preferCaptures: Bool = false) -> String? {
        guard let matched = game.executeVoiceCandidates(candidates, preferCaptures: preferCaptures) else {
            print("Could not execute voice candidates: \(candidates.joined(separator: ", "))")
            return nil
        }
        return matched
    }

    func legalDestinations(from: ChessPosition) -> [ChessPosition] {
        game.legalDestinations(from: from)
    }

    func requiresPromotion(from: ChessPosition, to: ChessPosition) -> Bool {
        game.requiresPromotion(from: from, to: to)
    }

    @discardableResult
    func executeTouchMove(
        from: ChessPosition,
        to: ChessPosition,
        promotion: PieceType? = nil
    ) -> Bool {
        game.performMove(from: from, to: to, promotion: promotion)
    }
}
