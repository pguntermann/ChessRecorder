//
//  GameReportPDFComposer.swift
//  Chess Recorder
//

import CoreImage
import CoreText
import SwiftUI
import UIKit

enum GameReportPDFComposer {
    struct Input {
        let recordedGame: RecordedGame
        let summary: GameAccuracySummary
        let whiteName: String
        let blackName: String
        let boardAppearance: MiniChessBoardAppearance
        let assessmentColors: MoveAssessmentColors
        var evaluationChartImage: UIImage? = nil
        var accuracyChartImage: UIImage? = nil
        var cumulativeAccuracyChartImage: UIImage? = nil
    }

    struct KeyPosition {
        let title: String
        let subtitle: String
        /// Insert the diagram after this 0-based move index (−1 = before movetext).
        let afterMoveIndex: Int
        let fen: String
        let from: ChessPosition?
        let to: ChessPosition?
    }

    enum ComposeError: LocalizedError {
        case failedToCreatePDF

        var errorDescription: String? {
            "Could not create the PDF report."
        }
    }

    private enum Theme {
        static let accent = UIColor(red: 0.14, green: 0.32, blue: 0.48, alpha: 1)
        static let accentSoft = UIColor(red: 0.14, green: 0.32, blue: 0.48, alpha: 0.10)
        static let rule = UIColor(red: 0.14, green: 0.32, blue: 0.48, alpha: 0.28)
        static let cardFill = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        static let muted = UIColor.darkGray
        static let hairline = UIColor(white: 0.82, alpha: 1)
        static let margin: CGFloat = 36
        static let contentWidth: CGFloat = 612 - 72
        /// Leave room for the branded two-line footer above the bottom accent bar.
        static let bottomContentInset: CGFloat = 58
        static let footerHeight: CGFloat = 36
    }

    @MainActor
    static func writeTemporaryPDF(input: Input) throws -> URL {
        let data = try renderPDF(input: input)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "ChessRecorder-Round\(input.recordedGame.round)-\(formatter.string(from: Date())).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    static func renderPDF(input: Input) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let boardAppearance = GameReportPDFBoardRenderer.Appearance.from(miniBoard: input.boardAppearance)
        let fens = ChessGame.prepared(from: input.recordedGame.moves, result: input.recordedGame.result)
            .fenSequenceFromStart()
        let diagrams = makeKeyPositions(
            moves: input.recordedGame.moves,
            summary: input.summary,
            fens: fens
        )
        let pgnWithSymbols = PGNExportService.pgn(
            for: input.recordedGame,
            includeAssessmentSymbols: true
        )
        let lichessURL = LichessAnalysisURL.make(
            fromMoves: input.recordedGame.moves,
            result: input.recordedGame.result
        )
        let qrImage = lichessURL.flatMap {
            qrCodeImage(from: $0.absoluteString, dimension: 512)
        }

        let data = renderer.pdfData { context in
            func beginPage() {
                context.beginPage()
                drawPageChrome(in: pageRect)
            }

            beginPage()
            var y = drawHeader(input: input, in: pageRect, at: 28)

            y = drawOverviewAndQR(
                input: input,
                qrImage: qrImage,
                hasLichessURL: lichessURL != nil,
                in: pageRect,
                at: y + 14
            )

            if input.summary.white.hasContent || input.summary.black.hasContent {
                if y > pageRect.height - Theme.bottomContentInset - 140 {
                    beginPage()
                    y = Theme.margin
                }
                y = drawMoveQualitySection(input: input, in: pageRect, at: y + 12)
            }

            if input.summary.isAssessmentIncomplete {
                y = drawIncompleteNotice(input.summary, in: pageRect, at: y + 10)
            }

            if input.evaluationChartImage != nil
                || input.accuracyChartImage != nil
                || input.cumulativeAccuracyChartImage != nil {
                y = drawCharts(input: input, in: pageRect, at: y + 16, beginNewPage: beginPage)
            }

            if y > pageRect.height - Theme.bottomContentInset - 180 {
                beginPage()
                y = Theme.margin
            }
            _ = drawAnnotatedGame(
                pgn: pgnWithSymbols,
                moves: input.recordedGame.moves,
                colors: input.assessmentColors,
                diagrams: diagrams,
                appearance: boardAppearance,
                in: pageRect,
                at: y + 18,
                beginNewPage: beginPage
            )
        }

        guard !data.isEmpty else { throw ComposeError.failedToCreatePDF }
        return data
    }

    // MARK: - Diagrams

    static func makeKeyPositions(
        moves: [ChessMove],
        summary: GameAccuracySummary,
        fens: [String]
    ) -> [KeyPosition] {
        var result: [KeyPosition] = []
        var usedPlies = Set<Int>()

        for transition in summary.evaluationPhaseTransitions {
            guard transition.ply < fens.count, !usedPlies.contains(transition.ply) else { continue }
            usedPlies.insert(transition.ply)
            result.append(
                KeyPosition(
                    title: transition.label,
                    subtitle: moveLabel(forPly: transition.ply),
                    afterMoveIndex: transition.ply - 1,
                    fen: fens[transition.ply],
                    from: nil,
                    to: nil
                )
            )
        }

        for critical in summary.evaluationCriticalPlies {
            let moveIndex = critical.ply - 1
            guard moveIndex >= 0, moveIndex < moves.count else { continue }
            // Position after the error; insert right after that move in the notation.
            let fenPly = critical.ply
            guard fenPly < fens.count, !usedPlies.contains(fenPly) else { continue }
            usedPlies.insert(fenPly)
            let move = moves[moveIndex]
            result.append(
                KeyPosition(
                    title: criticalTitle(quality: critical.quality, san: move.san),
                    subtitle: moveLabel(forPly: critical.ply),
                    afterMoveIndex: moveIndex,
                    fen: fens[fenPly],
                    from: move.from,
                    to: move.to
                )
            )
        }

        return result.sorted {
            if $0.afterMoveIndex != $1.afterMoveIndex {
                return $0.afterMoveIndex < $1.afterMoveIndex
            }
            return $0.title < $1.title
        }
    }

