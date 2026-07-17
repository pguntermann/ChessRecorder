//
//  GameAccuracySummary.swift
//  Chess Recorder
//

import Foundation

/// Aggregated move-quality stats for a recorded game.
///
/// Accuracy uses average centipawn loss: `clamp(100 - avgCPL / 3.5, 5, 100)`.
/// Book moves are excluded from the average and reported separately.
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
            if goodCount > 0 {
                parts.append(goodCount == 1 ? "1 good" : "\(goodCount) good")
            }
            if inaccuracyCount > 0 {
                parts.append(inaccuracyCount == 1 ? "1 inaccuracy" : "\(inaccuracyCount) inaccuracies")
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

        var inaccuraciesText: String {
            inaccuracyCount > 0 ? "\(inaccuracyCount)" : "—"
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

    /// Piecewise X mapping that compresses book moves before the first scored point.
    ///
    /// Example: first scored move at 6 → a short `0...5` prefix, then 6, 7, …
    struct AccuracyProgressXScale: Equatable, Sendable {
        /// Full-move number of the first scored (non-book) progress point.
        let firstScoredMove: Int
        /// Visual width of the compressed book prefix, in plot units (≈ one scored-move step).
        let compressedUnits: Double

        /// Last full-move still in book (or before first score). `nil` when nothing to compress.
        var bookEndMove: Int? {
            guard isCompressed else { return nil }
            return firstScoredMove - 1
        }

        /// Compress whenever at least two full moves precede the first scored point.
        var isCompressed: Bool {
            firstScoredMove >= 3
        }

        init(progress: [AccuracyProgressPoint], compressedUnits: Double = 0.28) {
            let first = progress.map(\.moveNumber).min() ?? 1
            self.firstScoredMove = first
            self.compressedUnits = max(compressedUnits, 0.15)
        }

        func plotX(moveNumber: Int) -> Double {
            guard isCompressed, let bookEnd = bookEndMove else {
                return Double(moveNumber)
            }
            if moveNumber <= bookEnd {
                guard bookEnd > 0 else { return 0 }
                return Double(moveNumber) / Double(bookEnd) * compressedUnits
            }
            return compressedUnits + Double(moveNumber - bookEnd)
        }

        func domain(maxMoveNumber: Int) -> ClosedRange<Double> {
            let upper = plotX(moveNumber: max(maxMoveNumber, firstScoredMove))
            let lower = isCompressed ? 0 : plotX(moveNumber: firstScoredMove)
            return lower...max(upper, lower + 1)
        }

        /// Axis ticks: optional compressed opening label, then consecutive move numbers (sampled if long).
        func axisMarks(scoredMoves: [Int], desiredCount: Int = 6) -> [(x: Double, label: String)] {
            let uniqueSorted = Array(Set(scoredMoves)).sorted()
            guard let lo = uniqueSorted.first, let hi = uniqueSorted.last else { return [] }

            var marks: [(Double, String)] = []
            if isCompressed, let bookEnd = bookEndMove {
                // Pin to the leading edge so the wide "0...N" text doesn't sit on the first move tick.
                marks.append((0, "0...\(bookEnd)"))
            }

            // Include every full-move in range so gaps like 4 → 6 don't leave a blank tick.
            // When compressed, skip the first scored move — it sits too close to "0...N".
            for move in sampleMoveNumbers(from: lo, through: hi, desiredCount: desiredCount) {
                if isCompressed, move == firstScoredMove { continue }
                marks.append((plotX(moveNumber: move), "\(move)"))
            }
            return marks
        }

        func label(forAxisValue value: Double, in marks: [(x: Double, label: String)]) -> String? {
            marks.min(by: { abs($0.x - value) < abs($1.x - value) })
                .flatMap { abs($0.x - value) <= 0.05 ? $0.label : nil }
        }

        private func sampleMoveNumbers(from lo: Int, through hi: Int, desiredCount: Int) -> [Int] {
            let span = hi - lo
            guard span > 0 else { return [lo] }
            if span + 1 <= desiredCount {
                return Array(lo...hi)
            }
            var picked: [Int] = []
            for i in 0..<desiredCount {
                let value = lo + Int((Double(i) / Double(desiredCount - 1) * Double(span)).rounded())
                if picked.last != value {
                    picked.append(value)
                }
            }
            return picked
        }
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
        if inaccuracyCount > 0 { columns.append(.inaccuracies) }
        if mistakeCount > 0 { columns.append(.mistakes) }
        if blunderCount > 0 { columns.append(.blunders) }
        if missCount > 0 { columns.append(.misses) }
        return columns
    }

    enum CompactTableColumn: Equatable, Sendable {
        case accuracy
        case book
        case good
        case inaccuracies
        case mistakes
        case blunders
        case misses

        var title: String {
            switch self {
            case .accuracy: return "Acc"
            case .book: return "Book"
            case .good: return "Good"
            case .inaccuracies: return "Inac"
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
            case .inaccuracies: return side.inaccuraciesText
            case .mistakes: return side.mistakesText
            case .blunders: return side.blundersText
            case .misses: return side.missesText
            }
        }
    }

    init(moves: [ChessMove]) {
        var white = SideStats()
        var black = SideStats()
        var whiteCPL = 0.0
        var blackCPL = 0.0
        var progress: [AccuracyProgressPoint] = []

        for (index, move) in moves.enumerated() {
            guard let quality = move.quality else { continue }
            let side: Side = index % 2 == 0 ? .white : .black
            let moveNumber = index / 2 + 1

            if side == .white {
                Self.apply(move, quality: quality, to: &white, cplSum: &whiteCPL)
                if let point = Self.progressPoint(
                    side: .white,
                    moveNumber: moveNumber,
                    contributedToAccuracy: quality != .book,
                    totalCPL: whiteCPL,
                    scoredMoves: white.scoredMoveCount
                ) {
                    progress.append(point)
                }
            } else {
                Self.apply(move, quality: quality, to: &black, cplSum: &blackCPL)
                if let point = Self.progressPoint(
                    side: .black,
                    moveNumber: moveNumber,
                    contributedToAccuracy: quality != .book,
                    totalCPL: blackCPL,
                    scoredMoves: black.scoredMoveCount
                ) {
                    progress.append(point)
                }
            }
        }

        white.accuracyPercent = Self.percent(totalCPL: whiteCPL, scoredMoves: white.scoredMoveCount)
        black.accuracyPercent = Self.percent(totalCPL: blackCPL, scoredMoves: black.scoredMoveCount)

        self.white = white
        self.black = black
        self.accuracyProgress = progress
    }

    /// Divisor used by `100 - averageCPL / divisor`, matching common CPL accuracy curves.
    static let averageCPLDivisor: Double = 3.5
    /// Per-move CPL cap before averaging (same as CARA) so mate-scale losses don't floor accuracy at 5%.
    static let averageCPLCap: Double = 500
    static let minimumAccuracyPercent: Double = 5
    static let maximumAccuracyPercent: Double = 100

    /// Effective CPL for accuracy. Book is excluded. Values are capped at `averageCPLCap`.
    /// Legacy qualities without stored CPL map from the previous point scores via `(100 - points) * 3.5`.
    static func effectiveCentipawnLoss(for move: ChessMove, quality: MoveQuality) -> Double? {
        guard quality != .book else { return nil }
        let uncapped: Double
        if let cpl = move.centipawnLoss {
            uncapped = Double(max(0, cpl))
        } else if let points = legacyPointScore(for: quality) {
            uncapped = (maximumAccuracyPercent - points) * averageCPLDivisor
        } else {
            return nil
        }
        return min(uncapped, averageCPLCap)
    }

    /// Former discrete point scores, kept only for legacy moves that lack stored CPL.
    static func legacyPointScore(for quality: MoveQuality) -> Double? {
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
        contributedToAccuracy: Bool,
        totalCPL: Double,
        scoredMoves: Int
    ) -> AccuracyProgressPoint? {
        guard contributedToAccuracy,
              let accuracy = percent(totalCPL: totalCPL, scoredMoves: scoredMoves) else {
            return nil
        }
        return AccuracyProgressPoint(
            side: side,
            moveNumber: moveNumber,
            accuracyPercent: Double(accuracy)
        )
    }

    private static func apply(
        _ move: ChessMove,
        quality: MoveQuality,
        to side: inout SideStats,
        cplSum: inout Double
    ) {
        switch quality {
        case .book:
            side.bookCount += 1
        case .good:
            side.goodCount += 1
        case .inaccuracy:
            side.inaccuracyCount += 1
        case .miss:
            side.missCount += 1
        case .mistake:
            side.mistakeCount += 1
        case .blunder:
            side.blunderCount += 1
        }

        guard let cpl = effectiveCentipawnLoss(for: move, quality: quality) else { return }
        side.scoredMoveCount += 1
        cplSum += cpl
    }

    /// `clamp(100 - averageCPL / 3.5, 5, 100)`, rounded to nearest int.
    static func percent(totalCPL: Double, scoredMoves: Int) -> Int? {
        guard scoredMoves > 0 else { return nil }
        let averageCPL = totalCPL / Double(scoredMoves)
        let raw = maximumAccuracyPercent - (averageCPL / averageCPLDivisor)
        return Int(max(minimumAccuracyPercent, min(maximumAccuracyPercent, raw)).rounded())
    }
}
