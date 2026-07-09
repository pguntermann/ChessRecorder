//
//  EngineAnalysisService.swift
//  Chess Recorder
//

import Foundation
import CStockfish
import LucidEngine

struct AnalysisArrowMove: Equatable {
    let from: ChessPosition
    let to: ChessPosition
}

struct EngineAnalysisDisplay: Equatable {
    var evaluationText: String = "—"
    var evaluationBarWhiteFraction: Double = 0.5
    var principalLineUCI: String = ""
    var principalLineSAN: String = ""
    var nextMoveArrow: AnalysisArrowMove?
    var statusMessage: String = "Stopped"
}

@Observable
@MainActor
final class EngineAnalysisService {
    private static let maxDepth = 100
    private static let defaultDepth = 10

    private(set) var isActive = false
    private(set) var isAnalyzing = false
    private(set) var isEngineReady = false
    private(set) var display = EngineAnalysisDisplay()
    
    private let engine: LucidEngine
    private var analysisTask: Task<Void, Never>?
    private var isPrepared = false
    private var configuredDepth = 10
    private var isDepthUnlimited = false
    
    init() {
        let configuration = (try? EngineConfiguration(
            defaultDepth: Self.defaultDepth,
            threadCount: 1,
            hashSizeMB: 16,
            timeoutSeconds: 30
        )) ?? .default
        engine = LucidEngine(configuration: configuration)
    }

    func configure(depth: Int, unlimited: Bool) {
        configuredDepth = min(max(depth, 1), Self.maxDepth)
        isDepthUnlimited = unlimited
    }
    
    func prepare() async {
        guard !isPrepared else { return }
        
        display.statusMessage = "Starting engine…"
        
        do {
            try await engine.start()
            isPrepared = true
            isEngineReady = true
            display.statusMessage = "Stopped"
        } catch {
            isPrepared = false
            isEngineReady = false
            display.statusMessage = "Engine unavailable"
        }
    }
    
    func shutdown() async {
        stop()
        if isPrepared {
            await engine.shutdown()
            isPrepared = false
            isEngineReady = false
        }
    }
    
    func startAnalyzing(game: ChessGame) {
        guard isPrepared else {
            display.statusMessage = "Engine unavailable"
            return
        }
        
        isActive = true
        refresh(game: game)
    }
    
    func stop() {
        isActive = false
        sf_stop_search()
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        display = EngineAnalysisDisplay(statusMessage: "Stopped")
    }
    
    func refresh(game: ChessGame) {
        guard isActive, isPrepared else { return }
        
        sf_stop_search()
        analysisTask?.cancel()
        
        let fen = game.fen()
        let sideToMove = game.currentTurn
        
        analysisTask = Task {
            await withTaskCancellationHandler {
                isAnalyzing = true
                display.statusMessage = isDepthUnlimited ? "Analyzing (uncapped)…" : "Analyzing…"
                
                defer {
                    if !Task.isCancelled {
                        isAnalyzing = false
                    }
                }
                
                var latestAssessment: PositionAssessment?
                var nextDepth: Int? = Self.initialDepth(targetDepth: configuredDepth, unlimited: isDepthUnlimited)

                while !Task.isCancelled, let depth = nextDepth {
                    do {
                        let assessment = try await engine.evaluate(fen: fen, depth: depth)
                        guard !Task.isCancelled else { return }

                        latestAssessment = assessment
                        display = EngineAnalysisDisplay(
                            evaluationText: Self.formatEvaluation(assessment.score, sideToMove: sideToMove),
                            evaluationBarWhiteFraction: Self.evaluationBarWhiteFraction(assessment.score, sideToMove: sideToMove),
                            principalLineUCI: Self.formatPrincipalLineUCI(assessment.principalVariation.map(\.uci)),
                            principalLineSAN: ChessKitMapping.formatEnginePrincipalLineSAN(assessment.principalVariation.map(\.uci), fen: fen),
                            nextMoveArrow: Self.arrowMove(from: assessment.principalVariation.first?.uci),
                            statusMessage: Self.depthStatusMessage(
                                currentDepth: assessment.depth,
                                targetDepth: configuredDepth,
                                unlimited: isDepthUnlimited,
                                isFinal: !Self.hasNextDepth(after: assessment.depth, targetDepth: configuredDepth, unlimited: isDepthUnlimited)
                            )
                        )
                        nextDepth = Self.nextDepth(after: assessment.depth, targetDepth: configuredDepth, unlimited: isDepthUnlimited)
                    } catch {
                        guard !Task.isCancelled else { return }

                        if let latestAssessment {
                            display = EngineAnalysisDisplay(
                                evaluationText: Self.formatEvaluation(latestAssessment.score, sideToMove: sideToMove),
                                evaluationBarWhiteFraction: Self.evaluationBarWhiteFraction(latestAssessment.score, sideToMove: sideToMove),
                                principalLineUCI: Self.formatPrincipalLineUCI(latestAssessment.principalVariation.map(\.uci)),
                                principalLineSAN: ChessKitMapping.formatEnginePrincipalLineSAN(latestAssessment.principalVariation.map(\.uci), fen: fen),
                                nextMoveArrow: Self.arrowMove(from: latestAssessment.principalVariation.first?.uci),
                                statusMessage: Self.statusMessage(for: error, fallbackDepth: latestAssessment.depth, unlimited: isDepthUnlimited)
                            )
                        } else {
                            display = EngineAnalysisDisplay(
                                evaluationText: "—",
                                evaluationBarWhiteFraction: 0.5,
                                principalLineUCI: "",
                                principalLineSAN: "",
                                nextMoveArrow: nil,
                                statusMessage: Self.statusMessage(for: error)
                            )
                        }
                        return
                    }
                }
            } onCancel: {
                sf_stop_search()
            }
        }
    }
    
