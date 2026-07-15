//
//  ChessLanguageModel.swift
//  Chess Recorder
//
//  Domain-specific on-device speech language model (iOS 17+).
//  See: https://developer.apple.com/videos/play/wwdc2023/10101/
//

import CryptoKit
import Foundation
import Speech

enum ChessLanguageModel {
    
    private static let baseModelVersion = "4.0"
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
            await reportStatus("Using prepared speech model \(baseModelVersion) from the last launch.", onStatusChange: onStatusChange)
            return existing
        }
        
        if let task = preparationTasks[language] {
            await reportStatus("Waiting for speech model preparation to finish…", onStatusChange: onStatusChange)
            return await task.value
        }

        if let restored = await restorePersistedConfigurationIfAvailable(
            for: language,
            revision: revision,
            onStatusChange: onStatusChange
        ) {
            registerPreparedConfiguration(restored, for: language, revision: revision)
            return restored
        }

        logDiskRestore("not used for \(language.rawValue); performing full compile")

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
        
        PreparedLanguageModelDiskCache.removeArtifacts(for: language, in: storageDirectory())
    }
    
    // MARK: - Build
    
    private static func restorePersistedConfigurationIfAvailable(
        for language: RecognitionLanguage,
        revision: Int,
        onStatusChange: (@MainActor (String) -> Void)?
    ) async -> SFSpeechLanguageModel.Configuration? {
        let directory = storageDirectory()
        let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: language, in: directory)
        let exportURL = PreparedLanguageModelDiskCache.exportURL(for: language, in: directory)

        logDiskRestore(
            "checking \(language.rawValue) (model \(baseModelVersion), vocab revision \(revision))"
        )
        if let artifactNames = PreparedLanguageModelDiskCache.artifactBundleRelativePaths(
            for: language,
            in: directory
        ) {
            logDiskRestore("artifact bundle: \(artifactNames.joined(separator: ", "))")
        }

        if let reason = PreparedLanguageModelDiskCache.restoreSkipReason(
            for: language,
            baseModelVersion: baseModelVersion,
            vocabRevision: revision,
            preparedURL: preparedURL,
            exportURL: exportURL,
            in: directory
        ) {
            logDiskRestore("failed for \(language.rawValue): \(reason)")
            if PreparedLanguageModelDiskCache.shouldPurgeArtifactsAfterRestoreSkip(reason) {
                PreparedLanguageModelDiskCache.removeArtifacts(for: language, in: directory)
            }
            return nil
        }

        guard let resolvedPreparedURL = PreparedLanguageModelDiskCache.resolvedPreparedModelURL(
            for: language,
            in: directory
        ) else {
            logDiskRestore("failed for \(language.rawValue): compiled model path could not be resolved")
            return nil
        }

        await reportStatus(
            "Restoring compiled speech model \(baseModelVersion) from disk…",
            onStatusChange: onStatusChange
        )

        let config = SFSpeechLanguageModel.Configuration(languageModel: resolvedPreparedURL)
        logDiskRestore(
            "succeeded for \(language.rawValue) from \(resolvedPreparedURL.lastPathComponent) " +
            "(model \(baseModelVersion), vocab revision \(revision))"
        )
        return config
    }

    private static func logDiskRestore(_ message: String) {
        print("ChessLanguageModel: disk restore — \(message)")
    }

    private static func registerPreparedConfiguration(
        _ config: SFSpeechLanguageModel.Configuration,
        for language: RecognitionLanguage,
        revision: Int
    ) {
        preparedConfigurations[language] = config
        lastPreparedRevision[language] = revision
        lastPreparedBaseVersion[language] = baseModelVersion
    }

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

        let directory = storageDirectory()
        
        do {
            let locale = Locale(identifier: language.speechLocaleIdentifier)
            let exportURL = PreparedLanguageModelDiskCache.exportURL(for: language, in: directory)
            let preparedURL = PreparedLanguageModelDiskCache.preparedModelURL(for: language, in: directory)

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
            PreparedLanguageModelDiskCache.removePreparedModelOnly(for: language, in: directory)
            try await data.export(to: exportURL)
            print("ChessLanguageModel: exported training data to \(exportURL.lastPathComponent)")
            
            let config = SFSpeechLanguageModel.Configuration(languageModel: preparedURL)

            await reportPhase(.compilingSpeechModel, onPhaseChange: onPhaseChange)
            await reportStatus("Compiling on-device speech model… Can take up to a minute on first launch.", onStatusChange: onStatusChange)
            try await prepareCompiledModel(
                exportURL: exportURL,
                configuration: config,
                ignoresCache: true
            )

            guard PreparedLanguageModelDiskCache.preparedArtifactsExist(for: language, in: directory) else {
                throw PreparationError.compiledModelMissing(at: preparedURL)
            }

            guard let resolvedPreparedURL = PreparedLanguageModelDiskCache.resolvedPreparedModelURL(
                for: language,
                in: directory
            ), let bundleFingerprint = PreparedLanguageModelDiskCache.artifactBundleFingerprint(
                for: language,
                in: directory
            ) else {
                throw PreparationError.compiledModelMissing(at: preparedURL)
            }

            do {
                try PreparedLanguageModelDiskCache.saveManifest(
                    PreparedLanguageModelDiskCache.Manifest(
                        baseModelVersion: baseModelVersion,
                        vocabRevision: revision,
                        languageCode: language.rawValue,
                        artifactBundleByteCount: bundleFingerprint.byteCount,
                        artifactBundleSHA256: bundleFingerprint.sha256,
                        preparedModelRelativePath: resolvedPreparedURL.lastPathComponent,
                        preparedModelByteCount: nil,
                        preparedModelSHA256: nil
                    ),
                    for: language,
                    in: directory
                )
            } catch {
                print("ChessLanguageModel: failed to write manifest — \(error.localizedDescription)")
            }
            
            registerPreparedConfiguration(config, for: language, revision: revision)
            print("ChessLanguageModel: ready for \(language.rawValue) (model \(baseModelVersion), vocab revision \(revision), \(personalPhrases.count) seeded phrases)")
            return config
        } catch {
            PreparedLanguageModelDiskCache.removeArtifacts(for: language, in: directory)
            print("ChessLanguageModel: preparation failed — \(error.localizedDescription)")
            return nil
        }
    }
    
    private enum PreparationError: LocalizedError {
        case compiledModelMissing(at: URL)

        var errorDescription: String? {
            switch self {
            case .compiledModelMissing(let url):
                return "Compiled speech model was not written to \(url.lastPathComponent)"
            }
        }
    }

    private static func prepareCompiledModel(
        exportURL: URL,
        configuration: SFSpeechLanguageModel.Configuration,
        ignoresCache: Bool
    ) async throws {
        try await SFSpeechLanguageModel.prepareCustomLanguageModel(
            for: exportURL,
            configuration: configuration,
            ignoresCache: ignoresCache
        )
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
                           "kleine rochade", "große rochade", "grosse rochade", "lange rochade",
                           "lang rochade", "rochade auf damenseite", "rochade auf königsseite"] {
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
                    "<piece> <file> <square>",
                    count: 4500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <rank> <square>",
                    count: 4500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> von <file> auf <square>",
                    count: 4000
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
                    "<square> <square>",
                    count: 3500
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

            for phrase in [
                "castle", "castle kingside", "castle queenside",
                "castle on kingside", "castle on queenside",
                "castling kingside", "castling queenside"
            ] {
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
                    "<piece> <file> <square>",
                    count: 4500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> <rank> <square>",
                    count: 4500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<piece> from <file> to <square>",
                    count: 4000
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
                    "<square> <square>",
                    count: 3500
                )
                SFCustomLanguageModelData.TemplatePhraseCountGenerator.Template(
                    "<square> to <square>",
                    count: 3500
                )
            }
        }
    }
    
    private static func storageDirectory() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "ChessLanguageModel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        PreparedLanguageModelDiskCache.excludeFromBackup(url: directory)
        return directory
    }
}

