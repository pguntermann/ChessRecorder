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
    let from: ChessPosition
    let to: ChessPosition
    let isCheckmate: Bool
    /// Failed engine attempts so far; used to retry once before abandoning a ply.
    let attempt: Int

    init(
        gameID: UUID,
        moveIndex: Int,
        fenBeforeMove: String,
        fenAfterMove: String,
        playedMoveSAN: String,
        from: ChessPosition,
        to: ChessPosition,
        isCheckmate: Bool,
        attempt: Int = 0
    ) {
        self.gameID = gameID
        self.moveIndex = moveIndex
        self.fenBeforeMove = fenBeforeMove
        self.fenAfterMove = fenAfterMove
        self.playedMoveSAN = playedMoveSAN
        self.from = from
        self.to = to
        self.isCheckmate = isCheckmate
        self.attempt = attempt
    }
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

    /// When true (developer mode), logs compact assessment pipeline events.
    var isTracingEnabled = false

    /// When true, engine-backed assessment waits so live analysis can finish first.
    private var isLiveAnalysisBusy = false

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
            log("engine ready")
        } catch {
            isEngineReady = false
            log("engine prepare failed: \(Self.errorDescription(error))")
        }
    }

    func shutdown() async {
        cancelAll()
        await engineWorker.shutdown()
        isEngineReady = false
        log("engine shutdown")
    }

    func enqueue(_ job: MoveAssessmentJob, archive: PGNArchive, logEnqueue: Bool = true) {
        guard isEnabled, isEngineReady else {
            log(
                "enqueue skipped \(Self.jobLabel(job)) — enabled=\(isEnabled) ready=\(isEngineReady)"
            )
            return
        }

        pendingJobs.removeAll {
            $0.gameID == job.gameID && $0.moveIndex == job.moveIndex
        }
        pendingJobs.append(job)
        refreshPendingState()
        if logEnqueue {
            log("enqueue \(Self.jobLabel(job)) queue=\(pendingJobCount)")
        }
        startProcessingIfNeeded(archive: archive)
    }

    func enqueueUnassessedMoves(in archive: PGNArchive) {
        guard isEnabled, isEngineReady else {
            log("bulk enqueue skipped — enabled=\(isEnabled) ready=\(isEngineReady)")
            return
        }

        var booked = 0
        var queued = 0
        var fenMismatchGames = 0
        var alreadyAssessed = 0

        for game in archive.games where !game.moves.isEmpty {
            let fens = fensForMoves(game.moves)
            guard fens.count == game.moves.count + 1 else {
                fenMismatchGames += 1
                log(
                    "skip game \(Self.shortID(game.id)) — fen replay \(fens.count) vs moves \(game.moves.count)+1"
                )
                continue
            }

            for moveIndex in game.moves.indices {
                guard game.moves[moveIndex].quality == nil else {
                    alreadyAssessed += 1
                    continue
                }

                let fenAfter = fens[moveIndex + 1]
                let recordedMove = game.moves[moveIndex]
                let playedSAN = recordedMove.san

                if isBookMove(fenBefore: fens[moveIndex], fenAfter: fenAfter) {
                    let applied = archive.applyMoveAssessment(
                        gameID: game.id,
                        moveIndex: moveIndex,
                        quality: .book,
                        centipawnLoss: nil,
                        expectedSAN: recordedMove.san,
                        expectedFrom: recordedMove.from,
                        expectedTo: recordedMove.to
                    )
                    if applied {
                        booked += 1
                        onAssessmentApplied?()
                        log(
                            "book \(Self.plyLabel(gameID: game.id, moveIndex: moveIndex, san: playedSAN))"
                        )
                    } else {
                        log(
                            "book apply missed \(Self.plyLabel(gameID: game.id, moveIndex: moveIndex, san: playedSAN))"
                        )
                    }
                    continue
                }

                let job = MoveAssessmentJob(
                    gameID: game.id,
                    moveIndex: moveIndex,
                    fenBeforeMove: fens[moveIndex],
                    fenAfterMove: fenAfter,
                    playedMoveSAN: recordedMove.san,
                    from: recordedMove.from,
                    to: recordedMove.to,
                    isCheckmate: recordedMove.isCheckmate
                )
                enqueue(job, archive: archive, logEnqueue: false)
                queued += 1
            }
        }

        log(
            "bulk enqueue done booked=\(booked) queued=\(queued) already=\(alreadyAssessed) fenSkip=\(fenMismatchGames) queue=\(pendingJobCount)"
        )
    }

    func cancelJobs(for gameID: UUID?, fromMoveIndex: Int) {
        guard let gameID else {
            cancelAll()
            return
        }

        let before = pendingJobs.count
        pendingJobs.removeAll { $0.gameID == gameID && $0.moveIndex >= fromMoveIndex }
        let removed = before - pendingJobs.count
        let clearedActive = activeJob?.gameID == gameID
        if clearedActive {
            activeJob = nil
        }
        refreshPendingState()
        if removed > 0 || clearedActive {
            log(
                "cancel game=\(Self.shortID(gameID)) fromPly=\(fromMoveIndex) removed=\(removed) clearedActive=\(clearedActive) queue=\(pendingJobCount)"
            )
        }
    }

    /// Live engine analysis is searching — pause Stockfish-backed assessment until it goes idle.
    func setLiveAnalysisBusy(_ busy: Bool) {
        let wasBusy = isLiveAnalysisBusy
        isLiveAnalysisBusy = busy
        if wasBusy && !busy {
            log("live analysis idle — assessment may proceed queue=\(pendingJobCount)")
        } else if !wasBusy && busy {
            log("live analysis busy — assessment waiting queue=\(pendingJobCount)")
        }
    }

    /// True when this game still has unassessed moves and/or queued/active assessment work.
    func hasIncompleteAssessment(for gameID: UUID, moves: [ChessMove]) -> Bool {
        guard isEnabled else { return false }
        if moves.contains(where: { $0.quality == nil }) { return true }
        if activeJob?.gameID == gameID { return true }
        return pendingJobs.contains { $0.gameID == gameID }
    }

    /// Game IDs with queued or in-flight assessment jobs (not including unassessed-but-not-yet-enqueued).
    func gameIDsWithQueuedAssessment() -> Set<UUID> {
        var ids = Set(pendingJobs.map(\.gameID))
        if let activeJob {
            ids.insert(activeJob.gameID)
        }
        return ids
    }

    func cancelAll() {
        let removed = pendingJobs.count + (activeJob == nil ? 0 : 1)
        processorTask?.cancel()
        processorTask = nil
        pendingJobs.removeAll()
        activeJob = nil
        refreshPendingState()
        if removed > 0 {
            log("cancel all (had \(removed) in flight/queued)")
        }
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

        log("processor start queue=\(pendingJobCount)")
        processorTask = Task.detached(priority: .utility) { [engineWorker] in
            while !Task.isCancelled {
                let job: MoveAssessmentJob? = await MainActor.run {
                    guard !self.pendingJobs.isEmpty else {
                        self.activeJob = nil
                        self.processorTask = nil
                        self.refreshPendingState()
                        self.log("processor idle")
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
                        let applied = archive.applyMoveAssessment(
                            gameID: job.gameID,
                            moveIndex: job.moveIndex,
                            quality: .book,
                            centipawnLoss: nil,
                            expectedSAN: job.playedMoveSAN,
                            expectedFrom: job.from,
                            expectedTo: job.to
                        )
                        if applied {
                            self.onAssessmentApplied?()
                            self.log("book \(Self.jobLabel(job))")
                        } else {
                            self.log("book apply missed \(Self.jobLabel(job))")
                        }
                        self.finishJob(job)
                    }
                    continue
                }

                let depth = await MainActor.run { self.configuredDepth }
                await MainActor.run {
                    self.log("engine \(Self.jobLabel(job)) depth=\(depth) queue=\(self.pendingJobCount)")
                }

                // Yield the shared Stockfish to live analysis until it reaches max depth / goes idle.
                while await MainActor.run(body: { self.isLiveAnalysisBusy }) && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if Task.isCancelled {
                    await MainActor.run {
                        self.requeueInterruptedJob(job, reason: "cancelled while waiting for live analysis")
                    }
                    return
                }

                do {
                    let result = try await engineWorker.assessMove(
                        fenBefore: job.fenBeforeMove,
                        fenAfter: job.fenAfterMove,
                        depth: depth,
                        deliveredCheckmate: job.isCheckmate
                    )

                    await MainActor.run {
                        let evalCP = MoveAssessmentClassifier.whitePerspectiveCentipawns(
                            rawScoreAfter: result.rawScoreAfter,
                            moveIndex: job.moveIndex,
                            deliveredCheckmate: job.isCheckmate
                        )
                        let applied = archive.applyMoveAssessment(
                            gameID: job.gameID,
                            moveIndex: job.moveIndex,
                            quality: result.quality,
                            centipawnLoss: result.centipawnLoss,
                            evaluationWhiteCentipawns: evalCP,
                            bestMoveSAN: result.bestMoveSAN,
                            expectedSAN: job.playedMoveSAN,
                            expectedFrom: job.from,
                            expectedTo: job.to
                        )
                        if applied {
                            self.onAssessmentApplied?()
                            self.log(
                                "ok \(Self.jobLabel(job)) \(result.quality.rawValue) cpl=\(result.centipawnLoss) eval=\(Self.evalLabel(evalCP)) queue=\(self.pendingJobCount)"
                            )
                        } else {
                            self.log(
                                "apply missed \(Self.jobLabel(job)) \(result.quality.rawValue) cpl=\(result.centipawnLoss)"
                            )
                        }
                        self.finishJob(job)
                    }
                } catch {
                    if Task.isCancelled {
                        await MainActor.run {
                            self.requeueInterruptedJob(job, reason: "cancelled during assessment")
                        }
                        return
                    }
                    await MainActor.run {
                        self.handleAssessmentFailure(job, error: error, archive: archive)
                    }
                }
            }
        }
    }

    private func finishJob(_ job: MoveAssessmentJob) {
        if activeJob == job {
            activeJob = nil
        }
        refreshPendingState()
        // Do not nil `processorTask` here — the loop owns that. Clearing it while the
        // processor is between jobs lets a second processor start and race the queue.
    }

    /// Put an in-flight job back so cancel / game-switch cannot leave a permanent hourglass.
    private func requeueInterruptedJob(_ job: MoveAssessmentJob, reason: String) {
        if activeJob == job {
            activeJob = nil
        }
        pendingJobs.removeAll { $0.gameID == job.gameID && $0.moveIndex == job.moveIndex }
        pendingJobs.insert(job, at: 0)
        refreshPendingState()
        log("requeue \(Self.jobLabel(job)) — \(reason) queue=\(pendingJobCount)")
    }

    private func handleAssessmentFailure(
        _ job: MoveAssessmentJob,
        error: Error,
        archive: PGNArchive
    ) {
        // Mating moves often fail fenAfter eval; still mark them so the hourglass clears.
        if job.isCheckmate {
            let evalCP = MoveAssessmentClassifier.whitePerspectiveCentipawns(
                rawScoreAfter: .mate(0),
                moveIndex: job.moveIndex,
                deliveredCheckmate: true
            )
            let applied = archive.applyMoveAssessment(
                gameID: job.gameID,
                moveIndex: job.moveIndex,
                quality: .good,
                centipawnLoss: 0,
                evaluationWhiteCentipawns: evalCP,
                expectedSAN: job.playedMoveSAN,
                expectedFrom: job.from,
                expectedTo: job.to
            )
            if applied {
                onAssessmentApplied?()
                log("ok \(Self.jobLabel(job)) good cpl=0 (checkmate fallback) queue=\(pendingJobCount)")
            } else {
                log("checkmate fallback apply missed \(Self.jobLabel(job))")
            }
            finishJob(job)
            return
        }

        if job.attempt < 1 {
            let retry = MoveAssessmentJob(
                gameID: job.gameID,
                moveIndex: job.moveIndex,
                fenBeforeMove: job.fenBeforeMove,
                fenAfterMove: job.fenAfterMove,
                playedMoveSAN: job.playedMoveSAN,
                from: job.from,
                to: job.to,
                isCheckmate: job.isCheckmate,
                attempt: job.attempt + 1
            )
            pendingJobs.removeAll { $0.gameID == job.gameID && $0.moveIndex == job.moveIndex }
            pendingJobs.insert(retry, at: 0)
            log(
                "retry \(Self.jobLabel(job)) after \(Self.errorDescription(error)) queue=\(pendingJobCount)"
            )
            finishJob(job)
            return
        }

        log(
            "FAIL \(Self.jobLabel(job)) \(Self.errorDescription(error)) queue=\(pendingJobCount)"
        )
        finishJob(job)
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

    private func log(_ message: String) {
        guard isTracingEnabled else { return }
        print("MoveAssessment: \(message)")
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private static func jobLabel(_ job: MoveAssessmentJob) -> String {
        plyLabel(gameID: job.gameID, moveIndex: job.moveIndex, san: job.playedMoveSAN)
    }

    private static func plyLabel(gameID: UUID, moveIndex: Int, san: String) -> String {
        let fullMove = moveIndex / 2 + 1
        let side = moveIndex % 2 == 0 ? "" : "..."
        return "game=\(shortID(gameID)) ply=\(moveIndex) \(fullMove).\(side)\(san)"
    }

    private static func evalLabel(_ centipawns: Int) -> String {
        String(format: "%+.2f", Double(centipawns) / 100.0)
    }

    private static func errorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(nsError.domain) \(nsError.code) \"\(nsError.localizedDescription)\""
        if let reason = nsError.localizedFailureReason, !reason.isEmpty {
            text += " reason=\"\(reason)\""
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " underlying=\(underlying.domain) \(underlying.code)"
        }
        return text
    }
}
