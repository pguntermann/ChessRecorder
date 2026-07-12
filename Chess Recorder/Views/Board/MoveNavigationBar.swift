//
//  MoveNavigationBar.swift
//  Chess Recorder
//

import SwiftUI

struct MoveNavigationBar: View {
    let game: ChessGame
    var iconHitSize: CGFloat = 44
    var onGoToFirst: () -> Void
    var onGoToPrevious: () -> Void
    var onGoToNext: () -> Void
    var onGoToLatest: () -> Void
    var onGoToPly: (Int) -> Void
    var onFlipBoard: () -> Void

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
                        ForEach(Array(game.moves.enumerated()), id: \.offset) { index, move in
                            if index % 2 == 0 {
                                moveToken(
                                    id: "number-\(index)",
                                    text: "\(index / 2 + 1).",
                                    isMoveNumber: true,
                                    moveIndex: index,
                                    action: { onGoToPly(index) }
                                )
                            }

                            moveToken(
                                id: "move-\(index)",
                                text: move.algebraicNotation,
                                isMoveNumber: false,
                                moveIndex: index,
                                action: { onGoToPly(index + 1) }
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                scrollToActiveMove(using: proxy, animated: false)
            }
            .onChange(of: game.activePlyIndex) { _, _ in
                scrollToActiveMove(using: proxy, animated: true)
            }
            .onChange(of: game.moves.count) { _, _ in
                scrollToActiveMove(using: proxy, animated: true)
            }
        }
        .frame(height: iconHitSize)
    }

    private func moveToken(
        id: String,
        text: String,
        isMoveNumber: Bool,
        moveIndex: Int,
        action: @escaping () -> Void
    ) -> some View {
        let isActive = !isMoveNumber && game.activePlyIndex == moveIndex + 1
        let isDimmed = !game.isAtLatestMove && moveIndex >= game.activePlyIndex

        return Button(action: action) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(tokenColor(isMoveNumber: isMoveNumber, isDimmed: isDimmed))
                .padding(.horizontal, isMoveNumber ? 0 : 4)
                .padding(.vertical, 3)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.25))
                    }
                }
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityLabel(accessibilityLabel(for: text, isMoveNumber: isMoveNumber, isActive: isActive))
    }

    private func tokenColor(isMoveNumber: Bool, isDimmed: Bool) -> Color {
        if isDimmed {
            return .secondary.opacity(0.45)
        }
        return isMoveNumber ? .secondary : .primary
    }

    private func accessibilityLabel(for text: String, isMoveNumber: Bool, isActive: Bool) -> String {
        let prefix = isActive ? "Current move, " : ""
        if isMoveNumber {
            return "\(prefix)Move \(text.trimmingCharacters(in: .whitespaces))"
        }
        return "\(prefix)\(text)"
    }

    private func scrollToActiveMove(using proxy: ScrollViewProxy, animated: Bool) {
        let targetID: String?
        if game.activePlyIndex == 0 {
            targetID = game.moves.isEmpty ? nil : "number-0"
        } else {
            targetID = "move-\(game.activePlyIndex - 1)"
        }

        guard let targetID else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        } else {
            proxy.scrollTo(targetID, anchor: .center)
        }
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