enum PreparedLanguageModelDiskCache {
    struct Manifest: Codable, Equatable {
        let baseModelVersion: String
        let vocabRevision: Int
        let languageCode: String
        let artifactBundleByteCount: Int64?
        let artifactBundleSHA256: String?
        let preparedModelRelativePath: String?
        // Legacy fields from earlier cache versions; ignored once bundle fingerprints exist.
        let preparedModelByteCount: Int64?
        let preparedModelSHA256: String?
    }

    /// Real compiled models are much larger; truncated corruption tests fail fast here.
    static let minimumPreparedModelByteCount: Int64 = 4096

    static func exportURL(for language: RecognitionLanguage, in directory: URL) -> URL {
        directory.appending(path: "\(language.rawValue)-export.bin")
    }

    static func preparedModelURL(for language: RecognitionLanguage, in directory: URL) -> URL {
        directory.appendingPathComponent("\(language.rawValue)-prepared")
    }

    static func manifestURL(for language: RecognitionLanguage, in directory: URL) -> URL {
        directory.appendingPathComponent("\(language.rawValue)-manifest.json")
    }

    static func canRestore(
        for language: RecognitionLanguage,
        baseModelVersion: String,
        vocabRevision: Int,
        preparedURL: URL,
        exportURL: URL,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        restoreSkipReason(
            for: language,
            baseModelVersion: baseModelVersion,
            vocabRevision: vocabRevision,
            preparedURL: preparedURL,
            exportURL: exportURL,
            in: directory,
            fileManager: fileManager
        ) == nil
    }

