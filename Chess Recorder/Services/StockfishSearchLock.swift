//
//  StockfishSearchLock.swift
//  Chess Recorder
//

import Foundation

/// LucidEngine/Stockfish uses one global C engine. Live analysis calls `sf_stop_search()`
/// freely, which can interrupt an in-flight move-assessment search and produce garbage
/// centipawn-loss (false blunders). Assessment sessions suppress those stops.
enum StockfishSearchLock {
    private static let lock = NSLock()
    private static var assessmentSessionCount = 0

    static func beginAssessmentSession() {
        lock.lock()
        assessmentSessionCount += 1
        lock.unlock()
    }

    static func endAssessmentSession() {
        lock.lock()
        assessmentSessionCount = max(0, assessmentSessionCount - 1)
        lock.unlock()
    }

    static var isAssessmentSessionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return assessmentSessionCount > 0
    }

    static func withAssessmentSession<T>(
        _ body: () async throws -> T
    ) async rethrows -> T {
        beginAssessmentSession()
        defer { endAssessmentSession() }
        return try await body()
    }
}
