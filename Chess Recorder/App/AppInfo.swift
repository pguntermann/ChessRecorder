//
//  AppInfo.swift
//  Chess Recorder
//

import Foundation

struct AppAcknowledgment: Identifiable {
    var id: String { name }
    let name: String
    let license: String
    let url: URL
}

enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/pguntermann/ChessRecorder")!

    static var licenseURL: URL {
        repositoryURL.appending(path: "blob/main/LICENSE")
    }

    static var thirdPartyLicensesURL: URL {
        repositoryURL.appending(path: "blob/main/THIRD_PARTY_LICENSES.md")
    }

    static let acknowledgments: [AppAcknowledgment] = [
        AppAcknowledgment(
            name: "ChessKit",
            license: "MIT",
            url: URL(string: "https://github.com/chesskit-app/chesskit-swift")!
        ),
        AppAcknowledgment(
            name: "LucidEngine",
            license: "GPL-3.0",
            url: URL(string: "https://github.com/CarlosDanielDev/lucid-engine")!
        ),
        AppAcknowledgment(
            name: "Stockfish",
            license: "GPL-3.0",
            url: URL(string: "https://stockfishchess.org/")!
        ),
        AppAcknowledgment(
            name: "eco.json",
            license: "MIT",
            url: URL(string: "https://github.com/hayatbiralem/eco.json")!
        ),
        AppAcknowledgment(
            name: "lichess chess-openings",
            license: "CC0",
            url: URL(string: "https://github.com/lichess-org/chess-openings")!
        ),
        AppAcknowledgment(
            name: "cburnett chess pieces",
            license: "CC BY-SA 3.0",
            url: URL(string: "https://commons.wikimedia.org/wiki/Category:SVG_chess_pieces")!
        ),
    ]

    static var displayName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty {
            return name
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return "Chess Recorder"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var versionLabel: String {
        "Version \(version) (\(build))"
    }
}
