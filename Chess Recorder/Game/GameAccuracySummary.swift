//
//  GameAccuracySummary.swift
//  Chess Recorder
//

import Foundation
import LucidEngine

/// Aggregated move-quality stats for a recorded game.
///
/// Accuracy uses winning-chance (Win%) drop per move, then aggregates with a
/// volatility-weighted mean and harmonic mean. Book moves are excluded from
/// accuracy and reported separately. Average CPL remains an overview metric.
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
        /// Average effective CPL over scored (non-book) moves.
        var averageCentipawnLoss: Double? = nil
        /// Share of scored moves with 0 CPL (engine best / equal).
        var bestMovePercent: Int? = nil
        /// Blunders as a percent of all assessed moves (including book).
        var blunderRatePercent: Int? = nil
        var bestMoveCount: Int = 0
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

        var averageCPLText: String {
            guard let averageCentipawnLoss else { return "—" }
            return "\(Int(averageCentipawnLoss.rounded()))"
        }

        var bestMoveText: String {
            bestMovePercent.map { "\($0)%" } ?? "—"
        }

        var blunderRateText: String {
            blunderRatePercent.map { "\($0)%" } ?? "—"
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

        mutating func finalizeOverviewStats(totalCPL: Double) {
            if scoredMoveCount > 0 {
                averageCentipawnLoss = totalCPL / Double(scoredMoveCount)
                bestMovePercent = Int((Double(bestMoveCount) / Double(scoredMoveCount) * 100).rounded())
            } else {
                averageCentipawnLoss = nil
                bestMovePercent = nil
            }
            if assessedMoveCount > 0 {
                blunderRatePercent = Int((Double(blunderCount) / Double(assessedMoveCount) * 100).rounded())
            } else {
                blunderRatePercent = nil
            }
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

    /// How accuracy progress is plotted over the game.
    enum AccuracyProgressMode: String, Equatable, Sendable, CaseIterable, Identifiable {
        /// Accuracy if the game had ended after each scored move (can rise or fall).
        case running
        /// Path of damage toward the current accuracy (only flat or down).
        case cumulative

        var id: String { rawValue }

        var title: String {
            switch self {
            case .running: return "Running"
            case .cumulative: return "Cumulative"
            }
        }

        var chartFooter: String {
            switch self {
            case .running:
                return "Accuracy if the game had ended at each move (can go up or down)."
            case .cumulative:
                return "How the current accuracy was lost over time (only flat or down)."
            }
        }
    }

    /// Accuracy for one side after a scored move, plotted against game move number.
    struct AccuracyProgressPoint: Equatable, Sendable, Identifiable {
        let side: Side
        /// Full-move number (1-based), e.g. 1 for 1.e4 / 1...e5.
        let moveNumber: Int
        let accuracyPercent: Double

        var id: String { "\(side.rawValue)-\(moveNumber)-\(accuracyPercent)" }
    }

    /// White-POV evaluation after a ply, in pawns (already clamped for display).
    struct EvaluationPoint: Equatable, Sendable, Identifiable {
        /// Half-move index: 0 = start, 1 = after White's first move, …
        let ply: Int
        /// Evaluation in pawns from White's perspective, clamped to ±`evaluationScaleCapPawns`.
        let evaluationPawns: Double

        var id: Int { ply }

        /// Full-move number for axis labeling (ply 1–2 → 1, ply 3–4 → 2, …).
        var moveNumber: Int {
            max(1, (ply + 1) / 2)
        }
    }

    struct EvaluationPhaseTransition: Equatable, Sendable, Identifiable {
        enum Kind: String, Equatable, Sendable {
            case middlegame
            case endgame
        }

        let kind: Kind
        /// Half-move index where the phase begins.
        let ply: Int

        var id: String { "\(kind.rawValue)-\(ply)" }

        var label: String {
            switch kind {
            case .middlegame: return "Middlegame"
            case .endgame: return "Endgame"
            }
        }
    }

    struct EvaluationCriticalPly: Equatable, Sendable, Identifiable {
        let ply: Int
        let quality: MoveQuality

        var id: Int { ply }
    }

    /// Piecewise X mapping that compresses book moves before the first scored point.
    ///
    /// Example: first scored move at 8 → a short `0...7` prefix, then 8, 9, …
    /// The book strip scales with game length so the first scored point does not sit on top of `0...N`.
    struct AccuracyProgressXScale: Equatable, Sendable {
        /// Full-move number of the first scored (non-book) progress point.
        let firstScoredMove: Int
        /// Visual width of the compressed book prefix, in plot units (≈ scored-move steps).
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

        /// Enough room after `0...N` to also label the first scored move.
        var showsFirstScoredAxisLabel: Bool {
            isCompressed && compressedUnits >= 1.0
        }

        init(progress: [AccuracyProgressPoint], compressedUnits: Double? = nil) {
            let first = progress.map(\.moveNumber).min() ?? 1
            let last = progress.map(\.moveNumber).max() ?? first
            self.firstScoredMove = first
            if let compressedUnits {
                self.compressedUnits = max(compressedUnits, 0.15)
            } else {
                self.compressedUnits = Self.defaultCompressedUnits(
                    firstScoredMove: first,
                    lastScoredMove: last
                )
            }
        }

        /// Book strip ≈ 12% of the scored span, clamped so short games stay compact and
        /// long games keep a clear gap before the first accuracy point.
        static func defaultCompressedUnits(firstScoredMove: Int, lastScoredMove: Int) -> Double {
            let scoredSpan = max(lastScoredMove - firstScoredMove, 1)
            return min(4.0, max(1.2, Double(scoredSpan) * 0.12))
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
            // Only skip the first scored label when the book strip is too narrow to share space.
            for move in sampleMoveNumbers(from: lo, through: hi, desiredCount: desiredCount) {
                if isCompressed, move == firstScoredMove, !showsFirstScoredAxisLabel { continue }
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
    /// Path toward the final accuracy: prefix moves plus remaining moves treated as perfect.
    var cumulativeAccuracyProgress: [AccuracyProgressPoint]
    /// White-POV evaluation story: ply 0 at 0.0, then each move that stored an eval.
    var evaluationProgress: [EvaluationPoint]
    /// Full-move numbers where middlegame / endgame begin (for vertical phase markers).
    var evaluationPhaseTransitions: [EvaluationPhaseTransition]
    /// Worst CPL swings (mistakes/blunders/misses) for sparse critical markers.
    var evaluationCriticalPlies: [EvaluationCriticalPly]

    var assessedMoveCount: Int {
        white.assessedMoveCount + black.assessedMoveCount
    }

    var scoredMoveCount: Int {
        white.scoredMoveCount + black.scoredMoveCount
    }

    var bookMoveCount: Int {
        white.bookCount + black.bookCount
    }

    /// Moves that still have no quality mark (assessment pending or not yet run).
    var unassessedMoveCount: Int

    var isAssessmentIncomplete: Bool {
        unassessedMoveCount > 0
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

    var hasEvaluationProgress: Bool {
        evaluationProgress.count >= 2
    }

    func accuracyProgress(for mode: AccuracyProgressMode) -> [AccuracyProgressPoint] {
        switch mode {
        case .running: return accuracyProgress
        case .cumulative: return cumulativeAccuracyProgress
        }
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

    init(moves: [ChessMove], fenSequence: [String]? = nil) {
        var white = SideStats()
        var black = SideStats()
        var whiteCPL = 0.0
        var blackCPL = 0.0
        var evaluationProgress: [EvaluationPoint] = [
            EvaluationPoint(ply: 0, evaluationPawns: 0)
        ]
        var criticalCandidates: [(ply: Int, quality: MoveQuality, cpl: Int)] = []

        // White-POV win% after each position: start + one entry per ply.
        var allWinPercents: [Double?] = [WinChanceAccuracy.winPercent(centipawns: 0)]
        var previousWhiteCP: Int? = 0
        var scoredSamples: [AccuracySample] = []

        for (index, move) in moves.enumerated() {
            if move.isCheckmate {
                let cp = MoveAssessmentClassifier.mateDisplayCentipawns(forDeliveredMateAtMoveIndex: index)
                evaluationProgress.append(
                    EvaluationPoint(
                        ply: index + 1,
                        evaluationPawns: Self.clampedEvaluationPawns(centipawns: cp)
                    )
                )
            } else if let cp = move.evaluationWhiteCentipawns {
                evaluationProgress.append(
                    EvaluationPoint(
                        ply: index + 1,
                        evaluationPawns: Self.clampedEvaluationPawns(centipawns: cp)
                    )
                )
            }

            guard let quality = move.quality else {
                allWinPercents.append(nil)
                previousWhiteCP = nil
                continue
            }

            let side: Side = index % 2 == 0 ? .white : .black
            let moveNumber = index / 2 + 1
            let beforeWhiteCP = previousWhiteCP
            let afterWhiteCP = Self.whitePOVCentipawnsAfter(
                move: move,
                moveIndex: index,
                side: side,
                beforeWhiteCP: beforeWhiteCP,
                quality: quality
            )

            if quality == .book {
                Self.whiteOrBlack(side, white: &white, black: &black) { $0.bookCount += 1 }
                // Keep the eval chain continuous through book; book is not scored.
                if let cp = beforeWhiteCP {
                    allWinPercents.append(WinChanceAccuracy.winPercent(centipawns: cp))
                } else {
                    allWinPercents.append(nil)
                }
                continue
            }

            if quality == .mistake || quality == .blunder || quality == .miss,
               let cpl = move.centipawnLoss, cpl > 0 {
                criticalCandidates.append((ply: index + 1, quality: quality, cpl: cpl))
            }

            if side == .white {
                Self.apply(move, quality: quality, to: &white, cplSum: &whiteCPL)
            } else {
                Self.apply(move, quality: quality, to: &black, cplSum: &blackCPL)
            }

            if let moveAccuracy = Self.moveAccuracy(
                for: move,
                quality: quality,
                side: side,
                beforeWhiteCP: beforeWhiteCP,
                afterWhiteCP: afterWhiteCP
            ) {
                scoredSamples.append(
                    AccuracySample(
                        side: side,
                        moveNumber: moveNumber,
                        plyIndex: index,
                        moveAccuracy: moveAccuracy
                    )
                )
            }

            if let afterWhiteCP {
                allWinPercents.append(WinChanceAccuracy.winPercent(centipawns: afterWhiteCP))
                previousWhiteCP = afterWhiteCP
            } else {
                allWinPercents.append(nil)
                previousWhiteCP = nil
            }
        }

        let volatilityWeights = WinChanceAccuracy.volatilityWeights(allWinPercents: allWinPercents)
        let weightedSamples = scoredSamples.map { sample in
            let weight = sample.plyIndex < volatilityWeights.count
                ? (volatilityWeights[sample.plyIndex] ?? 1)
                : 1
            return WeightedAccuracySample(
                side: sample.side,
                moveNumber: sample.moveNumber,
                moveAccuracy: sample.moveAccuracy,
                weight: weight
            )
        }

        white.accuracyPercent = Self.roundedAccuracy(
            WinChanceAccuracy.gameAccuracy(
                moveAccuracies: weightedSamples.filter { $0.side == .white }.map(\.moveAccuracy),
                weights: weightedSamples.filter { $0.side == .white }.map(\.weight)
            )
        )
        black.accuracyPercent = Self.roundedAccuracy(
            WinChanceAccuracy.gameAccuracy(
                moveAccuracies: weightedSamples.filter { $0.side == .black }.map(\.moveAccuracy),
                weights: weightedSamples.filter { $0.side == .black }.map(\.weight)
            )
        )
        white.finalizeOverviewStats(totalCPL: whiteCPL)
        black.finalizeOverviewStats(totalCPL: blackCPL)

        let whiteFinalCount = weightedSamples.filter { $0.side == .white }.count
        let blackFinalCount = weightedSamples.filter { $0.side == .black }.count

        var runningProgress: [AccuracyProgressPoint] = []
        var cumulativeProgress: [AccuracyProgressPoint] = []
        var whitePrefix: [WeightedAccuracySample] = []
        var blackPrefix: [WeightedAccuracySample] = []

        for sample in weightedSamples {
            if sample.side == .white {
                whitePrefix.append(sample)
                if let running = Self.progressAccuracy(samples: whitePrefix) {
                    runningProgress.append(
                        AccuracyProgressPoint(
                            side: .white,
                            moveNumber: sample.moveNumber,
                            accuracyPercent: running
                        )
                    )
                }
                if let cumulative = Self.cumulativeProgressAccuracy(
                    prefix: whitePrefix,
                    finalCount: whiteFinalCount
                ) {
                    cumulativeProgress.append(
                        AccuracyProgressPoint(
                            side: .white,
                            moveNumber: sample.moveNumber,
                            accuracyPercent: cumulative
                        )
                    )
                }
            } else {
                blackPrefix.append(sample)
                if let running = Self.progressAccuracy(samples: blackPrefix) {
                    runningProgress.append(
                        AccuracyProgressPoint(
                            side: .black,
                            moveNumber: sample.moveNumber,
                            accuracyPercent: running
                        )
                    )
                }
                if let cumulative = Self.cumulativeProgressAccuracy(
                    prefix: blackPrefix,
                    finalCount: blackFinalCount
                ) {
                    cumulativeProgress.append(
                        AccuracyProgressPoint(
                            side: .black,
                            moveNumber: sample.moveNumber,
                            accuracyPercent: cumulative
                        )
                    )
                }
            }
        }

        self.white = white
        self.black = black
        self.accuracyProgress = runningProgress
        self.cumulativeAccuracyProgress = cumulativeProgress
        self.evaluationProgress = evaluationProgress
        self.evaluationPhaseTransitions = Self.phaseTransitions(
            fenSequence: fenSequence ?? ChessGameBackgroundPreparation.fenSequence(from: moves)
        )
        self.evaluationCriticalPlies = criticalCandidates
            .sorted { $0.cpl > $1.cpl }
            .prefix(Self.evaluationCriticalMarkerLimit)
            .map { EvaluationCriticalPly(ply: $0.ply, quality: $0.quality) }
            .sorted { $0.ply < $1.ply }
        self.unassessedMoveCount = moves.reduce(0) { count, move in
            count + (move.quality == nil ? 1 : 0)
        }
    }

    /// Per-move CPL cap for overview average CPL (mate-scale losses).
    static let averageCPLCap: Double = 500
    static let maximumAccuracyPercent: Double = 100
    /// Eval chart Y cap in pawns (±10), matching common desktop eval graphs.
    static let evaluationScaleCapPawns: Double = 10
    static let evaluationCriticalMarkerLimit = 3

    private struct AccuracySample {
        let side: Side
        let moveNumber: Int
        let plyIndex: Int
        let moveAccuracy: Double
    }

    private struct WeightedAccuracySample {
        let side: Side
        let moveNumber: Int
        let moveAccuracy: Double
        let weight: Double
    }

    static func clampedEvaluationPawns(centipawns: Int) -> Double {
        let pawns = Double(centipawns) / 100.0
        return min(max(pawns, -evaluationScaleCapPawns), evaluationScaleCapPawns)
    }

    static func phaseTransitions(fenSequence: [String]) -> [EvaluationPhaseTransition] {
        guard fenSequence.count >= 2 else { return [] }
        let phases = GamePhaseDetector.detect(fens: fenSequence)
        var transitions: [EvaluationPhaseTransition] = []
        if let middlegame = phases.middlegame {
            transitions.append(
                EvaluationPhaseTransition(kind: .middlegame, ply: middlegame.lowerBound)
            )
        }
        if let endgame = phases.endgame {
            transitions.append(
                EvaluationPhaseTransition(kind: .endgame, ply: endgame.lowerBound)
            )
        }
        return transitions
    }

    /// Effective CPL for overview Avg CPL. Book excluded. Capped at `averageCPLCap`.
    /// Legacy qualities without stored CPL map from former point scores via `(100 - points) * 3.5`.
    static func effectiveCentipawnLoss(for move: ChessMove, quality: MoveQuality) -> Double? {
        guard quality != .book else { return nil }
        let uncapped: Double
        if let cpl = move.centipawnLoss {
            uncapped = Double(max(0, cpl))
        } else if let points = legacyPointScore(for: quality) {
            uncapped = (maximumAccuracyPercent - points) * 3.5
        } else {
            return nil
        }
        return min(uncapped, averageCPLCap)
    }

    /// Former discrete point scores, used as move accuracy when CPL/eval are missing.
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

    private static func whiteOrBlack(
        _ side: Side,
        white: inout SideStats,
        black: inout SideStats,
        _ body: (inout SideStats) -> Void
    ) {
        switch side {
        case .white: body(&white)
        case .black: body(&black)
        }
    }

    private static func whitePOVCentipawnsAfter(
        move: ChessMove,
        moveIndex: Int,
        side: Side,
        beforeWhiteCP: Int?,
        quality: MoveQuality
    ) -> Int? {
        if move.isCheckmate {
            return WinChanceAccuracy.clampedCentipawns(
                MoveAssessmentClassifier.mateDisplayCentipawns(forDeliveredMateAtMoveIndex: moveIndex)
            )
        }
        if let eval = move.evaluationWhiteCentipawns {
            return WinChanceAccuracy.clampedCentipawns(eval)
        }
        guard quality != .book,
              let before = beforeWhiteCP,
              let cpl = effectiveCentipawnLoss(for: move, quality: quality) else {
            return nil
        }
        let delta = Int(cpl.rounded())
        return WinChanceAccuracy.clampedCentipawns(
            side == .white ? before - delta : before + delta
        )
    }

    private static func moveAccuracy(
        for move: ChessMove,
        quality: MoveQuality,
        side: Side,
        beforeWhiteCP: Int?,
        afterWhiteCP: Int?
    ) -> Double? {
        if let before = beforeWhiteCP, let after = afterWhiteCP {
            let beforeWin = WinChanceAccuracy.winPercent(centipawns: before)
            let afterWin = WinChanceAccuracy.winPercent(centipawns: after)
            // White-POV pair; black uses the swapped endpoints (same ΔWin%).
            if side == .white {
                return WinChanceAccuracy.moveAccuracy(
                    beforeWinPercent: beforeWin,
                    afterWinPercent: afterWin
                )
            }
            return WinChanceAccuracy.moveAccuracy(
                beforeWinPercent: afterWin,
                afterWinPercent: beforeWin
            )
        }
        if let cpl = move.centipawnLoss {
            return WinChanceAccuracy.moveAccuracy(centipawnLoss: max(0, cpl))
        }
        if let cpl = effectiveCentipawnLoss(for: move, quality: quality) {
            return WinChanceAccuracy.moveAccuracy(centipawnLoss: Int(cpl.rounded()))
        }
        return legacyPointScore(for: quality)
    }

    private static func progressAccuracy(samples: [WeightedAccuracySample]) -> Double? {
        guard let value = WinChanceAccuracy.gameAccuracy(
            moveAccuracies: samples.map(\.moveAccuracy),
            weights: samples.map(\.weight)
        ) else { return nil }
        return Double(Int(value.rounded()))
    }

    private static func cumulativeProgressAccuracy(
        prefix: [WeightedAccuracySample],
        finalCount: Int
    ) -> Double? {
        guard finalCount > 0 else { return nil }
        var accuracies = prefix.map(\.moveAccuracy)
        var weights = prefix.map(\.weight)
        let remaining = finalCount - prefix.count
        if remaining > 0 {
            accuracies.append(contentsOf: Array(repeating: 100, count: remaining))
            weights.append(contentsOf: Array(repeating: 1, count: remaining))
        }
        guard let value = WinChanceAccuracy.gameAccuracy(
            moveAccuracies: accuracies,
            weights: weights
        ) else { return nil }
        return Double(Int(value.rounded()))
    }

    private static func roundedAccuracy(_ value: Double?) -> Int? {
        value.map { Int($0.rounded()) }
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
        if cpl == 0 {
            side.bestMoveCount += 1
        }
    }
}
