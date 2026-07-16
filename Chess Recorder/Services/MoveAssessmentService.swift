//
//  MoveAssessmentService.swift
//  Chess Recorder
//

import Foundation
import LucidEngine

struct MoveAssessmentJob: Sendable, Equatable {
    let gameID: UUID
    let moveIndex: Int
    let fenBeforeMove: String
    let fenAfterMove: String
    let playedMoveSAN: String
}

struct MoveAssessmentProgress: Equatable, Sendable {
    let gameID: UUID
    let moveIndex: Int
}

@Observable
@MainActor
final class MoveAssessmentService {
    private static let defaultDepth = 18

    private(set) var isEngineReady = false
    private(set) var pendingJobCount = 0
    /// The single move currently being assessed (nil when idle).
    private(set) var activeAssessment: MoveAssessmentProgress?

    private let engineWorker: MoveAssessmentEngine
    private var processorTask: Task<Void, Never>?
    private var pendingJobs: [MoveAssessmentJob] = []
    private var activeJob: MoveAssessmentJob?
    private var configuredDepth = 14
    private var isEnabled = true
    private var openingService: OpeningService?

    init() {
        let configuration = (try? EngineConfiguration(
            defaultDepth: Self.defaultDepth,
            threadCount: 1,
            hashSizeMB: 16,
            // High depths (up to 25) need generous time; 45s was timing out before glyphs appeared.
            timeoutSeconds: 120
        )) ?? .default
        engineWorker = MoveAssessmentEngine(configuration: configuration)
    }

    func configure(depth: Int, enabled: Bool, openingService: OpeningService? = nil) {
        configuredDepth = min(max(depth, 1), Int(AppSettings.maxMoveAssessmentDepth))
        isEnabled = enabled
        if let openingService {
            self.openingService = openingService
        }
        if !enabled {
            cancelAll()
        }
    }

    func prepare() async {
        guard !isEngineReady else { return }

        do {
            try await engineWorker.prepare()
            isEngineReady = true
        } catch {
            isEngineReady = false
        }
    }

    func shutdown() async {
        cancelAll()
        await engineWorker.shutdown()
        isEngineReady = false
    }

    func enqueue(_ job: MoveAssessmentJob, archive: PGNArchive) {
        guard isEnabled, isEngineReady else { return }

        pendingJobs.removeAll {
            $0.gameID == job.gameID && $0.moveIndex == job.moveIndex
        }
        pendingJobs.append(job)
        refreshPendingState()
        startProcessingIfNeeded(archive: archive)
    }

    func enqueueUnassessedMoves(in archive: PGNArchive) {
        guard isEnabled, isEngineReady else { return }

        for game in archive.games where !game.moves.isEmpty {
            let fens = fensForMoves(game.moves)
            guard fens.count == game.moves.count + 1 else { continue }

            for moveIndex in game.moves.indices where game.moves[moveIndex].quality == nil {
                let fenAfter = fens[moveIndex + 1]
                let playedSAN = game.moves[moveIndex].san

                if isBookMove(fenBefore: fens[moveIndex], fenAfter: fenAfter) {
                    if archive.applyMoveAssessment(
                        gameID: game.id,
                        moveIndex: moveIndex,
                        quality: .book,
                        centipawnLoss: nil,
                        expectedSAN: playedSAN
                    ) {
                        onAssessmentApplied?()
                    }
                    continue
                }

                let job = MoveAssessmentJob(
                    gameID: game.id,
                    moveIndex: moveIndex,
                    fenBeforeMove: fens[moveIndex],
                    fenAfterMove: fenAfter,
                    playedMoveSAN: playedSAN
                )
                enqueue(job, archive: archive)
            }
        }
    }

    func cancelJobs(for gameID: UUID?, fromMoveIndex: Int) {
        guard let gameID else {
            cancelAll()
            return
        }

        pendingJobs.removeAll { $0.gameID == gameID && $0.moveIndex >= fromMoveIndex }
        if activeJob?.gameID == gameID {
            activeJob = nil
        }
        refreshPendingState()
    }

    func cancelAll() {
        processorTask?.cancel()
        processorTask = nil
        pendingJobs.removeAll()
        activeJob = nil
        refreshPendingState()
    }

    var onAssessmentApplied: (() -> Void)?

    private func refreshPendingState() {
        pendingJobCount = pendingJobs.count + (activeJob == nil ? 0 : 1)
        if let activeJob {
            activeAssessment = MoveAssessmentProgress(gameID: activeJob.gameID, moveIndex: activeJob.moveIndex)
        } else {
            activeAssessment = nil
        }
    }

    private func startProcessingIfNeeded(archive: PGNArchive) {
        guard processorTask == nil else { return }

        processorTask = Task.detached(priority: .utility) { [engineWorker] in
            while !Task.isCancelled {
                let job: MoveAssessmentJob? = await MainActor.run {
                    guard !self.pendingJobs.isEmpty else {
                        self.activeJob = nil
                        self.processorTask = nil
                        self.refreshPendingState()
                        return nil
                    }
                    let next = self.pendingJobs.removeFirst()
                    self.activeJob = next
                    self.refreshPendingState()
                    return next
                }

                guard let job else { return }

                if await MainActor.run(body: {
                    self.isBookMove(fenBefore: job.fenBeforeMove, fenAfter: job.fenAfterMove)
                }) {
                    await MainActor.run {
                        if archive.applyMoveAssessment(
                            gameID: job.gameID,
                            moveIndex: job.moveIndex,
                            quality: .book,
                            centipawnLoss: nil,
                            expectedSAN: job.playedMoveSAN
                        ) {
                            self.onAssessmentApplied?()
                        }
                        if self.activeJob == job {
                            self.activeJob = nil
                        }
                        self.refreshPendingState()
                        if self.pendingJobs.isEmpty {
                            self.processorTask = nil
                        }
                    }
                    continue
                }

                let depth = await MainActor.run { self.configuredDepth }

                do {
                    let result = try await engineWorker.assessMove(
                        fenBefore: job.fenBeforeMove,
                        fenAfter: job.fenAfterMove,
                        depth: depth
                    )

                    await MainActor.run {
                        if archive.applyMoveAssessment(
                            gameID: job.gameID,
                            moveIndex: job.moveIndex,
                            quality: result.quality,
                            centipawnLoss: result.centipawnLoss,
                            expectedSAN: job.playedMoveSAN
                        ) {
                            self.onAssessmentApplied?()
                        }
                        if self.activeJob == job {
                            self.activeJob = nil
                        }
                        self.refreshPendingState()
                        if self.pendingJobs.isEmpty {
                            self.processorTask = nil
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if self.activeJob == job {
                            self.activeJob = nil
                        }
                        self.refreshPendingState()
                        if self.pendingJobs.isEmpty {
                            self.processorTask = nil
                        }
                    }
                }
            }
        }
    }

    private func isBookMove(fenBefore: String, fenAfter: String) -> Bool {
        if openingService?.isBookPosition(fen: fenAfter) == true {
            return true
        }
        return OpeningBook.detect(fens: [fenBefore, fenAfter]) != nil
    }

    private func fensForMoves(_ moves: [ChessMove]) -> [String] {
        ChessGame.prepared(from: moves).fenSequenceFromStart()
    }
}
