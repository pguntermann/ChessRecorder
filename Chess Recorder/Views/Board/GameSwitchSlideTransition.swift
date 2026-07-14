//
//  GameSwitchSlideTransition.swift
//  Chess Recorder
//

import SwiftUI

enum GameSwitchSlideMetrics {
    static let duration: TimeInterval = 0.28

    static var animation: Animation {
        .easeInOut(duration: duration)
    }
}

/// Clips and horizontally slides its content when `offset` changes.
struct GameSwitchSlideContainer<Content: View>: View {
    @Binding var offset: CGFloat
    @Binding var measuredWidth: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            content()
                .offset(x: offset)
                .animation(GameSwitchSlideMetrics.animation, value: offset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            if width > 0 {
                measuredWidth = width
            }
        }
        .clipped()
    }
}

enum GameSwitchDirection {
    /// Older game selected (further down the PGN list): content exits right, enters from left.
    case towardOlder
    /// Newer game selected: content exits left, enters from right.
    case towardNewer

    var slideMultiplier: CGFloat {
        switch self {
        case .towardOlder: 1
        case .towardNewer: -1
        }
    }

    static func between(oldIndex: Int?, newIndex: Int?) -> GameSwitchDirection {
        guard let oldIndex, let newIndex, oldIndex != newIndex else {
            return .towardOlder
        }
        return newIndex > oldIndex ? .towardOlder : .towardNewer
    }
}

@MainActor
enum GameSwitchSlideAnimator {
    static func run(
        direction: GameSwitchDirection,
        distance: CGFloat,
        setOffset: @escaping (CGFloat) -> Void,
        swapContent: @escaping () -> Void
    ) async {
        await Task.yield()

        guard distance > 0 else {
            swapContent()
            return
        }

        let multiplier = direction.slideMultiplier
        let duration = GameSwitchSlideMetrics.duration

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            setOffset(0)
        }
        await Task.yield()

        setOffset(multiplier * distance)
        try? await Task.sleep(for: .seconds(duration))

        swapContent()

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            setOffset(-multiplier * distance)
        }

        setOffset(0)
        try? await Task.sleep(for: .seconds(duration))
    }
}
