//
//  EngineAnalysisService.swift
//  Chess Recorder
//

import Foundation
import LucidEngine

struct AnalysisArrowMove: Equatable {
    let from: ChessPosition
    let to: ChessPosition
}

enum EngineGamePhase: String, Equatable {
    case opening = "Opening"
    case middlegame = "Middlegame"
    case endgame = "Endgame"
}

struct WinProbabilityDisplay: Equatable {
    let white: Double
    let draw: Double
    let black: Double

    init(wdl: WinProbability) {
        white = wdl.white
        draw = wdl.draw
        black = wdl.black
    }

    var whitePercent: Int { Int((white * 100).rounded()) }
    var drawPercent: Int { Int((draw * 100).rounded()) }
    var blackPercent: Int { Int((black * 100).rounded()) }
}

struct EngineAnalysisDisplay: Equatable {
    var evaluationText: String = "—"
    var evaluationBarWhiteFraction: Double = 0.5
    var winProbability: WinProbabilityDisplay?
    var gamePhase: EngineGamePhase?
    var principalLineUCI: String = ""
    var principalLineSAN: String = ""
    var nextMoveArrow: AnalysisArrowMove?
    var statusMessage: String = "Stopped"
}

@Observable
@MainActor
final class EngineAnalysisService {
    private static let defaultDepth = 18
    private static let displayPublishMinInterval: TimeInterval = 0.25

    private(set) var isActive = false
    private(set) var isAnalyzing = false
    private(set) var isEngineReady = false
    private(set) var display = EngineAnalysisDisplay()

    private let engineWorker: EngineAnalysisEngine
    private var analysisTask: Task<Void, Never>?
    private var analysisGeneration = 0
    private var configuredDepth = 18
    private var isDepthUnlimited = false
    private var lastDisplayPublish = Date.distantPast
    private var pendingDisplay: EngineAnalysisDisplay?

    init() {
        let configuration = (try? EngineConfiguration(
            defaultDepth: Self.defaultDepth,
            threadCount: 1,
            hashSizeMB: 16,
            // Per iterative-depth step; high max depths need more than 30s to finish a search.
            timeoutSeconds: 120
        )) ?? .default
        engineWorker = EngineAnalysisEngine(configuration: configuration)
    }

    func configure(depth: Int, unlimited: Bool) {
        configuredDepth = min(max(depth, 1), Int(AppSettings.maxEngineAnalysisDepth))
        // Uncapped analysis was removed; ignore legacy `unlimited` callers.
        isDepthUnlimited = false
        _ = unlimited
    }

    func prepare() async {
        guard !isEngineReady else { return }

        display.statusMessage = "Starting engine…"

        do {
            try await engineWorker.prepare()
            isEngineReady = true
            display.statusMessage = "Stopped"
        } catch {
            isEngineReady = false
            display.statusMessage = "Engine unavailable"
        }
    }

    func shutdown() async {
        stop()
        await engineWorker.shutdown()
        isEngineReady = false
    }

    func startAnalyzing(game: ChessGame) {
        guard isEngineReady else {
            display.statusMessage = "Engine unavailable"
            return
        }

        isActive = true
        refresh(game: game)
    }

    func stop() {
        isActive = false
        analysisGeneration += 1
        analysisTask?.cancel()
        analysisTask = nil
        pendingDisplay = nil
        isAnalyzing = false
        display = EngineAnalysisDisplay(statusMessage: "Stopped")
        Task { await engineWorker.stopSearch() }
    }

    /// Cancels in-flight search and clears the board arrow without turning analysis off.
    /// Used during game-switch slides so Stockfish work does not compete with animation frames.
    func suspendInFlightAnalysis() {
        guard isActive else { return }
        analysisGeneration += 1
        analysisTask?.cancel()
        analysisTask = nil
        pendingDisplay = nil
        isAnalyzing = false
        var cleared = display
        cleared.nextMoveArrow = nil
        cleared.principalLineUCI = ""
        cleared.principalLineSAN = ""
        cleared.statusMessage = "Analyzing…"
        display = cleared
        Task { await engineWorker.stopSearch() }
    }

