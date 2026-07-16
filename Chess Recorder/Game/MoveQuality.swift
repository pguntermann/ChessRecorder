//
//  MoveQuality.swift
//  Chess Recorder
//

import LucidEngine
import SwiftUI

enum MoveQuality: String, Equatable, Sendable, CaseIterable {
    case blunder
    case mistake
    case inaccuracy
    case miss
    case book
    case good

    init(_ classification: MoveClassification) {
        switch classification {
        case .blunder: self = .blunder
        case .mistake: self = .mistake
        case .inaccuracy: self = .inaccuracy
        case .book: self = .book
        case .good, .great, .brilliant: self = .good
        }
    }

    /// Classic PGN assessment suffix (e.g. `?!`, `??`). Misses have no NAG/symbol.
    var annotationSymbol: String {
        switch self {
        case .good, .book, .miss: return ""
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

    /// Restores qualities from persisted session data, including legacy great/brilliant values.
    init?(persistedRawValue: String) {
        switch persistedRawValue {
        case "great", "brilliant":
            self = .good
        default:
            guard let value = MoveQuality(rawValue: persistedRawValue) else { return nil }
            self = value
        }
    }
}

extension MoveQuality: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "great", "brilliant":
            // Legacy values from earlier builds; treat as undecorated good moves.
            self = .good
        case let value where MoveQuality(rawValue: value) != nil:
            self = MoveQuality(rawValue: value)!
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown MoveQuality: \(raw)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct MoveAssessmentColors: Equatable {
    let inaccuracy: Color
    let mistake: Color
    let blunder: Color
    let miss: Color

    func underlineColor(for quality: MoveQuality) -> Color {
        switch quality {
        case .inaccuracy: return inaccuracy
        case .mistake: return mistake
        case .blunder: return blunder
        case .miss: return miss
        case .good, .book: return .primary
        }
    }

    init(
        inaccuracy: Color,
        mistake: Color,
        blunder: Color,
        miss: Color
    ) {
        self.inaccuracy = inaccuracy
        self.mistake = mistake
        self.blunder = blunder
        self.miss = miss
    }

    init(settings: AppSettings) {
        self.init(
            inaccuracy: settings.moveAssessmentInaccuracyColor.color,
            mistake: settings.moveAssessmentMistakeColor.color,
            blunder: settings.moveAssessmentBlunderColor.color,
            miss: settings.moveAssessmentMissColor.color
        )
    }

    static let defaults = MoveAssessmentColors(
        inaccuracy: Color(red: 0.95, green: 0.78, blue: 0.2),
        mistake: Color(red: 0.95, green: 0.45, blue: 0.2),
        blunder: Color(red: 0.9, green: 0.2, blue: 0.2),
        miss: Color(red: 1.0, green: 0.45, blue: 0.75)
    )
}