    private static func moveLabel(forPly ply: Int) -> String {
        guard ply > 0 else { return "Start" }
        let moveNumber = (ply + 1) / 2
        let isWhite = ply % 2 == 1
        return isWhite ? "After \(moveNumber)." : "After \(moveNumber)..."
    }

    private static func criticalTitle(quality: MoveQuality, san: String) -> String {
        let label: String
        switch quality {
        case .blunder: label = "Blunder"
        case .mistake: label = "Mistake"
        case .miss: label = "Miss"
        case .inaccuracy: label = "Inaccuracy"
        case .good, .book: label = "Critical"
        }
        return "\(label) · \(san)"
    }

    // MARK: - Page chrome & header

    private static func drawPageChrome(in page: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setFillColor(Theme.accent.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: page.width, height: 6))
        cg.setFillColor(Theme.rule.cgColor)
        cg.fill(CGRect(x: 0, y: page.height - 4, width: page.width, height: 4))

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let stamp = formatter.string(from: Date())
        let line1 = "Generated with PGN Chess Recorder \(AppInfo.version)  ·  \(stamp)"
        let line2 = AppInfo.repositoryURL.absoluteString
        let font = UIFont.systemFont(ofSize: 7.5)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Theme.muted
        ]
        let line1Size = (line1 as NSString).size(withAttributes: attrs)
        let line2Size = (line2 as NSString).size(withAttributes: attrs)
        let totalHeight = line1Size.height + 2 + line2Size.height
        let top = page.height - Theme.footerHeight + (Theme.footerHeight - totalHeight) / 2 - 2
        (line1 as NSString).draw(at: CGPoint(x: Theme.margin, y: top), withAttributes: attrs)
        (line2 as NSString).draw(
            at: CGPoint(x: Theme.margin, y: top + line1Size.height + 2),
            withAttributes: attrs
        )
    }

    @discardableResult
    private static func drawHeader(input: Input, in page: CGRect, at y: CGFloat) -> CGFloat {
        let x = Theme.margin
        let width = Theme.contentWidth

        var cursor = drawText(
            "GAME REPORT",
            font: .systemFont(ofSize: 9, weight: .bold),
            color: Theme.accent,
            in: page,
            at: y,
            width: width,
            tracking: 1.2
        )

        cursor = drawText(
            "Round \(input.recordedGame.round)",
            font: .systemFont(ofSize: 22, weight: .bold),
            color: .black,
            in: page,
            at: cursor + 4,
            width: width
        )

        let players = "\(input.whiteName)  —  \(input.blackName)"
        cursor = drawText(
            players,
            font: .systemFont(ofSize: 13, weight: .medium),
            color: .black,
            in: page,
            at: cursor + 4,
            width: width * 0.72
        )

        // Result badge on the right.
        let result = input.recordedGame.result.rawValue
        let resultFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let resultSize = (result as NSString).size(withAttributes: [.font: resultFont])
        let badgeW = resultSize.width + 16
        let badgeH: CGFloat = 22
        let badgeRect = CGRect(x: page.width - Theme.margin - badgeW, y: cursor - 20, width: badgeW, height: badgeH)
        fillRoundedRect(badgeRect, color: Theme.accent, radius: 4)
        drawCenteredText(result, font: resultFont, color: .white, in: badgeRect)

        var meta: [String] = []
        if let eco = input.recordedGame.eco, !eco.isEmpty {
            meta.append("ECO \(eco)")
        }
        let date = DateFormatter.localizedString(from: input.recordedGame.date, dateStyle: .medium, timeStyle: .none)
        meta.append(date)
        if !meta.isEmpty {
            cursor = drawText(
                meta.joined(separator: "  ·  "),
                font: .systemFont(ofSize: 10),
                color: Theme.muted,
                in: page,
                at: max(cursor, badgeRect.maxY) + 4,
                width: width
            )
        }

        // Accent rule under header.
        let ruleY = cursor + 10
        drawHorizontalRule(at: ruleY, x: x, width: width, color: Theme.accent, thickness: 1.5)
        return ruleY + 2
    }

    // MARK: - Overview + QR

    @discardableResult
    private static func drawOverviewAndQR(
        input: Input,
        qrImage: UIImage?,
        hasLichessURL: Bool,
        in page: CGRect,
        at y: CGFloat
    ) -> CGFloat {
        let gap: CGFloat = 14
        let showQR = qrImage != nil || (!hasLichessURL && !input.recordedGame.moves.isEmpty)
        let qrColumn: CGFloat = showQR ? 148 : 0
        let leftWidth = Theme.contentWidth - (showQR ? qrColumn + gap : 0)
        let leftX = Theme.margin

        let overviewHeight = overviewCardHeight(input: input, width: leftWidth)
        let cardHeight = overviewHeight

        drawOverviewCard(
            input: input,
            in: CGRect(x: leftX, y: y, width: leftWidth, height: cardHeight)
        )

        if let qrImage {
            drawQRCard(
                qrImage,
                in: CGRect(x: leftX + leftWidth + gap, y: y, width: qrColumn, height: cardHeight)
            )
        } else if showQR {
            drawQRUnavailableCard(
                in: CGRect(x: leftX + leftWidth + gap, y: y, width: qrColumn, height: cardHeight)
            )
        }

        return y + cardHeight
    }

    private static func overviewCardHeight(input: Input, width: CGFloat) -> CGFloat {
        let padding: CGFloat = 12
        var height = padding
        height += 12 + 8 // section label
        height += 56 + 10 // accuracy row
        if input.summary.scoredMoveCount > 0 || input.summary.blunderCount > 0 {
            height += 16 // table header
            height += 3 * 15 // metric rows
        }
        height += padding
        return height
    }

    private static func drawOverviewCard(input: Input, in cardRect: CGRect) {
        let padding: CGFloat = 12
        let innerWidth = cardRect.width - padding * 2
        fillRoundedRect(cardRect, color: Theme.cardFill, radius: 8)
        strokeRoundedRect(cardRect, color: Theme.hairline, radius: 8, lineWidth: 0.75)

        var cursor = cardRect.minY + padding
        cursor = drawSectionLabel(
            "Overview",
            at: cursor,
            x: cardRect.minX + padding,
            width: innerWidth
        ) + 8

        cursor = drawAccuracyComparison(
            input: input,
            x: cardRect.minX + padding,
            width: innerWidth,
            at: cursor
        ) + 10

        if input.summary.scoredMoveCount > 0 || input.summary.blunderCount > 0 {
            _ = drawMetricsTable(
                input: input,
                x: cardRect.minX + padding,
                width: innerWidth,
                at: cursor
            )
        }
    }

    private static func drawAccuracyComparison(
        input: Input,
        x: CGFloat,
        width: CGFloat,
        at y: CGFloat
    ) -> CGFloat {
        let rowH: CGFloat = 56
        let showResult = input.recordedGame.result.isFinal
        let resultW: CGFloat = showResult ? 22 : 0
        let dividerW: CGFloat = 12
        let sideW = (width - dividerW - resultW * 2) / 2

        var cursorX = x
        drawAccuracyScore(
            name: input.whiteName,
            value: input.summary.white.accuracyText,
            bookCount: input.summary.white.bookCount,
            in: CGRect(x: cursorX, y: y, width: sideW, height: rowH),
            accent: UIColor(white: 0.38, alpha: 1),
            alignment: .center
        )
        cursorX += sideW

        if showResult {
            drawCenteredText(
                resultPoint(for: .white, result: input.recordedGame.result),
                font: .systemFont(ofSize: 16, weight: .semibold),
                color: Theme.muted,
                in: CGRect(x: cursorX, y: y, width: resultW, height: rowH)
            )
            cursorX += resultW
        }

        // Vertical divider
        if let cg = UIGraphicsGetCurrentContext() {
            cg.setStrokeColor(Theme.hairline.cgColor)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: cursorX + dividerW / 2, y: y + 10))
            cg.addLine(to: CGPoint(x: cursorX + dividerW / 2, y: y + rowH - 10))
            cg.strokePath()
        }
        cursorX += dividerW

        if showResult {
            drawCenteredText(
                resultPoint(for: .black, result: input.recordedGame.result),
                font: .systemFont(ofSize: 16, weight: .semibold),
                color: Theme.muted,
                in: CGRect(x: cursorX, y: y, width: resultW, height: rowH)
            )
            cursorX += resultW
        }

        drawAccuracyScore(
            name: input.blackName,
            value: input.summary.black.accuracyText,
            bookCount: input.summary.black.bookCount,
            in: CGRect(x: cursorX, y: y, width: sideW, height: rowH),
            accent: .black,
            alignment: .center
        )

        return y + rowH
    }

    private static func resultPoint(for side: GameAccuracySummary.Side, result: PGNResult) -> String {
        switch result {
        case .whiteWins: return side == .white ? "1" : "0"
        case .blackWins: return side == .white ? "0" : "1"
        case .draw: return "½"
        case .ongoing: return ""
        }
    }

    private static func drawMetricsTable(
        input: Input,
        x: CGFloat,
        width: CGFloat,
        at y: CGFloat
    ) -> CGFloat {
        let labelW = width * 0.34
        let colW = (width - labelW) / 2
        let rowH: CGFloat = 15
        let headerFont = UIFont.systemFont(ofSize: 8, weight: .semibold)
        let labelFont = UIFont.systemFont(ofSize: 9)
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

        // Header: player names as columns (no W/B).
        drawText(
            "",
            font: headerFont,
            color: Theme.muted,
            in: .zero,
            at: y,
            x: x,
            width: labelW
        )
        drawCenteredText(
            truncatedName(input.whiteName, maxWidth: colW - 4, font: headerFont),
            font: headerFont,
            color: Theme.muted,
            in: CGRect(x: x + labelW, y: y, width: colW, height: rowH)
        )
        drawCenteredText(
            truncatedName(input.blackName, maxWidth: colW - 4, font: headerFont),
            font: headerFont,
            color: Theme.muted,
            in: CGRect(x: x + labelW + colW, y: y, width: colW, height: rowH)
        )

        let rows: [(String, String, String)] = [
            ("Avg CPL", input.summary.white.averageCPLText, input.summary.black.averageCPLText),
            ("Best-move %", input.summary.white.bestMoveText, input.summary.black.bestMoveText),
            ("Blunder rate", input.summary.white.blunderRateText, input.summary.black.blunderRateText)
        ]

        var cursor = y + rowH + 1
        for (index, row) in rows.enumerated() {
            if index % 2 == 0 {
                fillRoundedRect(
                    CGRect(x: x, y: cursor - 1, width: width, height: rowH),
                    color: UIColor.white.withAlphaComponent(0.65),
                    radius: 2
                )
            }
            drawText(row.0, font: labelFont, color: Theme.muted, in: .zero, at: cursor, x: x, width: labelW)
            drawCenteredText(
                row.1,
                font: valueFont,
                color: UIColor(white: 0.35, alpha: 1),
                in: CGRect(x: x + labelW, y: cursor, width: colW, height: rowH)
            )
            drawCenteredText(
                row.2,
                font: valueFont,
                color: .black,
                in: CGRect(x: x + labelW + colW, y: cursor, width: colW, height: rowH)
            )
            cursor += rowH
        }
        return cursor
    }

    private static func truncatedName(_ name: String, maxWidth: CGFloat, font: UIFont) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (name as NSString).size(withAttributes: attrs).width <= maxWidth {
            return name
        }
        var truncated = name
        while truncated.count > 1 {
            truncated = String(truncated.dropLast())
            let candidate = truncated + "…"
            if (candidate as NSString).size(withAttributes: attrs).width <= maxWidth {
                return candidate
            }
        }
        return "…"
    }

    private static func drawAccuracyScore(
        name: String,
        value: String,
        bookCount: Int,
        in rect: CGRect,
        accent: UIColor,
        alignment: NSTextAlignment
    ) {
        let nameFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        let bookFont = UIFont.systemFont(ofSize: 8)

        let nameSize = (name as NSString).boundingRect(
            with: CGSize(width: rect.width, height: 14),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: nameFont],
            context: nil
        )
        let valueSize = (value as NSString).size(withAttributes: [.font: valueFont])

        var textY = rect.minY + 6
        let nameRect = CGRect(
            x: rect.minX,
            y: textY,
            width: rect.width,
            height: ceil(nameSize.height)
        )
        drawAlignedText(name, font: nameFont, color: Theme.muted, in: nameRect, alignment: alignment)
        textY = nameRect.maxY + 2

        let valueRect = CGRect(x: rect.minX, y: textY, width: rect.width, height: valueSize.height)
        drawAlignedText(value, font: valueFont, color: accent, in: valueRect, alignment: alignment)
        textY = valueRect.maxY + 1

        if bookCount > 0 {
            let book = "\(bookCount) book"
            let bookRect = CGRect(x: rect.minX, y: textY, width: rect.width, height: 12)
            drawAlignedText(book, font: bookFont, color: Theme.muted, in: bookRect, alignment: alignment)
        }
    }

    private static func drawAlignedText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        in rect: CGRect,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func drawQRCard(_ image: UIImage, in cardRect: CGRect) {
        fillRoundedRect(cardRect, color: Theme.cardFill, radius: 8)
        strokeRoundedRect(cardRect, color: Theme.hairline, radius: 8, lineWidth: 0.75)

        // Match overview card padding so section labels share a baseline.
        let padding: CGFloat = 12
        _ = drawSectionLabel(
            "Lichess",
            at: cardRect.minY + padding,
            x: cardRect.minX + padding,
            width: cardRect.width - padding * 2
        )

        let labelH: CGFloat = 12
        let captionH: CGFloat = 22
        let available = cardRect.height - padding - labelH - 4 - captionH - padding
        let qrSide = min(cardRect.width - padding * 2, available)
        let qrRect = CGRect(
            x: cardRect.midX - qrSide / 2,
            y: cardRect.minY + padding + labelH + 4 + max(0, (available - qrSide) / 2),
            width: qrSide,
            height: qrSide
        )
        UIColor.white.setFill()
        UIBezierPath(roundedRect: qrRect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3).fill()
        if let cg = UIGraphicsGetCurrentContext() {
            cg.interpolationQuality = .none
        }
        image.draw(in: qrRect)

        drawCenteredText(
            "Scan for analysis",
            font: .systemFont(ofSize: 8),
            color: Theme.muted,
            in: CGRect(
                x: cardRect.minX + 4,
                y: cardRect.maxY - padding - captionH + 4,
                width: cardRect.width - 8,
                height: captionH
            )
        )
    }

    private static func drawQRUnavailableCard(in cardRect: CGRect) {
        fillRoundedRect(cardRect, color: Theme.cardFill, radius: 8)
        strokeRoundedRect(cardRect, color: Theme.hairline, radius: 8, lineWidth: 0.75)
        let padding: CGFloat = 12
        _ = drawSectionLabel(
            "Lichess",
            at: cardRect.minY + padding,
            x: cardRect.minX + padding,
            width: cardRect.width - padding * 2
        )
        _ = drawText(
            "Game too long for a Lichess QR — share the PGN instead.",
            font: .systemFont(ofSize: 8.5),
            color: Theme.muted,
            in: .zero,
            at: cardRect.minY + padding + 16,
            x: cardRect.minX + padding,
            width: cardRect.width - padding * 2
        )
    }

    // MARK: - Move quality

    @discardableResult
    private static func drawMoveQualitySection(input: Input, in page: CGRect, at y: CGFloat) -> CGFloat {
        var cursor = drawSectionTitle("Move quality", in: page, at: y)
        cursor += 8

        let padding: CGFloat = 12
        let pieSize: CGFloat = 72
        let tableWidth: CGFloat = 150
        let cardHeight = padding + 14 + max(pieSize, CGFloat(qualityTableRowCount(input: input)) * 14 + 4) + padding
        let cardRect = CGRect(x: Theme.margin, y: cursor, width: Theme.contentWidth, height: cardHeight)
        fillRoundedRect(cardRect, color: Theme.cardFill, radius: 8)
        strokeRoundedRect(cardRect, color: Theme.hairline, radius: 8, lineWidth: 0.75)

        let innerY = cardRect.minY + padding
        let gap: CGFloat = 10
        let sideColW = (cardRect.width - padding * 2 - tableWidth - gap * 2) / 2

        // White pie
        drawQualityPieColumn(
            name: input.whiteName,
            stats: input.summary.white,
            colors: input.assessmentColors,
            in: CGRect(x: cardRect.minX + padding, y: innerY, width: sideColW, height: pieSize + 16)
        )

        // Center count table
        let tableX = cardRect.minX + padding + sideColW + gap
        drawQualityCountTable(
            input: input,
            in: CGRect(x: tableX, y: innerY + 4, width: tableWidth, height: cardHeight - padding * 2)
        )

        // Black pie
        drawQualityPieColumn(
            name: input.blackName,
            stats: input.summary.black,
            colors: input.assessmentColors,
            in: CGRect(
                x: tableX + tableWidth + gap,
                y: innerY,
                width: sideColW,
                height: pieSize + 16
            )
        )

        return cardRect.maxY
    }

    private static func qualityTableRowCount(input: Input) -> Int {
        let qualities: [MoveQuality] = [.book, .good, .inaccuracy, .mistake, .blunder, .miss]
        return qualities.filter { qualityCount($0, in: input.summary.white) + qualityCount($0, in: input.summary.black) > 0 }.count
    }

    private static func qualityCount(_ quality: MoveQuality, in stats: GameAccuracySummary.SideStats) -> Int {
        switch quality {
        case .good: return stats.goodCount
        case .book: return stats.bookCount
        case .inaccuracy: return stats.inaccuracyCount
        case .mistake: return stats.mistakeCount
        case .blunder: return stats.blunderCount
        case .miss: return stats.missCount
        }
    }

    private static func qualityLabel(_ quality: MoveQuality) -> String {
        switch quality {
        case .good: return "Good"
        case .book: return "Book"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        case .miss: return "Miss"
        }
    }

    private static func qualityColor(_ quality: MoveQuality, colors: MoveAssessmentColors) -> UIColor {
        switch quality {
        case .good: return UIColor.systemGreen.withAlphaComponent(0.85)
        case .book:
            // Distinct slate so book slices read on the light card fill.
            return UIColor(red: 0.45, green: 0.52, blue: 0.60, alpha: 1)
        case .inaccuracy: return UIColor(colors.underlineColor(for: .inaccuracy))
        case .mistake: return UIColor(colors.underlineColor(for: .mistake))
        case .blunder: return UIColor(colors.underlineColor(for: .blunder))
        case .miss: return UIColor(colors.underlineColor(for: .miss))
        }
    }

    private static func drawQualityPieColumn(
        name: String,
        stats: GameAccuracySummary.SideStats,
        colors: MoveAssessmentColors,
        in rect: CGRect
    ) {
        drawCenteredText(
            truncatedName(name, maxWidth: rect.width, font: .systemFont(ofSize: 8, weight: .semibold)),
            font: .systemFont(ofSize: 8, weight: .semibold),
            color: Theme.muted,
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 12)
        )

        let pieSide: CGFloat = 72
        let pieRect = CGRect(
            x: rect.midX - pieSide / 2,
            y: rect.minY + 14,
            width: pieSide,
            height: pieSide
        )
        let slices = stats.qualitySlices.map { ($0.quality, CGFloat($0.count)) }
        drawDonut(slices: slices, colors: colors, in: pieRect)
    }

    private static func drawQualityCountTable(input: Input, in rect: CGRect) {
        let qualities: [MoveQuality] = [.book, .good, .inaccuracy, .mistake, .blunder, .miss]
        let rows = qualities.filter {
            qualityCount($0, in: input.summary.white) + qualityCount($0, in: input.summary.black) > 0
        }
        let rowH: CGFloat = 14
        let labelW = rect.width * 0.48
        let colW = (rect.width - labelW) / 2
        let font = UIFont.systemFont(ofSize: 8.5)
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)

        for (index, quality) in rows.enumerated() {
            let y = rect.minY + CGFloat(index) * rowH
            let color = qualityColor(quality, colors: input.assessmentColors)

            // Color dot
            let dot = CGRect(x: rect.minX, y: y + 4, width: 6, height: 6)
            color.setFill()
            UIBezierPath(ovalIn: dot).fill()

            drawText(
                qualityLabel(quality),
                font: font,
                color: Theme.muted,
                in: .zero,
                at: y,
                x: rect.minX + 10,
                width: labelW - 10
            )
            drawCenteredText(
                "\(qualityCount(quality, in: input.summary.white))",
                font: valueFont,
                color: Theme.muted,
                in: CGRect(x: rect.minX + labelW, y: y, width: colW, height: rowH)
            )
            drawCenteredText(
                "\(qualityCount(quality, in: input.summary.black))",
                font: valueFont,
                color: Theme.muted,
                in: CGRect(x: rect.minX + labelW + colW, y: y, width: colW, height: rowH)
            )
        }
    }

    private static func drawDonut(
        slices: [(MoveQuality, CGFloat)],
        colors: MoveAssessmentColors,
        in rect: CGRect
    ) {
        let total = slices.reduce(CGFloat(0)) { $0 + $1.1 }
        guard total > 0 else {
            drawCenteredText("—", font: .systemFont(ofSize: 18), color: Theme.hairline, in: rect)
            return
        }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.52
        var start = -CGFloat.pi / 2

        for (quality, count) in slices where count > 0 {
            let angle = 2 * .pi * (count / total)
            let end = start + angle
            let path = UIBezierPath()
            path.addArc(withCenter: center, radius: outer, startAngle: start, endAngle: end, clockwise: true)
            path.addArc(withCenter: center, radius: inner, startAngle: end, endAngle: start, clockwise: false)
            path.close()
            qualityColor(quality, colors: colors).setFill()
            path.fill()
            start = end
        }
    }

    // MARK: - Charts

    @discardableResult
    private static func drawCharts(
        input: Input,
        in page: CGRect,
        at y: CGFloat,
        beginNewPage: () -> Void
    ) -> CGFloat {
        struct ChartItem {
            let title: String
            let subtitle: String
            let image: UIImage
        }

        var items: [ChartItem] = []
        if let eval = input.evaluationChartImage {
            items.append(
                ChartItem(
                    title: "Evaluation",
                    subtitle: "White’s perspective (±\(Int(GameAccuracySummary.evaluationScaleCapPawns)) pawns)",
                    image: eval
                )
            )
        }
        if let accuracy = input.accuracyChartImage {
            items.append(
                ChartItem(
                    title: "Running accuracy",
                    subtitle: "Accuracy if the game had ended at each move",
                    image: accuracy
                )
            )
        }
        if let cumulative = input.cumulativeAccuracyChartImage {
            items.append(
                ChartItem(
                    title: "Cumulative accuracy",
                    subtitle: "How the final accuracy was lost over time",
                    image: cumulative
                )
            )
        }
        guard !items.isEmpty else { return y }

        var cursor = y
        var sectionTitleDrawnOnPage = false
        var placedAnyChart = false
        /// Section title + underline + spacing before the first card on a page.
        let sectionHeaderHeight: CGFloat = 24

        for item in items {
            let cardHeight = chartCardHeight(for: item.image)
            let headerHeight = sectionTitleDrawnOnPage ? 0 : sectionHeaderHeight
            let limit = page.height - Theme.bottomContentInset

            // Keep the section title with at least one chart — never orphan the header.
            if cursor + headerHeight + cardHeight > limit {
                beginNewPage()
                cursor = Theme.margin
                sectionTitleDrawnOnPage = false
            }

            if !sectionTitleDrawnOnPage {
                let title = placedAnyChart ? "Charts (continued)" : "Charts"
                cursor = drawSectionTitle(title, in: page, at: cursor) + 8
                sectionTitleDrawnOnPage = true
            }

            cursor = drawChartCard(
                title: item.title,
                subtitle: item.subtitle,
                image: item.image,
                in: page,
                at: cursor
            ) + 10
            placedAnyChart = true
        }

        return cursor
    }

    private static func chartCardHeight(for image: UIImage) -> CGFloat {
        let padding: CGFloat = 10
        let titleH: CGFloat = 28
        let maxImageH: CGFloat = 148
        let aspect = image.size.width / max(image.size.height, 1)
        var imageH = (Theme.contentWidth - padding * 2) / aspect
        if imageH > maxImageH {
            imageH = maxImageH
        }
        return padding + titleH + imageH + padding
    }

    private static func drawChartCard(
        title: String,
        subtitle: String,
        image: UIImage,
        in page: CGRect,
        at y: CGFloat
    ) -> CGFloat {
        let x = Theme.margin
        let width = Theme.contentWidth
        let padding: CGFloat = 10
        let titleH: CGFloat = 28
        let maxImageH: CGFloat = 148
        let aspect = image.size.width / max(image.size.height, 1)
        var imageW = width - padding * 2
        var imageH = imageW / aspect
        if imageH > maxImageH {
            imageH = maxImageH
            imageW = imageH * aspect
        }
        let cardH = padding + titleH + imageH + padding
        let cardRect = CGRect(x: x, y: y, width: width, height: cardH)
        fillRoundedRect(cardRect, color: Theme.cardFill, radius: 8)
        strokeRoundedRect(cardRect, color: Theme.hairline, radius: 8, lineWidth: 0.75)

        drawText(
            title,
            font: .systemFont(ofSize: 11, weight: .bold),
            color: Theme.accent,
            in: .zero,
            at: y + padding,
            x: x + padding,
            width: width - padding * 2
        )
        drawText(
            subtitle,
            font: .systemFont(ofSize: 8.5),
            color: Theme.muted,
            in: .zero,
            at: y + padding + 14,
            x: x + padding,
            width: width - padding * 2
        )

        let imageRect = CGRect(
            x: x + padding + (width - padding * 2 - imageW) / 2,
            y: y + padding + titleH,
            width: imageW,
            height: imageH
        )
        UIColor.white.setFill()
        UIRectFill(imageRect)
        image.draw(in: imageRect)
        return cardRect.maxY
    }

    // MARK: - Annotated game (PGN + inline boards)

    @discardableResult
    private static func drawAnnotatedGame(
        pgn: String,
        moves: [ChessMove],
        colors: MoveAssessmentColors,
        diagrams: [KeyPosition],
        appearance: GameReportPDFBoardRenderer.Appearance,
        in page: CGRect,
        at y: CGFloat,
        beginNewPage: () -> Void
    ) -> CGFloat {
        var cursor = drawSectionTitle("Annotated game", in: page, at: y)
        cursor += 8

        let parts = pgn.components(separatedBy: "\n\n")
        let headers = parts.first ?? ""
        let movetext = parts.dropFirst().joined(separator: "\n\n")

        // Compact header block.
        let headerFont = UIFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: Theme.muted
        ]
        let headerAttributed = NSAttributedString(string: headers, attributes: headerAttrs)
        let headerBounds = headerAttributed.boundingRect(
            with: CGSize(width: Theme.contentWidth - 16, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let headerCard = CGRect(
            x: Theme.margin,
            y: cursor,
            width: Theme.contentWidth,
            height: ceil(headerBounds.height) + 16
        )
        fillRoundedRect(headerCard, color: Theme.accentSoft, radius: 6)
        headerAttributed.draw(
            with: CGRect(x: Theme.margin + 8, y: cursor + 8, width: Theme.contentWidth - 16, height: headerBounds.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        cursor = headerCard.maxY + 12

        let attributed = attributedMovetext(movetext, moves: moves, colors: colors)
        let endOffsets = moveEndUTF16Offsets(in: movetext, moves: moves)

        // Group diagrams by insertion offset.
        struct Insertion {
            let utf16Offset: Int
            let diagram: KeyPosition
        }
        var insertions: [Insertion] = []
        for diagram in diagrams {
            let offset: Int
            if diagram.afterMoveIndex < 0 {
                offset = 0
            } else if diagram.afterMoveIndex < endOffsets.count {
                offset = endOffsets[diagram.afterMoveIndex]
            } else {
                offset = attributed.length
            }
            insertions.append(Insertion(utf16Offset: offset, diagram: diagram))
        }
        insertions.sort { $0.utf16Offset < $1.utf16Offset }

        var textStart = 0
        var insertionIndex = 0

        func ensureSpace(_ needed: CGFloat) {
            if cursor + needed > page.height - Theme.bottomContentInset {
                beginNewPage()
                cursor = Theme.margin
            }
        }

        while textStart < attributed.length || insertionIndex < insertions.count {
            let nextOffset: Int
            if insertionIndex < insertions.count {
                nextOffset = min(insertions[insertionIndex].utf16Offset, attributed.length)
            } else {
                nextOffset = attributed.length
            }

            if nextOffset > textStart {
                let chunk = attributed.attributedSubstring(
                    from: NSRange(location: textStart, length: nextOffset - textStart)
                )
                cursor = drawFlowingAttributedText(
                    chunk,
                    in: page,
                    at: cursor,
                    beginNewPage: beginNewPage
                )
                textStart = nextOffset
            }

            while insertionIndex < insertions.count,
                  insertions[insertionIndex].utf16Offset <= textStart {
                let item = insertions[insertionIndex]
                insertionIndex += 1
                ensureSpace(150)
                cursor = drawInlineDiagram(
                    item.diagram,
                    appearance: appearance,
                    in: page,
                    at: cursor + 6
                ) + 8
            }

            if textStart >= attributed.length, insertionIndex >= insertions.count {
                break
            }
            // Avoid infinite loop if an insertion offset is somehow behind.
            if insertionIndex < insertions.count,
               insertions[insertionIndex].utf16Offset < textStart {
                insertionIndex += 1
            }
        }

        return cursor
    }

    private static func moveEndUTF16Offsets(in movetext: String, moves: [ChessMove]) -> [Int] {
        var offsets: [Int] = []
        var searchStart = movetext.startIndex
        for move in moves {
            let token = PGNFormatter.exportedMoveText(for: move, includeAssessmentSymbols: true)
            guard let range = movetext.range(of: token, range: searchStart..<movetext.endIndex) else {
                offsets.append(offsets.last ?? 0)
                continue
            }
            var end = range.upperBound
            if end < movetext.endIndex, movetext[end].isWhitespace {
                end = movetext.index(after: end)
            }
            let utf16 = NSRange(movetext.startIndex..<end, in: movetext).length
            offsets.append(utf16)
            searchStart = end
        }
        return offsets
    }

    private static func drawInlineDiagram(
        _ position: KeyPosition,
        appearance: GameReportPDFBoardRenderer.Appearance,
        in page: CGRect,
        at y: CGFloat
    ) -> CGFloat {
        let boardSide: CGFloat = 132
        let gap: CGFloat = 12
        let x = Theme.margin
        let captionX = x + boardSide + gap
        let captionWidth = Theme.contentWidth - boardSide - gap

        drawHorizontalRule(at: y, x: Theme.margin, width: Theme.contentWidth, color: Theme.rule, thickness: 0.6)

        let boardY = y + 10
        let board = GameReportPDFBoardRenderer.render(
            fen: position.fen,
            side: boardSide,
            appearance: appearance,
            highlightedFrom: position.from,
            highlightedTo: position.to
        )
        board.draw(in: CGRect(x: x, y: boardY, width: boardSide, height: boardSide))

        var textY = boardY + 10
        textY = drawText(
            position.title,
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .black,
            in: .zero,
            at: textY,
            x: captionX,
            width: captionWidth
        ) + 3
        textY = drawText(
            position.subtitle,
            font: .systemFont(ofSize: 9),
            color: Theme.muted,
            in: .zero,
            at: textY,
            x: captionX,
            width: captionWidth
        )

        let bottom = max(boardY + boardSide, textY) + 10
        drawHorizontalRule(at: bottom, x: Theme.margin, width: Theme.contentWidth, color: Theme.rule, thickness: 0.6)
        return bottom
    }

    private static func drawFlowingAttributedText(
        _ attributed: NSAttributedString,
        in page: CGRect,
        at y: CGFloat,
        beginNewPage: () -> Void
    ) -> CGFloat {
        var cursor = y
        var remaining = attributed
        let maxWidth = Theme.contentWidth

        while remaining.length > 0 {
            let availableHeight = page.height - cursor - Theme.bottomContentInset
            if availableHeight < 28 {
                beginNewPage()
                cursor = Theme.margin
            }

            let constraint = CGSize(width: maxWidth, height: page.height - cursor - Theme.bottomContentInset)
            let framesetter = CTFramesetterCreateWithAttributedString(remaining as CFAttributedString)
            var fittedRange = CFRange()
            let suggestSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: 0),
                nil,
                constraint,
                &fittedRange
            )
            let drawHeight = ceil(max(suggestSize.height, 12))
            let drawRect = CGRect(x: Theme.margin, y: cursor, width: maxWidth, height: drawHeight)

            guard let cg = UIGraphicsGetCurrentContext() else { break }
            cg.saveGState()
            cg.textMatrix = .identity
            cg.translateBy(x: 0, y: drawRect.maxY)
            cg.scaleBy(x: 1, y: -1)
            let path = CGPath(
                rect: CGRect(x: drawRect.minX, y: 0, width: drawRect.width, height: drawRect.height),
                transform: nil
            )
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: fittedRange.length),
                path,
                nil
            )
            CTFrameDraw(frame, cg)
            cg.restoreGState()

            cursor = drawRect.maxY + 2
            if fittedRange.length <= 0 || fittedRange.length >= remaining.length {
                break
            }
            remaining = remaining.attributedSubstring(
                from: NSRange(location: fittedRange.length, length: remaining.length - fittedRange.length)
            )
            beginNewPage()
            cursor = Theme.margin
        }

        return cursor
    }

    private static func attributedMovetext(
        _ movetext: String,
        moves: [ChessMove],
        colors: MoveAssessmentColors
    ) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 2

        let regularFont = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        let boldFont = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .bold)

        let base = NSMutableAttributedString(
            string: movetext,
            attributes: [
                .font: regularFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
        )

        // Bold move numbers (`1.`, `23.`) and the trailing result token.
        if let numberRegex = try? NSRegularExpression(pattern: #"\b\d+\."#) {
            let full = NSRange(location: 0, length: (movetext as NSString).length)
            numberRegex.enumerateMatches(in: movetext, options: [], range: full) { match, _, _ in
                guard let match else { return }
                base.addAttribute(.font, value: boldFont, range: match.range)
            }
        }
        boldTrailingResult(in: base, of: movetext, font: boldFont)

        var searchStart = movetext.startIndex
        for move in moves {
            guard let quality = move.quality, quality.showsAssessmentDecoration else { continue }
            let token = PGNFormatter.exportedMoveText(for: move, includeAssessmentSymbols: true)
            guard let range = movetext.range(of: token, range: searchStart..<movetext.endIndex) else {
                continue
            }
            let nsRange = NSRange(range, in: movetext)
            let uiColor = UIColor(colors.underlineColor(for: quality))
            base.addAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: uiColor,
                    .foregroundColor: uiColor.withAlphaComponent(0.95)
                ],
                range: nsRange
            )
            searchStart = range.upperBound
        }
        return base
    }

    private static func boldTrailingResult(
        in attributed: NSMutableAttributedString,
        of movetext: String,
        font: UIFont
    ) {
        let results = ["1-0", "0-1", "1/2-1/2", "*"]
        let trimmed = movetext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = results.first(where: { trimmed.hasSuffix($0) }) else { return }
        guard let range = movetext.range(of: result, options: .backwards) else { return }
        attributed.addAttribute(.font, value: font, range: NSRange(range, in: movetext))
    }

    // MARK: - Shared drawing helpers

    @discardableResult
    private static func drawIncompleteNotice(_ summary: GameAccuracySummary, in page: CGRect, at y: CGFloat) -> CGFloat {
        let count = summary.unassessedMoveCount
        let text = count == 1
            ? "1 move has not been assessed yet. Figures reflect assessed moves only."
            : "\(count) moves have not been assessed yet. Figures reflect assessed moves only."
        let width = Theme.contentWidth
        let font = UIFont.italicSystemFont(ofSize: 9.5)
        let height = ceil((text as NSString).boundingRect(
            with: CGSize(width: width - 20, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font],
            context: nil
        ).height) + 16
        let rect = CGRect(x: Theme.margin, y: y, width: width, height: height)
        fillRoundedRect(rect, color: UIColor.systemOrange.withAlphaComponent(0.12), radius: 6)
        strokeRoundedRect(rect, color: UIColor.systemOrange.withAlphaComponent(0.35), radius: 6, lineWidth: 0.6)
        return drawText(
            text,
            font: font,
            color: UIColor.brown,
            in: page,
            at: y + 8,
            x: Theme.margin + 10,
            width: width - 20
        ) + 8
    }

    @discardableResult
    private static func drawSectionTitle(_ title: String, in page: CGRect, at y: CGFloat) -> CGFloat {
        let text = title.uppercased()
        let font = UIFont.systemFont(ofSize: 11, weight: .bold)
        let tracking: CGFloat = 0.8
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Theme.accent,
            .kern: tracking
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textWidth = ceil(attributed.size().width)
        let cursor = drawText(
            text,
            font: font,
            color: Theme.accent,
            in: page,
            at: y,
            width: Theme.contentWidth,
            tracking: tracking
        )
        drawHorizontalRule(at: cursor + 4, x: Theme.margin, width: textWidth, color: Theme.accent, thickness: 2)
        return cursor + 6
    }

    @discardableResult
    private static func drawSectionLabel(_ title: String, at y: CGFloat, x: CGFloat, width: CGFloat) -> CGFloat {
        drawText(
            title.uppercased(),
            font: .systemFont(ofSize: 10, weight: .bold),
            color: Theme.accent,
            in: .zero,
            at: y,
            x: x,
            width: width,
            tracking: 0.7
        )
    }

    private static func fillRoundedRect(_ rect: CGRect, color: UIColor, radius: CGFloat) {
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    }

    private static func strokeRoundedRect(_ rect: CGRect, color: UIColor, radius: CGFloat, lineWidth: CGFloat) {
        color.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        path.lineWidth = lineWidth
        path.stroke()
    }

    private static func drawHorizontalRule(at y: CGFloat, x: CGFloat, width: CGFloat, color: UIColor, thickness: CGFloat) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(thickness)
        cg.move(to: CGPoint(x: x, y: y))
        cg.addLine(to: CGPoint(x: x + width, y: y))
        cg.strokePath()
    }

    private static func drawCenteredText(_ text: String, font: UIFont, color: UIColor, in rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    @discardableResult
    private static func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        in page: CGRect,
        at y: CGFloat,
        x: CGFloat = Theme.margin,
        width: CGFloat,
        tracking: CGFloat = 0
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if tracking != 0 {
            attrs[.kern] = tracking
        }
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let bounding = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let drawRect = CGRect(x: x, y: y, width: width, height: ceil(bounding.height))
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return drawRect.maxY
    }

    private static func qrCodeImage(from string: String, dimension: CGFloat) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        // Higher correction helps when the PDF is slightly soft / viewed at an angle.
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let modules = output.extent.width
        guard modules > 0 else { return nil }
        // Integer module scale keeps edges crisp when drawn into PDF.
        let moduleScale = max(1, floor(dimension / modules))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        // CIQRCodeGenerator omits the quiet zone; scanners need ~4 modules of white margin.
        let quiet = moduleScale * 4
        let finalSide = scaled.extent.width + quiet * 2
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: finalSide, height: finalSide), format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: finalSide, height: finalSide))
            ctx.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(
                in: CGRect(x: quiet, y: quiet, width: scaled.extent.width, height: scaled.extent.height)
            )
        }
    }
}
