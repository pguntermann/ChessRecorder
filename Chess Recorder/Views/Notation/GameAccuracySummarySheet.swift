//
//  GameAccuracySummarySheet.swift
//  Chess Recorder
//

import Charts
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct GameAccuracySummarySheet: View {
    private struct ShareablePDFExport: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct ChessComAnalysisLink: Identifiable {
        let id = UUID()
        let url: URL
        let pgn: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let summary: GameAccuracySummary
    let recordedGame: RecordedGame
    let roundTitle: String
    var result: PGNResult = .ongoing
    var whiteName: String = GameAccuracySummary.Side.white.label
    var blackName: String = GameAccuracySummary.Side.black.label
    var assessmentColors: MoveAssessmentColors = .defaults
    var boardAppearance: MiniChessBoardAppearance = .default

    @State private var progressMode: GameAccuracySummary.AccuracyProgressMode = .running
    @State private var isExportingPDF = false
    @State private var exportErrorMessage: String?
    @State private var pdfExportItem: ShareablePDFExport?
    @State private var chessComLink: ChessComAnalysisLink?

    /// Uses the PGN tag when it has a real value; otherwise `White` / `Black`.
    static func playerDisplayName(from tag: String, fallback: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "?" else { return fallback }
        return trimmed
    }

    private var lichessAnalysisURL: URL? {
        LichessAnalysisURL.make(
            fromMoves: recordedGame.moves,
            result: recordedGame.result,
            maxCharacterCount: LichessAnalysisURL.maxBrowserURLCharacterCount
        )
    }

    private var chessComAnalysisURL: URL? {
        ChessComAnalysisURL.make(
            fromMoves: recordedGame.moves,
            result: recordedGame.result,
            maxCharacterCount: ChessComAnalysisURL.maxBrowserURLCharacterCount
        )
    }

    private var chessComPGN: String? {
        ChessComAnalysisURL.pgnMovetext(
            from: recordedGame.moves,
            result: recordedGame.result
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    overviewSection
                } header: {
                    Text("Overview")
                } footer: {
                    Text(overviewFooter)
                }

                if summary.isAssessmentIncomplete {
                    Section {
                        Label {
                            Text(incompleteAssessmentMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "hourglass")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if summary.hasEvaluationProgress {
                    Section {
                        evaluationChart
                            .frame(height: 200)
                            .padding(.vertical, 4)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    } header: {
                        Text("Evaluation")
                    } footer: {
                        Text(evaluationChartFooter)
                    }
                }

                if summary.white.hasContent || summary.black.hasContent {
                    Section("Move quality") {
                        moveQualityComparison
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                }

                if summary.hasAccuracyProgress {
                    Section {
                        Picker("Chart mode", selection: $progressMode) {
                            ForEach(GameAccuracySummary.AccuracyProgressMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                        accuracyProgressChart
                            .frame(height: 200)
                            .padding(.vertical, 4)
                    } header: {
                        Text("Accuracy over game duration")
                    } footer: {
                        Text(accuracyProgressFooter)
                    }
                }

                if !recordedGame.moves.isEmpty {
                    Section {
                        if let url = lichessAnalysisURL {
                            Link(destination: url) {
                                Label("Analyze on Lichess", systemImage: "arrow.up.right.square")
                            }
                            .accessibilityHint("Opens this game on the Lichess analysis board")
                        } else {
                            Label {
                                Text("This game is too long to open as a Lichess analysis link. Share the PGN instead.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "link.badge.plus")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }

                        if let url = chessComAnalysisURL, let pgn = chessComPGN {
                            Button {
                                chessComLink = ChessComAnalysisLink(url: url, pgn: pgn)
                            } label: {
                                Label("Analyze on Chess.com", systemImage: "arrow.up.right.square")
                            }
                            .accessibilityHint("Opens Chess.com analysis and copies the PGN")
                        } else {
                            Label {
                                Text("This game is too long to open as a Chess.com analysis link. Share the PGN instead.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "link.badge.plus")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("For the best indepth Desktop analysis, use CARA — the free open source Chess Analysis and Review Application for macOS, Windows and Linux.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Link(destination: AppInfo.caraWebsiteURL) {
                                Text(AppInfo.caraWebsiteURL.absoluteString)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityLabel("CARA website")
                        }
                    } header: {
                        Text("External analysis")
                    }
                }
            }
            .navigationTitle(roundTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        exportPDF()
                    } label: {
                        if isExportingPDF {
                            ProgressView()
                        } else {
                            Label("PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExportingPDF)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isExportingPDF)
                }
            }
            .overlay {
                if isExportingPDF {
                    ZStack {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Preparing PDF…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Preparing PDF")
                }
            }
            #if os(iOS)
            .sheet(item: $pdfExportItem, onDismiss: cleanupPDFExport) { item in
                ShareSheet(items: [item.url])
            }
            .fullScreenCover(item: $chessComLink) { link in
                ChessComAnalysisBrowser(url: link.url, pgn: link.pgn)
            }
            #endif
            .alert("Export Failed", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "")
            }
        }
    }

    private func cleanupPDFExport() {
        if let pdfExportItem {
            try? FileManager.default.removeItem(at: pdfExportItem.url)
        }
        pdfExportItem = nil
    }

    @MainActor
    private func exportPDF() {
        guard !isExportingPDF else { return }
        isExportingPDF = true
        exportErrorMessage = nil

        Task { @MainActor in
            // Let the overlay/spinner paint before the heavy render work.
            await Task.yield()

            let evaluationChartImage = summary.hasEvaluationProgress
                ? renderChartImage(evaluationChart)
                : nil
            let accuracyChartImage = summary.hasAccuracyProgress
                ? renderChartImage(chartMarks(for: .running, printFriendly: true).frame(height: 200))
                : nil
            let cumulativeAccuracyChartImage = summary.hasAccuracyProgress
                ? renderChartImage(chartMarks(for: .cumulative, printFriendly: true).frame(height: 200))
                : nil

            do {
                let url = try GameReportPDFComposer.writeTemporaryPDF(
                    input: GameReportPDFComposer.Input(
                        recordedGame: recordedGame,
                        summary: summary,
                        whiteName: whiteName,
                        blackName: blackName,
                        boardAppearance: boardAppearance,
                        assessmentColors: assessmentColors,
                        evaluationChartImage: evaluationChartImage,
                        accuracyChartImage: accuracyChartImage,
                        cumulativeAccuracyChartImage: cumulativeAccuracyChartImage
                    )
                )
                pdfExportItem = ShareablePDFExport(url: url)
            } catch {
                exportErrorMessage = error.localizedDescription
            }
            isExportingPDF = false
        }
    }

    @MainActor
    private func renderChartImage<Content: View>(_ content: Content) -> UIImage? {
        // Give the Chart itself enough height for Y labels + X labels + legend, then add
        // outer margins so ImageRenderer does not clip glyph overhang.
        let chartView = content
            .frame(width: 488, height: 248, alignment: .center)
            .padding(.top, 12)
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.bottom, 14)
            .background(Color.white)
        let renderer = ImageRenderer(content: chartView)
        renderer.scale = 2
        return renderer.uiImage
    }

    private var overviewSection: some View {
        VStack(spacing: 14) {
            accuracyComparison
            if summary.scoredMoveCount > 0 || summary.blunderCount > 0 {
                overviewMetricsTable
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewFooter: String {
        "Accuracy uses average centipawn loss (book excluded). Best-move % is the share of scored moves with 0 CPL. Blunder rate is among all assessed moves."
    }

    private var incompleteAssessmentMessage: String {
        let count = summary.unassessedMoveCount
        if count == 1 {
            return "1 move has not been assessed yet. Accuracy and charts reflect assessed moves only."
        }
        return "\(count) moves have not been assessed yet. Accuracy and charts reflect assessed moves only."
    }

    private var accuracyComparison: some View {
        HStack(spacing: 0) {
            accuracyScore(side: .white, stats: summary.white)

            if result.isFinal {
                resultPointLabel(for: .white)
                    .padding(.trailing, 10)
            }

            Divider()
                .frame(height: 56)

            if result.isFinal {
                resultPointLabel(for: .black)
                    .padding(.leading, 10)
            }

            accuracyScore(side: .black, stats: summary.black)
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewMetricsTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            overviewMetricRow(label: "Avg CPL", white: summary.white.averageCPLText, black: summary.black.averageCPLText)
            overviewMetricRow(label: "Best-move %", white: summary.white.bestMoveText, black: summary.black.bestMoveText)
            overviewMetricRow(label: "Blunders", white: summary.white.blunderRateText, black: summary.black.blunderRateText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(overviewMetricsAccessibilityLabel)
    }

    private func overviewMetricRow(label: String, white: String, black: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(white)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(sideMetricAccent(.white))
                .frame(maxWidth: .infinity)
                .gridColumnAlignment(.center)
            Text(black)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(sideMetricAccent(.black))
                .frame(maxWidth: .infinity)
                .gridColumnAlignment(.center)
        }
    }

    private var overviewMetricsAccessibilityLabel: String {
        [
            "\(displayName(for: .white)) average CPL \(summary.white.averageCPLText), best-move \(summary.white.bestMoveText), blunder rate \(summary.white.blunderRateText)",
            "\(displayName(for: .black)) average CPL \(summary.black.averageCPLText), best-move \(summary.black.bestMoveText), blunder rate \(summary.black.blunderRateText)"
        ].joined(separator: ". ")
    }

    private var evaluationChartFooter: String {
        var parts = [
            "White’s perspective (±\(Int(GameAccuracySummary.evaluationScaleCapPawns)) pawns). Positive favors White."
        ]
        if !summary.evaluationPhaseTransitions.isEmpty {
            parts.append("Dashed lines mark middlegame and endgame.")
        }
        if !summary.evaluationCriticalPlies.isEmpty {
            parts.append("Dotted lines mark the largest mistakes.")
        }
        return parts.joined(separator: " ")
    }

    private var evaluationChart: some View {
        let points = summary.evaluationProgress
        let maxPly = points.map(\.ply).max() ?? 1
        let yCap = GameAccuracySummary.evaluationScaleCapPawns

        return Chart {
            ForEach(summary.evaluationCriticalPlies) { critical in
                RuleMark(x: .value("Critical", critical.ply))
                    .foregroundStyle(color(for: critical.quality).opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            ForEach(summary.evaluationPhaseTransitions) { transition in
                RuleMark(x: .value("Phase", transition.ply))
                    .foregroundStyle(phaseMarkerColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

            RuleMark(y: .value("Equal", 0))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(points) { point in
                LineMark(
                    x: .value("Ply", point.ply),
                    y: .value("Evaluation", point.evaluationPawns)
                )
                .foregroundStyle(Color.primary)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)
            }
        }
        .chartXScale(domain: 0...max(maxPly, 1))
        .chartYScale(domain: -yCap...yCap)
        .chartXAxis {
            AxisMarks(values: evaluationXAxisValues(maxPly: maxPly)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let ply = value.as(Int.self) {
                        Text(evaluationXLabel(forPly: ply))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [-10, -5, 0, 5, 10]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let pawns = value.as(Double.self) ?? value.as(Int.self).map(Double.init) {
                        Text(evaluationYLabel(pawns: pawns))
                            .font(.caption2)
                    }
                }
            }
        }
        .accessibilityLabel("Evaluation over the game from White’s perspective")
    }

    private var phaseMarkerColor: Color {
        colorScheme == .dark
            ? Color(red: 0.45, green: 0.65, blue: 1.0)
            : Color(red: 0.0, green: 0.55, blue: 0.5)
    }

    private func evaluationXAxisValues(maxPly: Int) -> [Int] {
        guard maxPly > 0 else { return [0] }
        let step = max(1, Int((Double(maxPly) / 6.0).rounded(.up)))
        var values = Array(stride(from: 0, through: maxPly, by: step))
        if values.last != maxPly {
            values.append(maxPly)
        }
        return values
    }

    private func evaluationXLabel(forPly ply: Int) -> String {
        guard ply > 0 else { return "0" }
        return "\(max(1, (ply + 1) / 2))"
    }

    private func evaluationYLabel(pawns: Double) -> String {
        if pawns == 0 { return "0" }
        return String(format: "%+.0f", pawns)
    }

    private func displayName(for side: GameAccuracySummary.Side) -> String {
        switch side {
        case .white: return whiteName
        case .black: return blackName
        }
    }

    private func accuracyScore(side: GameAccuracySummary.Side, stats: GameAccuracySummary.SideStats) -> some View {
        VStack(spacing: 4) {
            Text(displayName(for: side))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
        .accessibilityLabel(accuracyScoreAccessibilityLabel(side: side, stats: stats))
    }

    private func accuracyScoreAccessibilityLabel(
        side: GameAccuracySummary.Side,
        stats: GameAccuracySummary.SideStats
    ) -> String {
        var label = "\(displayName(for: side)) accuracy \(stats.accuracyText)"
        if result.isFinal {
            label += ", result \(resultPoint(for: side))"
        }
        return label
    }

    private func resultPointLabel(for side: GameAccuracySummary.Side) -> some View {
        let point = resultPoint(for: side)
        let won = sideWon(side)
        return Text(point)
            .font(.title2.monospacedDigit().weight(won ? .bold : .regular))
            .foregroundStyle(won ? sideAccent(side) : .secondary)
            .accessibilityHidden(true)
    }

    private func resultPoint(for side: GameAccuracySummary.Side) -> String {
        switch result {
        case .whiteWins:
            return side == .white ? "1" : "0"
        case .blackWins:
            return side == .white ? "0" : "1"
        case .draw:
            return "½"
        case .ongoing:
            return ""
        }
    }

    private func sideWon(_ side: GameAccuracySummary.Side) -> Bool {
        switch result {
        case .whiteWins: return side == .white
        case .blackWins: return side == .black
        case .draw, .ongoing: return false
        }
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
            Text(displayName(for: side))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

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
                .accessibilityLabel("\(displayName(for: side)) move quality chart")
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

    private var accuracyProgressXScale: GameAccuracySummary.AccuracyProgressXScale {
        // X positions are identical for both modes; either series works.
        GameAccuracySummary.AccuracyProgressXScale(progress: summary.accuracyProgress)
    }

    private var accuracyProgressFooter: String {
        var text = progressMode.chartFooter
        if accuracyProgressXScale.isCompressed {
            text += " Opening moves are compressed on the left."
        } else {
            text += " Book moves are omitted."
        }
        return text
    }

    private var accuracyProgressChart: some View {
        // Crossfade whole charts instead of morphing LineMarks (Charts' default looks glitchy).
        ZStack {
            chartMarks(for: progressMode)
                .id(progressMode)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .animation(.easeInOut(duration: 0.28), value: progressMode)
    }

    private func chartMarks(
        for mode: GameAccuracySummary.AccuracyProgressMode,
        printFriendly: Bool = false
    ) -> some View {
        let points = summary.accuracyProgress(for: mode)
        let xScale = accuracyProgressXScale
        let scoredMoves = points.map(\.moveNumber)
        let maxMove = scoredMoves.max() ?? xScale.firstScoredMove
        let axisMarks = xScale.axisMarks(scoredMoves: scoredMoves)
        let whiteStroke = printFriendly
            ? Color(red: 0.12, green: 0.42, blue: 0.72) // Blue reads clearly on print / white PDF
            : sideAccent(.white)
        let blackStroke = printFriendly ? Color.black : sideAccent(.black)

        return Chart {
            // Draw Black under White so overlapping segments stay a clean light stroke
            // (Black-on-White AA produces a grey fringe along the line edges).
            ForEach(points.filter { $0.side == .black }) { point in
                accuracyLineMark(for: point, xScale: xScale)
            }
            ForEach(points.filter { $0.side == .white }) { point in
                accuracyLineMark(for: point, xScale: xScale)
            }
        }
        .chartForegroundStyleScale([
            GameAccuracySummary.Side.white.label: whiteStroke,
            GameAccuracySummary.Side.black.label: blackStroke
        ])
        .chartLegend(position: .bottom, alignment: .center, spacing: printFriendly ? 10 : 8)
        .chartXScale(domain: xScale.domain(maxMoveNumber: maxMove))
        .chartXAxis {
            AxisMarks(values: axisMarks.map(\.x)) { value in
                AxisGridLine()
                AxisValueLabel {
                    let raw: Double? = value.as(Double.self) ?? value.as(Int.self).map(Double.init)
                    if let raw, let label = xScale.label(forAxisValue: raw, in: axisMarks) {
                        Text(label)
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: sharedAccuracyProgressYDomain)
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

    private func accuracyLineMark(
        for point: GameAccuracySummary.AccuracyProgressPoint,
        xScale: GameAccuracySummary.AccuracyProgressXScale
    ) -> some ChartContent {
        LineMark(
            x: .value("Move", xScale.plotX(moveNumber: point.moveNumber)),
            y: .value("Accuracy", point.accuracyPercent),
            series: .value("Side", point.side.label)
        )
        .foregroundStyle(by: .value("Side", point.side.label))
        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        .interpolationMethod(.linear)
    }

    /// Stable Y domain across both modes so the axis doesn't jump during the crossfade.
    private var sharedAccuracyProgressYDomain: ClosedRange<Double> {
        let values =
            summary.accuracyProgress.map(\.accuracyPercent)
            + summary.cumulativeAccuracyProgress.map(\.accuracyPercent)
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

    /// Readable side tint for caption-sized overview metrics (near-black is too faint at small sizes).
    private func sideMetricAccent(_ side: GameAccuracySummary.Side) -> Color {
        switch side {
        case .white:
            return colorScheme == .dark ? Color(white: 0.88) : Color(white: 0.42)
        case .black:
            return colorScheme == .dark ? Color(white: 0.78) : Color(white: 0.18)
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
