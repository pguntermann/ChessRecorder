//
//  MoveNavigationBar.swift
//  Chess Recorder
//

import SwiftUI

struct MoveNavigationBar: View {
    let game: ChessGame
    var moveQualities: [MoveQuality?] = []
    var showMoveAssessments: Bool = false
    var assessmentColors: MoveAssessmentColors = .defaults
    var iconHitSize: CGFloat = 44
    /// False while the startup overlay covers the board. Defer tip-pinning until chrome is visible.
    var isChromeReady: Bool = true
    /// True during game-switch slides — defer tip-pin until after the transition.
    var isTipPinSuspended: Bool = false
    var onGoToFirst: () -> Void
    var onGoToPrevious: () -> Void
    var onGoToNext: () -> Void
    var onGoToLatest: () -> Void
    var onGoToPly: (Int) -> Void
    var onFlipBoard: () -> Void

    @State private var tipPinTask: Task<Void, Never>?
    @State private var pendingTipPinAfterResume = false

    var body: some View {
        HStack(spacing: 6) {
            turnIndicator

            navigationButton(
                systemName: "backward.end",
                label: "First move",
                isEnabled: game.canGoToFirst,
                action: onGoToFirst
            )

            navigationButton(
                systemName: "chevron.left",
                label: "Previous move",
                isEnabled: game.canGoBack,
                action: onGoToPrevious
            )

            moveStrip
                .frame(maxWidth: .infinity)

            navigationButton(
                systemName: "chevron.right",
                label: "Next move",
                isEnabled: game.canGoForward,
                action: onGoToNext
            )

            navigationButton(
                systemName: "forward.end",
                label: "Last move",
                isEnabled: game.canGoToLatest,
                action: onGoToLatest
            )

            Button(action: onFlipBoard) {
                ToolbarIconLabel("arrow.up.arrow.down", hitSize: iconHitSize)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Turn board")
        }
        .padding(.horizontal, 4)
        .onDisappear {
            tipPinTask?.cancel()
            tipPinTask = nil
        }
    }

    private var turnIndicator: some View {
        Circle()
            .fill(game.currentTurn == .white ? Color.white : Color.black)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
            .accessibilityLabel(game.currentTurn == .white ? "White to move" : "Black to move")
    }

    private var moveStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if game.moves.isEmpty {
                        Text("No moves yet")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // Lazy: keep token cost low on ContentView redraws. Tip-pinning must
                        // walk IDs so trailing cells are realized before the final scrollTo.
                        LazyHStack(spacing: 4) {
                            ForEach(Array(game.moves.enumerated()), id: \.offset) { index, move in
                                if index % 2 == 0 {
                                    moveNumberToken(
                                        id: "number-\(index)",
                                        text: "\(index / 2 + 1).",
                                        moveIndex: index
                                    )
                                }

                                assessedMoveToken(
                                    id: "move-\(index)",
                                    move: move,
                                    moveIndex: index,
                                    quality: quality(at: index)
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                scheduleTipPinIfNeeded(using: proxy)
            }
            .onChange(of: isChromeReady) { _, ready in
                guard ready else { return }
                scheduleTipPinIfNeeded(using: proxy)
            }
            .onChange(of: isTipPinSuspended) { _, suspended in
                if suspended {
                    tipPinTask?.cancel()
                    tipPinTask = nil
                } else if pendingTipPinAfterResume {
                    pendingTipPinAfterResume = false
                    scheduleTipPinIfNeeded(using: proxy)
                }
            }
            .onChange(of: game.activePlyIndex) { _, _ in
                guard !isTipPinSuspended else { return }
                scrollToActiveMove(using: proxy, animated: true)
            }
            .onChange(of: game.moves.count) { _, _ in
                if game.isAtLatestMove {
                    scheduleTipPinIfNeeded(using: proxy)
                } else {
                    guard !isTipPinSuspended else { return }
                    scrollToActiveMove(using: proxy, animated: true)
                }
            }
            .onChange(of: moveStripLayoutKey) { _, _ in
                guard !isTipPinSuspended, game.isAtLatestMove else { return }
                scrollToActiveMove(using: proxy, animated: false)
            }
        }
        .frame(height: iconHitSize)
    }

    /// Invalidates when token widths change without a ply/count change (e.g. `??` appears).
    private var moveStripLayoutKey: String {
        moveQualities.map { $0?.rawValue ?? "-" }.joined(separator: ",")
    }

    private func quality(at index: Int) -> MoveQuality? {
        guard showMoveAssessments, index < moveQualities.count else { return nil }
        return moveQualities[index]
    }

    private func scheduleTipPinIfNeeded(using proxy: ScrollViewProxy) {
        guard isChromeReady, game.isAtLatestMove, !game.moves.isEmpty else { return }

        if isTipPinSuspended {
            pendingTipPinAfterResume = true
            return
        }

        tipPinTask?.cancel()
        tipPinTask = Task { @MainActor in
            // Let the startup overlay finish fading and the strip receive a real width.
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await pinToLatestMove(using: proxy)
        }
    }

    /// Walks move IDs toward the tip so `LazyHStack` realizes cells before the final pin.
    private func pinToLatestMove(using proxy: ScrollViewProxy) async {
        let count = game.moves.count
        guard count > 0, game.isAtLatestMove else { return }

        let lastIndex = count - 1
        // Coarse waypoints force lazy materialization without visiting every ply.
        let step = max(1, count / 6)
        var waypoint = 0
        while waypoint < lastIndex {
            guard !Task.isCancelled, game.isAtLatestMove, game.moves.count == count else { return }
            proxy.scrollTo("move-\(waypoint)", anchor: .trailing)
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
            waypoint += step
        }

        guard !Task.isCancelled, game.isAtLatestMove else { return }
        proxy.scrollTo("move-\(lastIndex)", anchor: .trailing)
        // One follow-up after the last token has been measured.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(32))
        guard !Task.isCancelled, game.isAtLatestMove, game.moves.count == count else { return }
        proxy.scrollTo("move-\(lastIndex)", anchor: .trailing)
    }

    private func scrollToActiveMove(using proxy: ScrollViewProxy, animated: Bool) {
        guard isChromeReady else { return }

        if game.isAtLatestMove {
            // New moves at the tip: last ID was just inserted and should already be nearby.
            let targetID = game.moves.isEmpty ? nil : "move-\(game.moves.count - 1)"
            guard let targetID else { return }
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(targetID, anchor: .trailing)
                }
            } else {
                proxy.scrollTo(targetID, anchor: .trailing)
            }
            return
        }

        let targetID: String
        let anchor: UnitPoint
        if game.activePlyIndex == 0 {
            targetID = "number-0"
            anchor = .leading
        } else {
            targetID = "move-\(game.activePlyIndex - 1)"
            anchor = .center
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(targetID, anchor: anchor)
            }
        } else {
            proxy.scrollTo(targetID, anchor: anchor)
        }
    }

    private func moveNumberToken(id: String, text: String, moveIndex: Int) -> some View {
        let isDimmed = !game.isAtLatestMove && moveIndex >= game.activePlyIndex

        return Button {
            onGoToPly(moveIndex)
        } label: {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isDimmed ? Color.secondary.opacity(0.45) : Color.secondary)
                .padding(.horizontal, 0)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityLabel("Move \(text.trimmingCharacters(in: .whitespaces))")
    }

    private func assessedMoveToken(
        id: String,
        move: ChessMove,
        moveIndex: Int,
        quality: MoveQuality?
    ) -> some View {
        let isActive = game.activePlyIndex == moveIndex + 1
        let isDimmed = !game.isAtLatestMove && moveIndex >= game.activePlyIndex
        let displayText = move.algebraicNotation + (quality?.annotationSymbol ?? "")
        let showsDecoration = quality?.showsAssessmentDecoration == true

        return Button {
            onGoToPly(moveIndex + 1)
        } label: {
            Text(displayText)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isDimmed ? Color.secondary.opacity(0.45) : Color.primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.25))
                    }
                }
                .overlay(alignment: .bottom) {
                    if showsDecoration, let quality {
                        Capsule()
                            .fill(assessmentColors.underlineColor(for: quality))
                            .frame(height: 2.5)
                            .padding(.horizontal, 1)
                            .offset(y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityLabel(accessibilityLabel(for: move, quality: quality, isActive: isActive))
    }

    private func accessibilityLabel(for move: ChessMove, quality: MoveQuality?, isActive: Bool) -> String {
        let prefix = isActive ? "Current move, " : ""
        let annotation = quality?.annotationSymbol ?? ""
        let assessment = quality.map { ", \($0.rawValue)" } ?? ""
        return "\(prefix)\(move.algebraicNotation)\(annotation)\(assessment)"
    }

    private func navigationButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ToolbarIconLabel(systemName, hitSize: iconHitSize)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.35))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
