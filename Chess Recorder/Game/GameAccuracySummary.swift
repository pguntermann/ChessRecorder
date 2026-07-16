//
//  GameAccuracySummary.swift
//  Chess Recorder
//

import Foundation

/// Aggregated move-quality stats for a recorded game.
///
/// Accuracy averages scored moves only (excludes book). Book moves are reported
/// separately so opening theory does not inflate or dilute the percentage.
struct GameAccuracySummary: Equatable, Sendable {
    enum Side: String, Equatable, Hashable, Sendable, CaseIterable {
        case white
        case black

        var label: String {
            switch self {
            case .white: return "White"
            case .black: return "Black"
            }
        }
    }

    struct SideStats: Equatable, Sendable {
        var scoredMoveCount: Int = 0
        var accuracyPercent: Int? = nil
        var goodCount: Int = 0
        var inaccuracyCount: Int = 0
        var mistakeCount: Int = 0
        var blunderCount: Int = 0
        var missCount: Int = 0
        var bookCount: Int = 0

        var assessedMoveCount: Int {
            scoredMoveCount + bookCount
        }

        var hasContent: Bool {
            assessedMoveCount > 0
        }

        /// Compact line for one side, e.g. `Accuracy 88% · 4 book · 1 mistake`.
        var compactLabel: String {
            var parts: [String] = []
            if let accuracyPercent {
                parts.append("Accuracy \(accuracyPercent)%")
            }
            if bookCount > 0 {
                parts.append("\(bookCount) book")
            }
            if mistakeCount > 0 {
                parts.append(mistakeCount == 1 ? "1 mistake" : "\(mistakeCount) mistakes")
            }
            if blunderCount > 0 {
                parts.append(blunderCount == 1 ? "1 blunder" : "\(blunderCount) blunders")
            }
            if missCount > 0 {
                parts.append(missCount == 1 ? "1 miss" : "\(missCount) misses")
            }
            if parts.isEmpty, inaccuracyCount > 0 {
                parts.append(inaccuracyCount == 1 ? "1 inaccuracy" : "\(inaccuracyCount) inaccuracies")
            }
            if parts.isEmpty, goodCount > 0 {
                parts.append(goodCount == 1 ? "1 good move" : "\(goodCount) good moves")
            }
            return parts.joined(separator: " · ")
        }

        var accuracyText: String {
            accuracyPercent.map { "\($0)%" } ?? "—"
        }

        var bookText: String {
            bookCount > 0 ? "\(bookCount)" : "—"
        }

        var goodText: String {
            goodCount > 0 ? "\(goodCount)" : "—"
        }

        var mistakesText: String {
            mistakeCount > 0 ? "\(mistakeCount)" : "—"
        }

        var blundersText: String {
            blunderCount > 0 ? "\(blunderCount)" : "—"
        }

        var missesText: String {
            missCount > 0 ? "\(missCount)" : "—"
        }

        /// Non-zero quality slices for pie charts (includes book).
        var qualitySlices: [QualitySlice] {
            [
                QualitySlice(quality: .book, count: bookCount),
                QualitySlice(quality: .good, count: goodCount),
                QualitySlice(quality: .inaccuracy, count: inaccuracyCount),
                QualitySlice(quality: .mistake, count: mistakeCount),
                QualitySlice(quality: .blunder, count: blunderCount),
                QualitySlice(quality: .miss, count: missCount)
            ]
            .filter { $0.count > 0 }
        }
    }

    struct QualitySlice: Equatable, Sendable, Identifiable {
        let quality: MoveQuality
        let count: Int

        var id: String { quality.rawValue }

        var label: String {
            switch quality {
            case .good: return "Good"
            case .book: return "Book"
            case .inaccuracy: return "Inaccuracy"
            case .mistake: return "Mistake"
            case .blunder: return "Blunder"
            case .miss: return "Miss"
            }
        }
    }

    /// Running accuracy for one side after a scored move, plotted against game move number.
    struct AccuracyProgressPoint: Equatable, Sendable, Identifiable {
        let side: Side
        /// Full-move number (1-based), e.g. 1 for 1.e4 / 1...e5.
        let moveNumber: Int
        let accuracyPercent: Double

        var id: String { "\(side.rawValue)-\(moveNumber)-\(accuracyPercent)" }
    }

    var white: SideStats
    var black: SideStats
    /// Chronological running accuracy for White and Black (scored moves only).
    var accuracyProgress: [AccuracyProgressPoint]

    var assessedMoveCount: Int {
        white.assessedMoveCount + black.assessedMoveCount
    }

    var scoredMoveCount: Int {
        white.scoredMoveCount + black.scoredMoveCount
    }

    var bookMoveCount: Int {
        white.bookCount + black.bookCount
    }

