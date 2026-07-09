//
//  EvaluationBarView.swift
//  Chess Recorder
//

import SwiftUI

struct EvaluationBarView: View {
    private struct TickMark: Identifiable {
        let pawns: Double

        var id: Double { pawns }
        var label: String? {
            guard pawns != 0 else { return nil }
            return pawns > 0 ? "+\(Int(pawns))" : "\(Int(pawns))"
        }
    }

    let whiteFraction: Double
    let orientation: BoardOrientation
    let evaluationText: String
    let isEngineActive: Bool
    let isEngineReady: Bool

    private let tickMarks: [TickMark] = [
        TickMark(pawns: 5),
        TickMark(pawns: 3),
        TickMark(pawns: 2),
        TickMark(pawns: 1),
        TickMark(pawns: 0),
        TickMark(pawns: -1),
        TickMark(pawns: -2),
        TickMark(pawns: -3),
        TickMark(pawns: -5)
    ]

    private var clampedFraction: Double {
        min(max(whiteFraction, 0), 1)
    }

    private var topFraction: Double {
        orientation == .whiteAtBottom ? 1 - clampedFraction : clampedFraction
    }

    private var bottomFraction: Double {
        1 - topFraction
    }

    private var topColor: Color {
        orientation == .whiteAtBottom ? .black : .white
    }

    private var bottomColor: Color {
        orientation == .whiteAtBottom ? .white : .black
    }

    private var topSegmentIsDark: Bool {
        orientation == .whiteAtBottom
    }

    private var bottomSegmentIsDark: Bool {
        !topSegmentIsDark
    }

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let topHeight = max(totalHeight * topFraction, 0)
            let bottomHeight = max(totalHeight * bottomFraction, 0)

            ZStack {
                VStack(spacing: 0) {
                    topColor
                        .frame(height: topHeight)
                    bottomColor
                        .frame(height: bottomHeight)
                }

                tickOverlay(totalHeight: totalHeight)

                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(width: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func tickOverlay(totalHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(tickMarks) { tick in
                let y = tickYPosition(for: tick.pawns, totalHeight: totalHeight)
                let tickColor = tickForegroundColor(for: tick.pawns)

                Rectangle()
                    .fill(tickColor.opacity(0.9))
                    .frame(width: 8, height: 1)
                    .offset(x: -16, y: y)

                if let label = tick.label {
                    Text(label)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(tickColor)
                        .offset(x: 0, y: y - 6)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func tickYPosition(for pawns: Double, totalHeight: CGFloat) -> CGFloat {
        let whiteFraction = EngineAnalysisService.evaluationBarWhiteFraction(forPawns: pawns)
        let topFraction = orientation == .whiteAtBottom ? 1 - whiteFraction : whiteFraction
        return totalHeight * CGFloat(topFraction) - (totalHeight / 2)
    }

    private func tickForegroundColor(for pawns: Double) -> Color {
        let whiteFraction = EngineAnalysisService.evaluationBarWhiteFraction(forPawns: pawns)
        let tickOnTopSegment = (orientation == .whiteAtBottom ? 1 - whiteFraction : whiteFraction) <= topFraction
        let backgroundIsDark = tickOnTopSegment ? topSegmentIsDark : bottomSegmentIsDark
        return backgroundIsDark ? .white : .black
    }

    private var accessibilityLabel: String {
        guard isEngineReady else { return "Engine unavailable" }
        guard isEngineActive else { return "Evaluation bar inactive" }
        return "Evaluation \(evaluationText)"
    }
}
