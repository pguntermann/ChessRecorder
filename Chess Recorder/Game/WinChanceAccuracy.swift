//
//  WinChanceAccuracy.swift
//  Chess Recorder
//
//  Accuracy from winning-chance (Win%) changes rather than raw average CPL.
//

import Foundation

/// Win%-based accuracy: convert eval → win chance, score each move by Win% drop,
/// then aggregate with a volatility-weighted mean and harmonic mean.
enum WinChanceAccuracy: Sendable {
    /// Logistic mapping from centipawns to win probability.
    static let winPercentCoefficient: Double = 0.00368208
    /// Cap when mapping mate-scale evals into Win%.
    static let centipawnCeiling: Int = 1_000

    static let moveAccuracyScale: Double = 103.1668100711649
    static let moveAccuracyDecay: Double = 0.04354415386753951
    static let moveAccuracyOffset: Double = -3.166924740191411
    /// Small bonus for analysis uncertainty before clamping to `[0, 100]`.
    static let moveAccuracyUncertaintyBonus: Double = 1

    static let volatilityWeightMin: Double = 0.5
    static let volatilityWeightMax: Double = 12

    /// Win% in `[0, 100]` from White-POV centipawns (mates should already be ceiled).
    static func winPercent(centipawns: Int) -> Double {
        let cp = Double(clampedCentipawns(centipawns))
        return 100.0 / (1.0 + exp(-winPercentCoefficient * cp))
    }

    static func clampedCentipawns(_ centipawns: Int) -> Int {
        min(max(centipawns, -centipawnCeiling), centipawnCeiling)
    }

    /// Per-move accuracy from mover-POV Win% before/after the move.
    static func moveAccuracy(beforeWinPercent: Double, afterWinPercent: Double) -> Double {
        if afterWinPercent >= beforeWinPercent { return 100 }
        let winDiff = beforeWinPercent - afterWinPercent
        let raw = moveAccuracyScale * exp(-moveAccuracyDecay * winDiff) + moveAccuracyOffset
        return min(100, max(0, raw + moveAccuracyUncertaintyBonus))
    }

    /// When only CPL is known, grade the swing as if it happened near equality
    /// (`Win%(cpl) → Win%(0)`), where a given CPL costs the most winning chance.
    static func moveAccuracy(centipawnLoss: Int) -> Double {
        let cpl = max(0, centipawnLoss)
        if cpl == 0 { return 100 }
        return moveAccuracy(
            beforeWinPercent: winPercent(centipawns: cpl),
            afterWinPercent: winPercent(centipawns: 0)
        )
    }

    /// `(volatilityWeightedMean + harmonicMean) / 2`.
    static func gameAccuracy(moveAccuracies: [Double], weights: [Double]) -> Double? {
        guard !moveAccuracies.isEmpty, moveAccuracies.count == weights.count else { return nil }
        let pairs = zip(moveAccuracies, weights).map { ($0, $1) }
        guard let weighted = weightedMean(pairs),
              let harmonic = harmonicMean(moveAccuracies) else { return nil }
        return (weighted + harmonic) / 2
    }

    /// Equal-weight game accuracy (fallback when volatility is unavailable).
    static func gameAccuracy(moveAccuracies: [Double]) -> Double? {
        gameAccuracy(
            moveAccuracies: moveAccuracies,
            weights: Array(repeating: 1, count: moveAccuracies.count)
        )
    }

    /// Volatility weights: stddev of Win% in a sliding window, clamped to `[0.5, 12]`.
    /// `allWinPercents` is `[start] + after each ply` (same length as positions).
    /// Returns one weight per move (`allWinPercents.count - 1`).
    static func volatilityWeights(allWinPercents: [Double?]) -> [Double?] {
        let positionCount = allWinPercents.count
        guard positionCount >= 2 else { return [] }
        let moveCount = positionCount - 1
        let windowSize = max(2, min(8, moveCount / 10))
        let firstWindow = Array(allWinPercents.prefix(min(windowSize, positionCount)))
        let padCount = max(0, min(windowSize, positionCount) - 2)

        var windows: [[Double?]] = Array(repeating: firstWindow, count: padCount)
        if positionCount >= windowSize {
            for start in 0...(positionCount - windowSize) {
                windows.append(Array(allWinPercents[start..<(start + windowSize)]))
            }
        } else if windows.count < moveCount {
            while windows.count < moveCount {
                windows.append(firstWindow)
            }
        }

        return windows.prefix(moveCount).map { window in
            let values = window.compactMap { $0 }
            guard values.count == window.count, let sd = standardDeviation(values) else {
                return nil
            }
            return min(volatilityWeightMax, max(volatilityWeightMin, sd))
        }
    }

    static func weightedMean(_ pairs: [(Double, Double)]) -> Double? {
        guard !pairs.isEmpty else { return nil }
        var weightedSum = 0.0
        var weightSum = 0.0
        for (value, weight) in pairs {
            weightedSum += value * weight
            weightSum += weight
        }
        guard weightSum > 0 else { return nil }
        return weightedSum / weightSum
    }

    static func harmonicMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var reciprocalSum = 0.0
        for value in values {
            guard value > 0 else { return 0 }
            reciprocalSum += 1.0 / value
        }
        return Double(values.count) / reciprocalSum
    }

    /// Population standard deviation.
    static func standardDeviation(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return sqrt(variance)
    }
}
