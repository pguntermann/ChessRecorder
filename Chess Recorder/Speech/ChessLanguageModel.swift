//
//  ChessLanguageModel.swift
//  Chess Recorder
//
//  Domain-specific on-device speech language model (iOS 17+).
//  See: https://developer.apple.com/videos/play/wwdc2023/10101/
//

import Foundation
import Speech

enum ChessLanguageModel {
    
    private static let baseModelVersion = "1.4"
    private static let modelIdentifier = "ChessRecorder.chess-moves"
    
    private static var preparedConfigurations: [RecognitionLanguage: SFSpeechLanguageModel.Configuration] = [:]
    private static var preparationTasks: [RecognitionLanguage: Task<SFSpeechLanguageModel.Configuration?, Never>] = [:]
    private static var lastPreparedRevision: [RecognitionLanguage: Int] = [:]
    private static var lastPreparedBaseVersion: [RecognitionLanguage: String] = [:]
    
    static func prepare(
        for language: RecognitionLanguage,
        vocabulary: PersonalVocabularyStore,
        onPhaseChange: (@MainActor (InitializationPhase) -> Void)? = nil
    ) async -> SFSpeechLanguageModel.Configuration? {
        let revision = vocabulary.revision(for: language)
        if let existing = preparedConfigurations[language],
           lastPreparedRevision[language] == revision,
           lastPreparedBaseVersion[language] == baseModelVersion {
            return existing
        }
        
        if let task = preparationTasks[language] {
            return await task.value
        }
        
        let task = Task<SFSpeechLanguageModel.Configuration?, Never> {
            await buildAndPrepare(
                for: language,
                vocabulary: vocabulary,
                revision: revision,
                onPhaseChange: onPhaseChange
            )
        }
        preparationTasks[language] = task
        let result = await task.value
        preparationTasks[language] = nil
        return result
    }
    
    static func configuration(for language: RecognitionLanguage) -> SFSpeechLanguageModel.Configuration? {
        preparedConfigurations[language]
    }
    
    static func invalidate(for language: RecognitionLanguage) {
        preparedConfigurations.removeValue(forKey: language)
        lastPreparedRevision.removeValue(forKey: language)
        lastPreparedBaseVersion.removeValue(forKey: language)
        preparationTasks[language]?.cancel()
        preparationTasks.removeValue(forKey: language)
        
        let exportURL = modelExportURL(for: language)
        let preparedURL = modelPreparedURL(for: language)
        try? FileManager.default.removeItem(at: exportURL)
        try? FileManager.default.removeItem(at: preparedURL)
    }
    
    // MARK: - Build
    