    func refresh(game: ChessGame) {
        guard isActive, isEngineReady else { return }

        analysisGeneration += 1
        let generation = analysisGeneration
        analysisTask?.cancel()
        pendingDisplay = nil

        let snapshot = AnalysisSnapshot(
            fen: game.fen(),
            sideToMove: game.currentTurn,
            fenSequence: game.fenSequenceFromStart()
        )
        let targetDepth = configuredDepth
        let unlimited = isDepthUnlimited

        isAnalyzing = true
        // Drop the previous position's best-move arrow immediately so it can't linger
        // while we wait on assessment lock / the first new depth result.
        var cleared = display
        cleared.nextMoveArrow = nil
        cleared.principalLineUCI = ""
        cleared.principalLineSAN = ""
        cleared.statusMessage = unlimited ? "Analyzing (uncapped)…" : "Analyzing…"
        display = cleared

        analysisTask = Task.detached(priority: .userInitiated) { [engineWorker] in
            // Live analysis and move assessment share one Stockfish. Wait until assessment
            // releases the engine so our evaluate timeout cannot sf_stop_search mid-classify.
            while StockfishSearchLock.isAssessmentSessionActive && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }

            await engineWorker.stopSearch()

            let gamePhase = EngineAnalysisDisplayBuilder.currentPhase(fens: snapshot.fenSequence)
            var latestAssessment: PositionAssessment?
            var nextDepth: Int? = EngineAnalysisDisplayBuilder.initialDepth(
                targetDepth: targetDepth,
                unlimited: unlimited
            )

            defer {
                Task { @MainActor in
                    guard generation == self.analysisGeneration else { return }
                    self.isAnalyzing = false
                    if let pendingDisplay = self.pendingDisplay {
                        self.display = pendingDisplay
                        self.pendingDisplay = nil
                    }
                }
            }

            while !Task.isCancelled, let depth = nextDepth {
                do {
                    let assessment = try await engineWorker.evaluate(fen: snapshot.fen, depth: depth)
                    guard !Task.isCancelled else { return }

                    latestAssessment = assessment
                    let isFinal = !EngineAnalysisDisplayBuilder.hasNextDepth(
                        after: assessment.depth,
                        targetDepth: targetDepth,
                        unlimited: unlimited
                    )
                    let builtDisplay = EngineAnalysisDisplayBuilder.makeDisplay(
                        assessment: assessment,
                        fen: snapshot.fen,
                        sideToMove: snapshot.sideToMove,
                        gamePhase: gamePhase,
                        statusMessage: EngineAnalysisDisplayBuilder.depthStatusMessage(
                            currentDepth: assessment.depth,
                            targetDepth: targetDepth,
                            unlimited: unlimited,
                            isFinal: isFinal
                        )
                    )

                    await MainActor.run {
                        guard generation == self.analysisGeneration else { return }
                        self.publishDisplay(builtDisplay, force: isFinal)
                    }

                    nextDepth = EngineAnalysisDisplayBuilder.nextDepth(
                        after: assessment.depth,
                        targetDepth: targetDepth,
                        unlimited: unlimited
                    )
                } catch {
                    guard !Task.isCancelled else { return }

                    let failureDisplay: EngineAnalysisDisplay
                    if let latestAssessment {
                        failureDisplay = EngineAnalysisDisplayBuilder.makeDisplay(
                            assessment: latestAssessment,
                            fen: snapshot.fen,
                            sideToMove: snapshot.sideToMove,
                            gamePhase: gamePhase,
                            statusMessage: EngineAnalysisDisplayBuilder.statusMessage(
                                for: error,
                                fallbackDepth: latestAssessment.depth,
                                unlimited: unlimited
                            )
                        )
                    } else {
                        failureDisplay = EngineAnalysisDisplay(
                            evaluationText: "—",
                            evaluationBarWhiteFraction: 0.5,
                            winProbability: nil,
                            gamePhase: gamePhase,
                            principalLineUCI: "",
                            principalLineSAN: "",
                            nextMoveArrow: nil,
                            statusMessage: EngineAnalysisDisplayBuilder.statusMessage(for: error)
                        )
                    }

                    await MainActor.run {
                        guard generation == self.analysisGeneration else { return }
                        self.publishDisplay(failureDisplay, force: true)
                    }
                    return
                }
            }
        }
    }

    static func currentPhase(fens: [String]) -> EngineGamePhase {
        EngineAnalysisDisplayBuilder.currentPhase(fens: fens)
    }

    static func evaluationBarWhiteFraction(forPawns pawns: Double) -> Double {
        EngineAnalysisDisplayBuilder.evaluationBarWhiteFraction(forPawns: pawns)
    }

    private func publishDisplay(_ newDisplay: EngineAnalysisDisplay, force: Bool) {
        let now = Date()
        if force || now.timeIntervalSince(lastDisplayPublish) >= Self.displayPublishMinInterval {
            display = newDisplay
            lastDisplayPublish = now
            pendingDisplay = nil
            return
        }

        pendingDisplay = newDisplay
    }
}
