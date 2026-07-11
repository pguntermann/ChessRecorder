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

    private var isEnabled: Bool {
        isEngineReady && isEngineActive
    }

    private var displayTopFraction: Double {
        isEnabled ? topFraction : 0.5
    }

    private var displayBottomFraction: Double {
        isEnabled ? bottomFraction : 0.5
    }

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let topHeight = max(totalHeight * displayTopFraction, 0)
            let bottomHeight = max(totalHeight * displayBottomFraction, 0)

            ZStack {
                VStack(spacing: 0) {
                    segmentColor(isTop: true)
                        .frame(height: topHeight)
                    segmentColor(isTop: false)
                        .frame(height: bottomHeight)
                }

                if isEnabled {
                    tickOverlay(totalHeight: totalHeight, barWidth: geometry.size.width)
                }

                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        Color.secondary.opacity(isEnabled ? 0.45 : 0.25),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.55)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func segmentColor(isTop: Bool) -> Color {
        guard isEnabled else {
            return Color.secondary.opacity(isTop ? 0.28 : 0.14)
        }
        return isTop ? topColor : bottomColor
    }

    private func tickOverlay(totalHeight: CGFloat, barWidth: CGFloat) -> some View {
        let tickWidth = max(4, barWidth * (8 / 38))
        let tickInset = barWidth * (16 / 38)
        let labelSize = max(7, barWidth * (9 / 38))

        return ZStack(alignment: .topTrailing) {
            ForEach(tickMarks) { tick in
                let y = tickYPosition(for: tick.pawns, totalHeight: totalHeight)
                let tickColor = tickForegroundColor(for: tick.pawns)

                Rectangle()
                    .fill(tickColor.opacity(0.9))
                    .frame(width: tickWidth, height: 1)
                    .offset(x: -tickInset, y: y)

                if let label = tick.label {
                    Text(label)
                        .font(.system(size: labelSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(tickColor)
                        .offset(x: 0, y: y - labelSize * 0.65)
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