    static func restoreSkipReason(
        for language: RecognitionLanguage,
        baseModelVersion: String,
        vocabRevision: Int,
        preparedURL: URL,
        exportURL: URL,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard let manifest = loadManifest(for: language, in: directory, fileManager: fileManager) else {
            return "manifest missing (app data may have been reset by an Xcode install)"
        }
        if manifest.languageCode != language.rawValue {
            return "language mismatch (manifest \(manifest.languageCode), expected \(language.rawValue))"
        }
        if manifest.baseModelVersion != baseModelVersion {
            return "model version mismatch (manifest \(manifest.baseModelVersion), expected \(baseModelVersion))"
        }
        if manifest.vocabRevision != vocabRevision {
            return "vocab revision mismatch (manifest \(manifest.vocabRevision), expected \(vocabRevision))"
        }
        if !fileManager.fileExists(atPath: exportURL.path) {
            return "training export missing at \(exportURL.lastPathComponent)"
        }
        guard let resolvedPreparedURL = resolvedPreparedModelURL(
            for: language,
            in: directory,
            fileManager: fileManager
        ) else {
            return "compiled model missing at \(preparedURL.lastPathComponent)"
        }
        if let integrityIssue = preparedModelIntegrityIssue(at: resolvedPreparedURL, fileManager: fileManager) {
            return integrityIssue
        }
        if let expectedPath = manifest.preparedModelRelativePath,
           resolvedPreparedURL.lastPathComponent != expectedPath {
            return "compiled model path mismatch (manifest \(expectedPath), found \(resolvedPreparedURL.lastPathComponent))"
        }
        guard let expectedBundleByteCount = manifest.artifactBundleByteCount,
              let expectedBundleSHA256 = manifest.artifactBundleSHA256 else {
            return "manifest missing artifact bundle fingerprint (recompile required)"
        }
        guard let bundleFingerprint = artifactBundleFingerprint(
            for: language,
            in: directory,
            fileManager: fileManager
        ) else {
            return "artifact bundle missing or unreadable"
        }
        if bundleFingerprint.byteCount != expectedBundleByteCount {
            return "artifact bundle appears corrupt (size \(bundleFingerprint.byteCount), expected \(expectedBundleByteCount))"
        }
        if bundleFingerprint.sha256 != expectedBundleSHA256 {
            return "artifact bundle appears corrupt (digest mismatch)"
        }
        return nil
    }

    static func artifactBundleRelativePaths(
        for language: RecognitionLanguage,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> [String]? {
        guard let items = artifactBundleItems(for: language, in: directory, fileManager: fileManager) else {
            return nil
        }
        return items.map(\.relativePath)
    }

    static func artifactBundleFingerprint(
        for language: RecognitionLanguage,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> (byteCount: Int64, sha256: String)? {
        guard let items = artifactBundleItems(for: language, in: directory, fileManager: fileManager),
              !items.isEmpty else {
            return nil
        }

        var totalBytes: Int64 = 0
        var hasher = SHA256()
        for item in items {
            guard appendArtifactToHasher(
                &hasher,
                totalBytes: &totalBytes,
                relativePath: item.relativePath,
                url: item.url,
                fileManager: fileManager
            ) else {
                return nil
            }
        }
        return (totalBytes, hasher.finalize().hexString)
    }

    private struct ArtifactBundleItem {
        let relativePath: String
        let url: URL
    }

    private static func artifactBundleItems(
        for language: RecognitionLanguage,
        in directory: URL,
        fileManager: FileManager
    ) -> [ArtifactBundleItem]? {
        let export = exportURL(for: language, in: directory)
        guard fileManager.fileExists(atPath: export.path) else {
            return nil
        }

        let preparedPrefix = preparedModelURL(for: language, in: directory).lastPathComponent
        let manifestName = manifestURL(for: language, in: directory).lastPathComponent
        var items = [ArtifactBundleItem(relativePath: export.lastPathComponent, url: export)]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return items
        }

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            if name == export.lastPathComponent || name == manifestName {
                continue
            }
            if matchesPreparedModelPath(name, prefix: preparedPrefix) {
                items.append(ArtifactBundleItem(relativePath: name, url: url))
            }
        }
        return items
    }

