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
    
    private static let baseModelVersion = "3.9"
    private static let modelIdentifier = "ChessRecorder.chess-moves"
    
    private static var preparedConfigurations: [RecognitionLanguage: SFSpeechLanguageModel.Configuration] = [:]
    private static var preparationTasks: [RecognitionLanguage: Task<SFSpeechLanguageModel.Configuration?, Never>] = [:]
    private static var lastPreparedRevision: [RecognitionLanguage: Int] = [:]
    private static var lastPreparedBaseVersion: [RecognitionLanguage: String] = [:]
    
    static func prepare(
        for language: RecognitionLanguage,
        vocabulary: PersonalVocabularyStore,
        onPhaseChange: (@MainActor (InitializationPhase) -> Void)? = nil,
        onStatusChange: (@MainActor (String) -> Void)? = nil
    ) async -> SFSpeechLanguageModel.Configuration? {
        let revision = vocabulary.revision(for: language)
        if let existing = preparedConfigurations[language],
           lastPreparedRevision[language] == revision,
           lastPreparedBaseVersion[language] == baseModelVersion {
            await reportStatus("Using prepared speech model from the last launch.", onStatusChange: onStatusChange)
            return existing
        }
        
        if let task = preparationTasks[language] {
            await reportStatus("Waiting for speech model preparation to finish…", onStatusChange: onStatusChange)
            return await task.value
        }

        await reportPhase(.preparingSpeechVocabulary, onPhaseChange: onPhaseChange)
        await reportStatus("Collecting phrases for on-device recognition…", onStatusChange: onStatusChange)
        let personalPhrases = vocabulary.speechPhraseCounts(for: language)
        await reportStatus(
            "Loaded \(personalPhrases.count) phrase\(personalPhrases.count == 1 ? "" : "s") for speech recognition.",
            onStatusChange: onStatusChange
        )

        let task = Task.detached(priority: .userInitiated) {
            await buildAndPrepare(
                for: language,
                revision: revision,
                personalPhrases: personalPhrases,
                onPhaseChange: onPhaseChange,
                onStatusChange: onStatusChange
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
        revision: Int,
        personalPhrases: [(phrase: String, count: Int)],
        onPhaseChange: (@MainActor (InitializationPhase) -> Void)?,
        onStatusChange: (@MainActor (String) -> Void)?
    ) async -> SFSpeechLanguageModel.Configuration? {
        await reportStatus("Verifying on-device speech recognition…", onStatusChange: onStatusChange)
        guard SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))?.supportsOnDeviceRecognition == true else {
            print("ChessLanguageModel: on-device recognition unavailable for \(language.rawValue)")
            await reportStatus("On-device speech recognition is unavailable on this device.", onStatusChange: onStatusChange)
            return nil
        }
        
        do {
            let locale = Locale(identifier: language.speechLocaleIdentifier)
            let exportURL = modelExportURL(for: language)
            let preparedURL = modelPreparedURL(for: language)

            await reportPhase(.buildingTrainingData, onPhaseChange: onPhaseChange)
            await reportStatus("Assembling chess phrases, squares, and piece names… Usually a few seconds.", onStatusChange: onStatusChange)
            let data = buildTrainingData(
                for: language,
                locale: locale,
                personalPhrases: personalPhrases,
                revision: revision
            )

            await reportPhase(.exportingTrainingData, onPhaseChange: onPhaseChange)
            await reportStatus("Writing speech training data to disk…", onStatusChange: onStatusChange)
            try await data.export(to: exportURL)
            print("ChessLanguageModel: exported training data to \(exportURL.lastPathComponent)")
            
            let config = SFSpeechLanguageModel.Configuration(languageModel: preparedURL)

            await reportPhase(.compilingSpeechModel, onPhaseChange: onPhaseChange)
            await reportStatus("Compiling on-device speech model… Can take up to a minute on first launch.", onStatusChange: onStatusChange)
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

    private static func reportStatus(
        _ detail: String,
        onStatusChange: (@MainActor (String) -> Void)?
    ) async {
        guard let onStatusChange else { return }
        await MainActor.run {
            onStatusChange(detail)
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
        let lexicon = ChessSpeechLexicon.lexicon(for: .german)
        let files = ChessSpeechLexicon.files
        let ranks = ChessSpeechLexicon.digitRanks
        let squares = files.flatMap { file in ranks.map { file + $0 } }
        
        return SFCustomLanguageModelData(
            locale: locale,
            identifier: modelIdentifier,
            version: "\(baseModelVersion)-\(revision)"
        ) {
            for (phrase, count) in personalPhrases {
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: count)
            }

            for phrase in ["zurück", "rückgängig", "kurz rochiert", "lang rochiert",
                           "kleine rochade", "große rochade", "grosse rochade", "lange rochade"] {
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: 220)
            }
            
            SFCustomLanguageModelData.PhraseCountsFromTemplates(
                classes: [
                    "file": files,
                    "rank": ranks,
                    "square": squares,
                    "piece": lexicon.pieces,
                    "verb": lexicon.clmCaptureVerbs,
                    "spokenRank": lexicon.spokenRanks
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
                    "<piece> <verb> <file> <spokenRank>",
                    count: 7000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <verb> <file> <rank>",
                    count: 5000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <square>",
                    count: 7000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> auf <square>",
                    count: 5500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <file> auf <square>",
                    count: 4500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<file> <spokenRank>",
                    count: 2000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<square>",
                    count: 4000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<square> nach <square>",
                    count: 3500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<square> auf <square>",
                    count: 3500
                )
            }
        }
    }
    
    private static func buildEnglishData(
        locale: Locale,
        personalPhrases: [(phrase: String, count: Int)],
        revision: Int
    ) -> SFCustomLanguageModelData {
        let lexicon = ChessSpeechLexicon.lexicon(for: .english)
        let files = ChessSpeechLexicon.files
        let ranks = ChessSpeechLexicon.digitRanks
        let squares = files.flatMap { file in ranks.map { file + $0 } }
        
        return SFCustomLanguageModelData(
            locale: locale,
            identifier: modelIdentifier,
            version: "\(baseModelVersion)-\(revision)"
        ) {
            for (phrase, count) in personalPhrases {
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: count)
            }

            for phrase in ["castle", "castle kingside", "castle queenside"] {
                SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: 240)
            }
            
            SFCustomLanguageModelData.PhraseCountsFromTemplates(
                classes: [
                    "file": files,
                    "rank": ranks,
                    "square": squares,
                    "piece": lexicon.pieces,
                    "verb": lexicon.clmCaptureVerbs,
                    "spokenRank": lexicon.spokenRanks
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
                    "<piece> <verb> <file> <spokenRank>",
                    count: 7000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <verb> <file> <rank>",
                    count: 5000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <square>",
                    count: 7000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> to <square>",
                    count: 5500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <file> to <square>",
                    count: 4500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<file> <spokenRank>",
                    count: 2000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<square>",
                    count: 4000
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<square> to <square>",
                    count: 3500
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
