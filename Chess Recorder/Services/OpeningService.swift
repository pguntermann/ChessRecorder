//
//  OpeningService.swift
//  Chess Recorder
//

import Foundation
import UIKit

struct OpeningDisplay: Equatable {
    var eco: String
    var name: String

    static let starting = OpeningDisplay(eco: "A00", name: "Starting Position")
    static let unknown = OpeningDisplay(eco: "A00", name: "Unknown Opening")

    var label: String {
        "\(eco) · \(name)"
    }
}

private struct EcoEntry: Decodable {
    let eco: String?
    let name: String?
}

private enum OpeningDataLoader {
    static func load() -> (base: [String: EcoEntry], interpolated: [String: EcoEntry]) {
        let decoder = JSONDecoder()
        return (
            base: loadDatabase(named: "eco_base", decoder: decoder),
            interpolated: loadDatabase(named: "eco_interpolated", decoder: decoder)
        )
    }

    private static func loadDatabase(named name: String, decoder: JSONDecoder) -> [String: EcoEntry] {
        guard let asset = NSDataAsset(name: name),
              let database = try? decoder.decode([String: EcoEntry].self, from: asset.data) else {
            return [:]
        }
        return database
    }
}

@Observable
@MainActor
final class OpeningService {
    private(set) var isLoaded = false
    private(set) var display = OpeningDisplay.starting

    private var ecoBase: [String: EcoEntry] = [:]
    private var ecoInterpolated: [String: EcoEntry] = [:]

    func prepare() async {
        guard !isLoaded else { return }

        let loaded = await Task.detached(priority: .userInitiated) {
            OpeningDataLoader.load()
        }.value

        ecoBase = loaded.base
        ecoInterpolated = loaded.interpolated
        isLoaded = true
    }

    func refresh(game: ChessGame) {
        guard isLoaded else { return }

        if game.moves.isEmpty {
            display = .starting
            return
        }

        display = openingDisplay(forFens: game.fensAfterMoves()) ?? .unknown
    }

    func ecoCode(for moves: [ChessMove]) -> String? {
        guard isLoaded, !moves.isEmpty else { return nil }

        let replayGame = ChessGame()
        guard replayGame.loadMainLine(moves: moves) else { return nil }
        return openingDisplay(forFens: replayGame.fensAfterMoves())?.eco
    }

    private func openingDisplay(forFens fens: [String]) -> OpeningDisplay? {
        var lastKnown: OpeningDisplay?
        for fen in fens {
            if let match = lookupOpening(fen: fen) {
                lastKnown = match
            }
        }
        return lastKnown
    }

    private func lookupOpening(fen: String) -> OpeningDisplay? {
        let entry = ecoInterpolated[fen] ?? ecoBase[fen]
        guard let entry,
              let eco = entry.eco,
              let name = entry.name,
              !eco.isEmpty,
              !name.isEmpty else {
            return nil
        }
        return OpeningDisplay(eco: eco, name: name)
    }
}
