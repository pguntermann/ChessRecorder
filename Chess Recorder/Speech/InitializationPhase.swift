//
//  InitializationPhase.swift
//  Chess Recorder
//

import Foundation

enum InitializationContext: Equatable {
    case startup
    case speechModelRebuild

    var steps: [InitializationPhase] {
        switch self {
        case .startup:
            return InitializationPhase.orderedSteps
        case .speechModelRebuild:
            return [
                .preparingSpeechVocabulary,
                .buildingTrainingData,
                .exportingTrainingData,
                .compilingSpeechModel
            ]
        }
    }

    var totalSteps: Int { steps.count }
}

enum InitializationPhase: Equatable, CaseIterable {
    case requestingPermissions
    case preparingSpeechVocabulary
    case buildingTrainingData
    case exportingTrainingData
    case compilingSpeechModel
    case preparingEngine
    case loadingOpenings

    static let orderedSteps: [InitializationPhase] = [
        .requestingPermissions,
        .preparingSpeechVocabulary,
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
        case .preparingSpeechVocabulary:
            return "Preparing speech vocabulary"
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
        case .preparingSpeechVocabulary:
            return "Setting up built-in chess phrases, speech recognition, and any phrases you taught."
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

    func isComplete(relativeTo current: InitializationPhase, in context: InitializationContext) -> Bool {
        let steps = context.steps
        guard let currentIndex = steps.firstIndex(of: current),
              let selfIndex = steps.firstIndex(of: self) else {
            return false
        }
        return selfIndex < currentIndex
    }

    func stepNumber(in context: InitializationContext) -> Int {
        (context.steps.firstIndex(of: self) ?? 0) + 1
    }
}

struct PendingSpeechModelWork: Equatable {
    enum Action: Equatable {
        case changeLanguage(RecognitionLanguage)
        case reloadVocabulary(RecognitionLanguage)
    }

    private(set) var action: Action?

    var needsWork: Bool { action != nil }

    mutating func requestLanguageChange(_ language: RecognitionLanguage) {
        action = .changeLanguage(language)
    }

    mutating func requestVocabularyReload(for language: RecognitionLanguage) {
        if case .changeLanguage = action { return }
        action = .reloadVocabulary(language)
    }

    mutating func clear() {
        action = nil
    }
}