    var goodCount: Int { white.goodCount + black.goodCount }
    var inaccuracyCount: Int { white.inaccuracyCount + black.inaccuracyCount }
    var mistakeCount: Int { white.mistakeCount + black.mistakeCount }
    var blunderCount: Int { white.blunderCount + black.blunderCount }
    var missCount: Int { white.missCount + black.missCount }

    var hasContent: Bool {
        assessedMoveCount > 0
    }

    var hasAccuracyProgress: Bool {
        accuracyProgress.count >= 2
    }

    /// Columns shown in the compact PGN header table (only those with any data).
    var compactTableColumns: [CompactTableColumn] {
        var columns: [CompactTableColumn] = [.accuracy]
        if bookMoveCount > 0 { columns.append(.book) }
        if goodCount > 0 { columns.append(.good) }
        if mistakeCount > 0 { columns.append(.mistakes) }
        if blunderCount > 0 { columns.append(.blunders) }
        if missCount > 0 { columns.append(.misses) }
        return columns
    }

    enum CompactTableColumn: Equatable, Sendable {
        case accuracy
        case book
        case good
        case mistakes
        case blunders
        case misses

        var title: String {
            switch self {
            case .accuracy: return "Acc"
            case .book: return "Book"
            case .good: return "Good"
            case .mistakes: return "Mist"
            case .blunders: return "Blun"
            case .misses: return "Miss"
            }
        }

        func value(for side: SideStats) -> String {
            switch self {
            case .accuracy: return side.accuracyText
            case .book: return side.bookText
            case .good: return side.goodText
            case .mistakes: return side.mistakesText
            case .blunders: return side.blundersText
            case .misses: return side.missesText
            }
        }
    }

    init(moves: [ChessMove]) {
        var white = SideStats()
        var black = SideStats()
        var whiteScore = 0.0
        var blackScore = 0.0
        var progress: [AccuracyProgressPoint] = []

        for (index, move) in moves.enumerated() {
            guard let quality = move.quality else { continue }
            let side: Side = index % 2 == 0 ? .white : .black
            let moveNumber = index / 2 + 1

            if side == .white {
                Self.apply(quality, to: &white, scoreSum: &whiteScore)
                if let point = Self.progressPoint(
                    side: .white,
                    moveNumber: moveNumber,
                    quality: quality,
                    totalScore: whiteScore,
                    scoredMoves: white.scoredMoveCount
                ) {
                    progress.append(point)
                }
            } else {
                Self.apply(quality, to: &black, scoreSum: &blackScore)
                if let point = Self.progressPoint(
                    side: .black,
                    moveNumber: moveNumber,
                    quality: quality,
                    totalScore: blackScore,
                    scoredMoves: black.scoredMoveCount
                ) {
                    progress.append(point)
                }
            }
        }

        white.accuracyPercent = Self.percent(totalScore: whiteScore, scoredMoves: white.scoredMoveCount)
        black.accuracyPercent = Self.percent(totalScore: blackScore, scoredMoves: black.scoredMoveCount)

        self.white = white
        self.black = black
        self.accuracyProgress = progress
    }

    /// Point contribution used for the accuracy average (book excluded).
    static func score(for quality: MoveQuality) -> Double? {
        switch quality {
        case .book: return nil
        case .good: return 100
        case .inaccuracy: return 80
        case .miss: return 70
        case .mistake: return 50
        case .blunder: return 20
        }
    }

    private static func progressPoint(
        side: Side,
        moveNumber: Int,
        quality: MoveQuality,
        totalScore: Double,
        scoredMoves: Int
    ) -> AccuracyProgressPoint? {
        guard score(for: quality) != nil,
              let accuracy = percent(totalScore: totalScore, scoredMoves: scoredMoves) else {
            return nil
        }
        return AccuracyProgressPoint(
            side: side,
            moveNumber: moveNumber,
            accuracyPercent: Double(accuracy)
        )
    }

    private static func apply(_ quality: MoveQuality, to side: inout SideStats, scoreSum: inout Double) {
        switch quality {
        case .book:
            side.bookCount += 1
        case .good:
            side.goodCount += 1
            side.scoredMoveCount += 1
            scoreSum += 100
        case .inaccuracy:
            side.inaccuracyCount += 1
            side.scoredMoveCount += 1
            scoreSum += 80
        case .miss:
            side.missCount += 1
            side.scoredMoveCount += 1
            scoreSum += 70
        case .mistake:
            side.mistakeCount += 1
            side.scoredMoveCount += 1
            scoreSum += 50
        case .blunder:
            side.blunderCount += 1
            side.scoredMoveCount += 1
            scoreSum += 20
        }
    }

    private static func percent(totalScore: Double, scoredMoves: Int) -> Int? {
        guard scoredMoves > 0 else { return nil }
        return Int((totalScore / Double(scoredMoves)).rounded())
    }
}