    private static func buildAndPrepare(
        for language: RecognitionLanguage,
        vocabulary: PersonalVocabularyStore,
        revision: Int,
        onPhaseChange: (@MainActor (InitializationPhase) -> Void)?
    ) async -> SFSpeechLanguageModel.Configuration? {
        guard SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))?.supportsOnDeviceRecognition == true else {
            print("ChessLanguageModel: on-device recognition unavailable for \(language.rawValue)")
            return nil
        }
        
        do {
            let locale = Locale(identifier: language.speechLocaleIdentifier)
            let exportURL = modelExportURL(for: language)
            let preparedURL = modelPreparedURL(for: language)

            await reportPhase(.loadingPersonalVocabulary, onPhaseChange: onPhaseChange)
            let personalPhrases = vocabulary.speechPhraseCounts(for: language)

            await reportPhase(.buildingTrainingData, onPhaseChange: onPhaseChange)
            let data = buildTrainingData(
                for: language,
                locale: locale,
                personalPhrases: personalPhrases,
                revision: revision
            )

            await reportPhase(.exportingTrainingData, onPhaseChange: onPhaseChange)
            try await data.export(to: exportURL)
            print("ChessLanguageModel: exported training data to \(exportURL.lastPathComponent)")
            
            let config = SFSpeechLanguageModel.Configuration(languageModel: preparedURL)

            await reportPhase(.compilingSpeechModel, onPhaseChange: onPhaseChange)
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(
                for: exportURL,
                configuration: config
            )
            
            preparedConfigurations[language] = config
            lastPreparedRevision[language] = revision
            lastPreparedBaseVersion[language] = baseModelVersion
            print("ChessLanguageModel: ready for \(language.rawValue) (revision \(revision), \(personalPhrases.count) personal phrases)")
            return config
        } catch {
            print("ChessLanguageModel: preparation failed — \(error.localizedDescription)")
            return nil
        }
    }
    
    private static func reportPhase(
        _ phase: InitializationPhase,
        onPhaseChange: (@MainActor (InitializationPhase) -> Void)?
    ) async {
        guard let onPhaseChange else { return }
        await MainActor.run {
            onPhaseChange(phase)
        }
    }

    private static func buildTrainingData(
        for language: RecognitionLanguage,
        locale: Locale,
        personalPhrases: [(phrase: String, count: Int)],
        revision: Int
    ) -> SFCustomLanguageModelData {
        switch language {
        case .english:
            return buildEnglishData(locale: locale, personalPhrases: personalPhrases, revision: revision)
        case .german:
            return buildGermanData(locale: locale, personalPhrases: personalPhrases, revision: revision)
        }
    }
    
    private static func buildGermanData(
        locale: Locale,
        personalPhrases: [(phrase: String, count: Int)],
        revision: Int
    ) -> SFCustomLanguageModelData {
        let files = Array("abcdefgh").map(String.init)
        let ranks = (1...8).map(String.init)
        let squares = files.flatMap { file in ranks.map { file + $0 } }
        let pieces = ["springer", "läufer", "turm", "dame", "könig", "bauer"]
        let captureVerbs = ["schlägt", "schlagt", "nimmt"]
        let spokenRanks = ["eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht"]
        
        return SFCustomLanguageModelData(
            locale: locale,
            identifier: modelIdentifier,
            version: "\(baseModelVersion)-\(revision)"
        ) {
            for (phrase, count) in personalPhrases {
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: count)
            }
            
            for verb in captureVerbs {
                SFCustomLanguageModelData.PhraseCount(phrase: "e \(verb) d4", count: 500)
                SFCustomLanguageModelData.PhraseCount(phrase: "e \(verb) d vier", count: 200)
            }
            
            for square in ["e4", "d4", "e5", "d5", "c4", "f3", "f6", "c3", "c6", "g1", "e3", "e6", "e7"] {
                SFCustomLanguageModelData.PhraseCount(phrase: square, count: 300)
            }

            for rank in ["eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht"] {
                SFCustomLanguageModelData.PhraseCount(phrase: "e \(rank)", count: 280)
            }

            for word in spokenRanks {
                SFCustomLanguageModelData.PhraseCount(phrase: word, count: 150)
            }

            for phrase in ["zurück", "rückgängig", "kurz rochiert", "lang rochiert",
                           "kleine rochade", "große rochade", "grosse rochade", "lange rochade",
                           "springer g1 auf f3", "turm f auf d1", "turm f1 auf d1"] {
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: 100)
            }
            
            SFCustomLanguageModelData.PhraseCountsFromTemplates(
                classes: [
                    "file": files,
                    "rank": ranks,
                    "square": squares,
                    "piece": pieces,
                    "verb": captureVerbs,
                    "spokenRank": spokenRanks
                ]
            ) {
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<file> <verb> <square>",
                    count: 8000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <verb> <square>",
                    count: 8000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <square>",
                    count: 6000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <file> auf <square>",
                    count: 3000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<file> <spokenRank>",
                    count: 2000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<square>",
                    count: 4000
                )
            }
        }
    }
    
    private static func buildEnglishData(
        locale: Locale,
        personalPhrases: [(phrase: String, count: Int)],
        revision: Int
    ) -> SFCustomLanguageModelData {
        let files = Array("abcdefgh").map(String.init)
        let ranks = (1...8).map(String.init)
        let squares = files.flatMap { file in ranks.map { file + $0 } }
        let pieces = ["knight", "bishop", "rook", "queen", "king", "pawn"]
        let captureVerbs = ["takes", "take", "captures", "capture"]
        let spokenRanks = ["one", "two", "three", "four", "five", "six", "seven", "eight"]
        
        return SFCustomLanguageModelData(
            locale: locale,
            identifier: modelIdentifier,
            version: "\(baseModelVersion)-\(revision)"
        ) {
            for (phrase, count) in personalPhrases {
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: count)
            }

            for square in ["e4", "d4", "e5", "d5", "c4", "f3", "f6", "c3", "c6", "g1"] {
                SFCustomLanguageModelData.PhraseCount(phrase: square, count: 300)
            }

            for word in ["see", "sea", "bee", "dee", "gee", "aitch"] {
                SFCustomLanguageModelData.PhraseCount(phrase: word, count: 200)
            }

            for word in spokenRanks {
                SFCustomLanguageModelData.PhraseCount(phrase: word, count: 150)
            }

            for phrase in ["knight g1 to f3", "rook f to d1", "rook g1 to f3"] {
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: 100)
            }
            
            SFCustomLanguageModelData.PhraseCountsFromTemplates(
                classes: [
                    "file": files,
                    "rank": ranks,
                    "square": squares,
                    "piece": pieces,
                    "verb": captureVerbs,
                    "spokenRank": spokenRanks
                ]
            ) {
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<file> <verb> <square>",
                    count: 8000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <verb> <square>",
                    count: 8000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <square>",
                    count: 6000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <file> to <square>",
                    count: 2500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<file> <spokenRank>",
                    count: 2000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<square>",
                    count: 4000
                )
            }
        }
    }
    
    private static func modelExportURL(for language: RecognitionLanguage) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "ChessLanguageModel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(language.rawValue)-export.bin")
    }
    
    private static func modelPreparedURL(for language: RecognitionLanguage) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "ChessLanguageModel", directoryHint: .isDirectory)
        return directory.appendingPathComponent("\(language.rawValue)-prepared")
    }
}

private extension RecognitionLanguage {
    var speechLocaleIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .german: return "de_DE"
        }
    }
}
