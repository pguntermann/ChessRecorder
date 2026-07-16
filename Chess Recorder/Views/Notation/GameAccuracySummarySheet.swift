//
//  GameAccuracySummarySheet.swift
//  Chess Recorder
//

import Charts
import SwiftUI

struct GameAccuracySummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let summary: GameAccuracySummary
    let roundTitle: String
    var assessmentColors: MoveAssessmentColors = .defaults

    var body: some View {
        NavigationStack {
            List {
                Section {
                    accuracyComparison
                } header: {
                    Text("Accuracy")
                } footer: {
                    Text("Accuracy is based on average centipawn loss (book moves excluded).")
                }

                if summary.white.hasContent || summary.black.hasContent {
                    Section("Move quality") {
                        moveQualityComparison
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                }

                if summary.hasAccuracyProgress {
                    Section {
                        accuracyProgressChart
                            .frame(height: 200)
                            .padding(.vertical, 4)
                    } header: {
                        Text("Accuracy over game duration")
                    } footer: {
                        Text("Running accuracy after each scored move (book moves omitted).")
                    }
                }
            }
            .navigationTitle(roundTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var accuracyComparison: some View {
        HStack(spacing: 0) {
            accuracyScore(side: .white, stats: summary.white)
            Divider()
                .frame(height: 56)
            accuracyScore(side: .black, stats: summary.black)
        }
        .frame(maxWidth: .infinity)
    }

    private func accuracyScore(side: GameAccuracySummary.Side, stats: GameAccuracySummary.SideStats) -> some View {
        VStack(spacing: 4) {
            Text(side.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(stats.accuracyText)
                .font(.title.monospacedDigit().weight(.semibold))
                .foregroundStyle(sideAccent(side))
            if stats.bookCount > 0 {
                Text("\(stats.bookCount) book")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.label) accuracy \(stats.accuracyText)")
    }

    /// White pie | quality counts table | Black pie — single row, no mid-section separator.
    private var moveQualityComparison: some View {
        HStack(alignment: .center, spacing: 12) {
            qualityPieColumn(side: .white, stats: summary.white)
                .frame(maxWidth: .infinity)

            qualityCountTable

            qualityPieColumn(side: .black, stats: summary.black)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func qualityPieColumn(
        side: GameAccuracySummary.Side,
        stats: GameAccuracySummary.SideStats
    ) -> some View {
        VStack(spacing: 6) {
            Text(side.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if stats.qualitySlices.isEmpty {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(width: 88, height: 88)
            } else {
                Chart(stats.qualitySlices) { slice in
                    SectorMark(
                        angle: .value("Count", slice.count),
                        innerRadius: .ratio(0.52),
                        angularInset: 1.2
                    )
                    .cornerRadius(3)
                    .foregroundStyle(color(for: slice.quality))
                }
                .chartLegend(.hidden)
                .frame(width: 88, height: 88)
                .accessibilityLabel("\(side.label) move quality chart")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var qualityCountTable: some View {
        let qualities: [MoveQuality] = [.book, .good, .inaccuracy, .mistake, .blunder, .miss]
        let rows = qualities.filter { quality in
            count(quality, in: summary.white) + count(quality, in: summary.black) > 0
        }

        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            ForEach(rows, id: \.rawValue) { quality in
                GridRow {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(color(for: quality))
                            .frame(width: 7, height: 7)
                        Text(label(for: quality))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Text("\(count(quality, in: summary.white))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("\(count(quality, in: summary.black))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
    }

    private var accuracyProgressChart: some View {
        Chart {
            // Draw Black under White so overlapping segments stay a clean light stroke
            // (Black-on-White AA produces a grey fringe along the line edges).
            ForEach(progressPoints(for: .black)) { point in
                accuracyLineMark(for: point)
            }
            ForEach(progressPoints(for: .white)) { point in
                accuracyLineMark(for: point)
            }
        }
        .chartForegroundStyleScale([
            GameAccuracySummary.Side.white.label: sideAccent(.white),
            GameAccuracySummary.Side.black.label: sideAccent(.black)
        ])
        .chartLegend(position: .bottom, alignment: .center)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6))
        }
        .chartYScale(domain: accuracyProgressYDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)%")
                            .font(.caption2)
                    } else if let doubleValue = value.as(Double.self) {
                        Text("\(Int(doubleValue.rounded()))%")
                            .font(.caption2)
                    }
                }
            }
        }
    }

    private func progressPoints(for side: GameAccuracySummary.Side) -> [GameAccuracySummary.AccuracyProgressPoint] {
        summary.accuracyProgress.filter { $0.side == side }
    }

    private func accuracyLineMark(for point: GameAccuracySummary.AccuracyProgressPoint) -> some ChartContent {
        LineMark(
            x: .value("Move", point.moveNumber),
            y: .value("Accuracy", point.accuracyPercent),
            series: .value("Side", point.side.label)
        )
        .foregroundStyle(by: .value("Side", point.side.label))
        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        .interpolationMethod(.linear)
    }

    /// Zoom the Y-axis to the data range with a small buffer (still clamped to 0…100).
    private var accuracyProgressYDomain: ClosedRange<Double> {
        let values = summary.accuracyProgress.map(\.accuracyPercent)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...100
        }
        let span = max(maxValue - minValue, 8)
        let buffer = max(span * 0.15, 4)
        let lower = max(0, minValue - buffer)
        let upper = min(100, max(maxValue + buffer, lower + 8))
        return lower...upper
    }

    private func sideAccent(_ side: GameAccuracySummary.Side) -> Color {
        switch side {
        case .white:
            // Light “white-piece” tone; slightly off pure white so it reads on grey rows.
            return colorScheme == .dark ? Color(white: 0.92) : Color(white: 0.72)
        case .black:
            // Near-black for a true “black pieces” look on grey chart rows.
            return colorScheme == .dark ? Color(white: 0.06) : Color.black
        }
    }

    private func color(for quality: MoveQuality) -> Color {
        switch quality {
        case .good: return Color.green.opacity(0.85)
        case .book: return Color.secondary.opacity(0.55)
        case .inaccuracy: return assessmentColors.inaccuracy
        case .mistake: return assessmentColors.mistake
        case .blunder: return assessmentColors.blunder
        case .miss: return assessmentColors.miss
        }
    }

    private func label(for quality: MoveQuality) -> String {
        switch quality {
        case .good: return "Good"
        case .book: return "Book"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        case .miss: return "Miss"
        }
    }

    private func count(_ quality: MoveQuality, in stats: GameAccuracySummary.SideStats) -> Int {
        switch quality {
        case .good: return stats.goodCount
        case .book: return stats.bookCount
        case .inaccuracy: return stats.inaccuracyCount
        case .mistake: return stats.mistakeCount
        case .blunder: return stats.blunderCount
        case .miss: return stats.missCount
        }
    }
}