    private static func initialDepth(targetDepth: Int, unlimited: Bool) -> Int {
        min(unlimited ? 6 : targetDepth, 6)
    }

    private static func nextDepth(after depth: Int, targetDepth: Int, unlimited: Bool) -> Int? {
        let candidate: Int
        switch depth {
        case ..<10:
            candidate = depth + 2
        case ..<20:
            candidate = depth + 4
        default:
            candidate = depth + 8
        }

        if unlimited {
            return candidate <= maxDepth ? candidate : nil
        }
        return candidate <= targetDepth ? candidate : nil
    }

    private static func hasNextDepth(after depth: Int, targetDepth: Int, unlimited: Bool) -> Bool {
        nextDepth(after: depth, targetDepth: targetDepth, unlimited: unlimited) != nil
    }

    private static func depthStatusMessage(currentDepth: Int, targetDepth: Int, unlimited: Bool, isFinal: Bool) -> String {
        if unlimited {
            return isFinal ? "Depth \(currentDepth) (uncapped)" : "Depth \(currentDepth) (updating)"
        }
        return isFinal ? "Depth \(currentDepth)" : "Depth \(currentDepth) of \(targetDepth)"
    }

    private static func statusMessage(for error: Error, fallbackDepth: Int? = nil, unlimited: Bool = false) -> String {
        guard let engineError = error as? EngineError else {
            return "Analysis failed"
        }
        
        switch engineError {
        case .evaluationTimeout:
            if let fallbackDepth {
                return unlimited ? "Depth \(fallbackDepth) (timed out)" : "Depth \(fallbackDepth) (timed out)"
            }
            return "Analysis timed out"
        case .engineNotRunning:
            return "Engine unavailable"
        case .invalidFEN(_):
            return "Invalid position"
        default:
            return "Analysis failed"
        }
    }
    
    private static func formatEvaluation(_ score: Score, sideToMove: PieceColor) -> String {
        let whitePerspective = whitePerspectiveScore(score, sideToMove: sideToMove)
        switch whitePerspective {
        case .centipawns(let cp):
            return String(format: "%+.2f", Double(cp) / 100.0)
        case .mate(let moves):
            if moves > 0 {
                return "M\(moves)"
            }
            if moves < 0 {
                return "-M\(abs(moves))"
            }
            return "0.00"
        }
    }

    private static func evaluationBarWhiteFraction(_ score: Score, sideToMove: PieceColor) -> Double {
        let whitePerspective = whitePerspectiveScore(score, sideToMove: sideToMove)

        switch whitePerspective {
        case .centipawns(let cp):
            return evaluationBarWhiteFraction(forPawns: Double(cp) / 100.0)
        case .mate(let moves):
            if moves > 0 { return 1.0 }
            if moves < 0 { return 0.0 }
            return 0.5
        }
    }

    static func evaluationBarWhiteFraction(forPawns pawns: Double) -> Double {
        let normalized = tanh(pawns / 4.0)
        return min(max((normalized + 1.0) / 2.0, 0.0), 1.0)
    }

    private static func whitePerspectiveScore(_ score: Score, sideToMove: PieceColor) -> Score {
        switch score {
        case .centipawns(let cp):
            return .centipawns(sideToMove == .white ? cp : -cp)
        case .mate(let moves):
            return .mate(sideToMove == .white ? moves : -moves)
        }
    }
    
    private static func formatPrincipalLineUCI(_ line: [String]) -> String {
        guard !line.isEmpty else { return "—" }
        return line.joined(separator: " ")
    }

    private static func arrowMove(from uci: String?) -> AnalysisArrowMove? {
        guard let uci,
              let move = ChessKitMapping.engineMoveComponents(from: uci),
              let from = ChessPosition(notation: move.from),
              let to = ChessPosition(notation: move.to) else {
            return nil
        }

        return AnalysisArrowMove(from: from, to: to)
    }
}
