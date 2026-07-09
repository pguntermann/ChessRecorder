//
//  InitializationPhase.swift
//  Chess Recorder
//

import Foundation

enum InitializationPhase: Equatable, CaseIterable {
    case requestingPermissions
    case loadingPersonalVocabulary
    case buildingTrainingData
    case exportingTrainingData
    case compilingSpeechModel
    case preparingEngine
    case loadingOpenings

    static let orderedSteps: [InitializationPhase] = [
        .requestingPermissions,
        .loadingPersonalVocabulary,
        .buildingTrainingData,
        .exportingTrainingData,
        .compilingSpeechModel,
        .preparingEngine,
        .loadingOpenings
    ]

    var title: String {
        switch self {
        case .requestingPermissions:
            return "Checking permissions"
        case .loadingPersonalVocabulary:
            return "Loading personal vocabulary"
        case .buildingTrainingData:
            return "Building chess vocabulary"
        case .exportingTrainingData:
            return "Saving vocabulary"
        case .compilingSpeechModel:
            return "Compiling speech model"
        case .preparingEngine:
            return "Starting analysis engine"
        case .loadingOpenings:
            return "Loading openings"
        }
    }

    var detail: String {
        switch self {
        case .requestingPermissions:
            return "Verifying microphone and speech recognition access."
        case .loadingPersonalVocabulary:
            return "Loading your taught phrases and corrections."
        case .buildingTrainingData:
            return "Assembling move phrases, squares, and piece names."
        case .exportingTrainingData:
            return "Writing training data for voice recognition."
        case .compilingSpeechModel:
            return "Building the on-device language model. This step can take up to a minute on first launch."
        case .preparingEngine:
            return "Loading Stockfish for optional position analysis."
        case .loadingOpenings:
            return "Preparing the opening name database."
        }
    }

    var stepNumber: Int {
        (Self.orderedSteps.firstIndex(of: self) ?? 0) + 1
    }

    static var totalSteps: Int { orderedSteps.count }

    func isComplete(relativeTo current: InitializationPhase) -> Bool {
        guard let currentIndex = Self.orderedSteps.firstIndex(of: current),
              let selfIndex = Self.orderedSteps.firstIndex(of: self) else {
            return false
        }
        return selfIndex < currentIndex
    }
}