    private static func appendArtifactToHasher(
        _ hasher: inout SHA256,
        totalBytes: inout Int64,
        relativePath: String,
        url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        if isDirectory.boolValue {
            guard let files = regularFilesRecursively(at: url, fileManager: fileManager), !files.isEmpty else {
                return false
            }
            for file in files.sorted(by: { $0.path < $1.path }) {
                guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else {
                    return false
                }
                let rootPath = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
                let nestedRelativePath = file.path.hasPrefix(rootPath + "/")
                    ? String(file.path.dropFirst(rootPath.count + 1))
                    : file.lastPathComponent
                let fingerprintPath = "\(relativePath)/\(nestedRelativePath)"
                hasher.update(data: Data(fingerprintPath.utf8))
                hasher.update(data: data)
                totalBytes += Int64(data.count)
            }
            return true
        }

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return false
        }
        hasher.update(data: Data(relativePath.utf8))
        hasher.update(data: data)
        totalBytes += Int64(data.count)
        return true
    }

    static func shouldPurgeArtifactsAfterRestoreSkip(_ reason: String) -> Bool {
        reason.contains("corrupt")
            || reason.contains("digest")
            || reason.contains("fingerprint")
            || reason.contains("verification")
            || reason.contains("path mismatch")
    }

    static func preparedModelFingerprint(
        at url: URL,
        fileManager: FileManager = .default
    ) -> (byteCount: Int64, sha256: String)? {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            guard let files = regularFilesRecursively(at: url, fileManager: fileManager), !files.isEmpty else {
                return nil
            }

            var totalBytes: Int64 = 0
            var hasher = SHA256()
            for file in files.sorted(by: { $0.path < $1.path }) {
                guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else {
                    return nil
                }
                totalBytes += Int64(data.count)
                hasher.update(data: Data(file.path.utf8))
                hasher.update(data: data)
            }
            return (totalBytes, hasher.finalize().hexString)
        }

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return (Int64(data.count), SHA256.hash(data: data).hexString)
    }

    private static func regularFilesRecursively(
        at directory: URL,
        fileManager: FileManager
    ) -> [URL]? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            files.append(file)
        }
        return files
    }

    static func preparedModelIntegrityIssue(
        at url: URL,
        fileManager: FileManager = .default
    ) -> String? {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "compiled model missing at \(url.lastPathComponent)"
        }

        if isDirectory.boolValue {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey]
            ), !contents.isEmpty else {
                return "compiled model appears corrupt (empty directory at \(url.lastPathComponent))"
            }
            var archiveCount = 0
            for child in contents {
                guard let handle = try? FileHandle(forReadingFrom: child),
                      let header = try? handle.read(upToCount: 2), header.count == 2 else {
                    continue
                }
                try? handle.close()
                guard header.starts(with: [0x50, 0x4B]) else { continue }
                archiveCount += 1
                if let zipIssue = zipArchiveIntegrityIssue(at: child) {
                    return zipIssue
                }
            }
            let totalSize = contents.reduce(Int64(0)) { partial, child in
                partial + Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            if totalSize < minimumPreparedModelByteCount {
                return "compiled model appears corrupt (\(totalSize) bytes total in \(url.lastPathComponent))"
            }
            if archiveCount == 0 {
                return "compiled model appears corrupt (no archive files in \(url.lastPathComponent))"
            }
            return nil
        }

        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if size < minimumPreparedModelByteCount {
            return "compiled model appears corrupt (\(size) bytes in \(url.lastPathComponent))"
        }
        if let zipIssue = zipArchiveIntegrityIssue(at: url) {
            return zipIssue
        }
        return nil
    }

    static func zipArchiveIntegrityIssue(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "compiled model appears corrupt (unreadable archive at \(url.lastPathComponent))"
        }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 4), header.count == 4 else {
            return "compiled model appears corrupt (empty archive at \(url.lastPathComponent))"
        }
        guard header.starts(with: [0x50, 0x4B]) else {
            return "compiled model appears corrupt (invalid archive header at \(url.lastPathComponent))"
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > 0 else {
            return "compiled model appears corrupt (empty archive at \(url.lastPathComponent))"
        }

        let searchWindow = min(fileSize, 1024)
        try? handle.seek(toOffset: UInt64(fileSize - searchWindow))
        guard let tail = try? handle.readToEnd(), !tail.isEmpty else {
            return "compiled model appears corrupt (truncated ZIP archive at \(url.lastPathComponent))"
        }

        if !containsZipEndOfCentralDirectorySignature(in: tail) {
            return "compiled model appears corrupt (truncated ZIP archive at \(url.lastPathComponent))"
        }
        return nil
    }

    private static func containsZipEndOfCentralDirectorySignature(in data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let signature = Data([0x50, 0x4B, 0x05, 0x06])
        for index in stride(from: data.count - 4, through: 0, by: -1) {
            if data[index..<(index + 4)] == signature {
                return true
            }
        }
        return false
    }

    static func resolvedPreparedModelURL(
        for language: RecognitionLanguage,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let preparedURL = preparedModelURL(for: language, in: directory)
        if artifactExists(at: preparedURL, fileManager: fileManager) {
            return preparedURL
        }

        let prefix = preparedURL.lastPathComponent
        guard let siblings = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return siblings
            .filter { $0.lastPathComponent.hasPrefix(prefix) && artifactExists(at: $0, fileManager: fileManager) }
            .sorted { lhs, rhs in
                if lhs.lastPathComponent.count != rhs.lastPathComponent.count {
                    return lhs.lastPathComponent.count < rhs.lastPathComponent.count
                }
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
            .first
    }

    static func loadManifest(
        for language: RecognitionLanguage,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> Manifest? {
        let url = manifestURL(for: language, in: directory)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func saveManifest(
        _ manifest: Manifest,
        for language: RecognitionLanguage,
        in directory: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(for: language, in: directory), options: .atomic)
    }

    static func preparedArtifactsExist(at preparedURL: URL, fileManager: FileManager = .default) -> Bool {
        if artifactExists(at: preparedURL, fileManager: fileManager) {
            return true
        }

        let directory = preparedURL.deletingLastPathComponent()
        let prefix = preparedURL.lastPathComponent
        guard let siblings = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return siblings.contains { url in
            url.lastPathComponent.hasPrefix(prefix) && artifactExists(at: url, fileManager: fileManager)
        }
    }

    static func preparedArtifactsExist(
        for language: RecognitionLanguage,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        resolvedPreparedModelURL(for: language, in: directory, fileManager: fileManager) != nil
    }

    private static func artifactExists(at url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        if !isDirectory.boolValue {
            return true
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return !contents.isEmpty
    }

    static func removePreparedModelOnly(for language: RecognitionLanguage, in directory: URL, fileManager: FileManager = .default) {
        removePreparedModelFiles(for: language, in: directory, fileManager: fileManager)
    }

    static func removeArtifacts(for language: RecognitionLanguage, in directory: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: exportURL(for: language, in: directory))
        removePreparedModelFiles(for: language, in: directory, fileManager: fileManager)
        try? fileManager.removeItem(at: manifestURL(for: language, in: directory))
    }

    private static func removePreparedModelFiles(
        for language: RecognitionLanguage,
        in directory: URL,
        fileManager: FileManager = .default
    ) {
        let preparedURL = preparedModelURL(for: language, in: directory)
        let prefix = preparedURL.lastPathComponent
        if let siblings = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for url in siblings where matchesPreparedModelPath(url.lastPathComponent, prefix: prefix) {
                try? fileManager.removeItem(at: url)
            }
        }
        try? fileManager.removeItem(at: preparedURL)
    }

    private static func matchesPreparedModelPath(_ name: String, prefix: String) -> Bool {
        name == prefix || name.hasPrefix("\(prefix).")
    }

    static func excludeFromBackup(url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var resourceURL = url
        try? resourceURL.setResourceValues(values)
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
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
