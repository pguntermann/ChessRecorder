//
//  MoveQuality.swift
//  Chess Recorder
//

import LucidEngine
import SwiftUI

enum MoveQuality: String, Codable, Equatable, Sendable, CaseIterable {
    case blunder
    case mistake
    case inaccuracy
    case book
    case good
    case great
    case brilliant

    init(_ classification: MoveClassification) {
        switch classification {
        case .blunder: self = .blunder
        case .mistake: self = .mistake
        case .inaccuracy: self = .inaccuracy
        case .book: self = .book
        case .good: self = .good
        case .great: self = .great
        case .brilliant: self = .brilliant
        }
    }

    /// Classic PGN assessment suffix (e.g. `!`, `?!`, `??`).
    var annotationSymbol: String {
        switch self {
        case .brilliant: return "!!"
        case .great: return "!"
        case .good, .book: return ""
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        }
    }

    var showsAssessmentDecoration: Bool {
        switch self {
        case .good, .book: return false
        default: return true
        }
    }

    static let configurableCases: [MoveQuality] = [.brilliant, .great, .inaccuracy, .mistake, .blunder]
}

struct MoveAssessmentColors: Equatable {
    let brilliant: Color
    let great: Color
    let inaccuracy: Color
    let mistake: Color
    let blunder: Color

    func underlineColor(for quality: MoveQuality) -> Color {
        switch quality {
        case .brilliant: return brilliant
        case .great: return great
        case .inaccuracy: return inaccuracy
        case .mistake: return mistake
        case .blunder: return blunder
        case .good, .book: return .primary
        }
    }

    init(
        brilliant: Color,
        great: Color,
        inaccuracy: Color,
        mistake: Color,
        blunder: Color
    ) {
        self.brilliant = brilliant
        self.great = great
        self.inaccuracy = inaccuracy
        self.mistake = mistake
        self.blunder = blunder
    }

    init(settings: AppSettings) {
        self.init(
            brilliant: settings.moveAssessmentBrilliantColor.color,
            great: settings.moveAssessmentGreatColor.color,
            inaccuracy: settings.moveAssessmentInaccuracyColor.color,
            mistake: settings.moveAssessmentMistakeColor.color,
            blunder: settings.moveAssessmentBlunderColor.color
        )
    }

    static let defaults = MoveAssessmentColors(
        brilliant: Color(red: 0.0, green: 0.72, blue: 0.95),
        great: Color(red: 0.2, green: 0.75, blue: 0.45),
        inaccuracy: Color(red: 0.95, green: 0.78, blue: 0.2),
        mistake: Color(red: 0.95, green: 0.45, blue: 0.2),
        blunder: Color(red: 0.9, green: 0.2, blue: 0.2)
    )
}
