//
//  PersonalVocabularyStore.swift
//  Chess Recorder
//
//  User-taught speech phrases for custom language model boosting and move mapping.
//

import Foundation

enum LearnedPhraseSource: String, Codable {
    case user
    case builtIn
    case recognitionOnly
}

struct LearnedCorrection: Codable, Identifiable, Equatable {
    let id: UUID
    var heard: String
    var replacement: String
    var languageCode: String
    var updatedAt: Date

    var language: RecognitionLanguage? {
        RecognitionLanguage(rawValue: languageCode)
    }
}

struct LearnedPhrase: Codable, Identifiable, Equatable {
    let id: UUID
    var phrase: String
    var moveNotation: String
    var languageCode: String
    var count: Int
    var updatedAt: Date
    var source: LearnedPhraseSource
    
    var language: RecognitionLanguage? {
        RecognitionLanguage(rawValue: languageCode)
    }

    init(
        id: UUID,
        phrase: String,
        moveNotation: String,
        languageCode: String,
        count: Int,
        updatedAt: Date,
        source: LearnedPhraseSource = .user
    ) {
        self.id = id
        self.phrase = phrase
        self.moveNotation = moveNotation
        self.languageCode = languageCode
        self.count = count
        self.updatedAt = updatedAt
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id
        case phrase
        case moveNotation
        case languageCode
        case count
        case updatedAt
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        phrase = try container.decode(String.self, forKey: .phrase)
        moveNotation = try container.decode(String.self, forKey: .moveNotation)
        languageCode = try container.decode(String.self, forKey: .languageCode)
        count = try container.decode(Int.self, forKey: .count)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        source = try container.decodeIfPresent(LearnedPhraseSource.self, forKey: .source) ?? .user
    }
}

private struct PersonalVocabularyFile: Codable {
    var phrases: [LearnedPhrase]
    var corrections: [LearnedCorrection]
    var revisions: [String: Int]

    enum CodingKeys: String, CodingKey {
        case phrases
        case corrections
        case revisions
    }

    init(phrases: [LearnedPhrase], corrections: [LearnedCorrection], revisions: [String: Int]) {
        self.phrases = phrases
        self.corrections = corrections
        self.revisions = revisions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phrases = try container.decodeIfPresent([LearnedPhrase].self, forKey: .phrases) ?? []
        corrections = try container.decodeIfPresent([LearnedCorrection].self, forKey: .corrections) ?? []
        revisions = try container.decodeIfPresent([String: Int].self, forKey: .revisions) ?? [:]
    }
}

@Observable
final class PersonalVocabularyStore {
    private(set) var phrases: [LearnedPhrase] = []
    private(set) var corrections: [LearnedCorrection] = []
    private var revisions: [String: Int] = [:]
    private var phraseIndex: [String: Int] = [:]
    
    private let storageURL: URL
    
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appending(path: "personal-vocabulary.json")
        load()
    }
    
    func entries(for language: RecognitionLanguage) -> [LearnedPhrase] {
        phrases
            .filter { $0.languageCode == language.rawValue && $0.source == .user }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func correctionEntries(for language: RecognitionLanguage) -> [LearnedCorrection] {
        corrections
            .filter { $0.languageCode == language.rawValue }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func userMoveMappingEntries(for language: RecognitionLanguage) -> [LearnedPhrase] {
        phrases
            .filter { $0.languageCode == language.rawValue && $0.source == .user }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func revision(for language: RecognitionLanguage) -> Int {
        revisions[language.rawValue] ?? 0
    }

    @discardableResult
    func seedCommonPhrasesIfNeeded(
        for language: RecognitionLanguage,
        onProgress: (@MainActor (_ loaded: Int, _ total: Int) -> Void)? = nil
    ) async -> Int {
        let trainingItems = Self.commonTrainingPhrases(for: language)
        let recognitionItems = ChessSpeechTrainingPhrases.generatedRecognitionPhraseCounts(for: language)
        let total = trainingItems.count + recognitionItems.count
        let trainingDone = Self.trainingSeedUpToDate(for: language, in: phrases)
        let recognitionDone = Self.recognitionSeedUpToDate(for: language, in: phrases)

        if trainingDone && recognitionDone {
            if let onProgress {
                await MainActor.run {
                    onProgress(total, total)
                }
            }
            return 0
        }

        var changes = 0

        for retired in Self.retiredBuiltInMovePhrases(for: language) {
            let before = phrases.count
            phrases.removeAll {
                $0.source == .builtIn &&
                $0.languageCode == language.rawValue &&
                Self.normalizePhrase($0.phrase, language: language) == retired
            }
            if phrases.count != before { changes += 1 }
        }

        for retired in Self.retiredRecognitionPhrases(for: language) {
            let before = phrases.count
            phrases.removeAll {
                $0.source == .recognitionOnly &&
                $0.languageCode == language.rawValue &&
                Self.seedPhraseKey($0.phrase) == Self.seedPhraseKey(retired)
            }
            if phrases.count != before { changes += 1 }
        }

        if changes > 0 {
            rebuildPhraseIndex()
        }

        var loaded = 0
        if let onProgress {
            await MainActor.run {
                onProgress(0, total)
            }
            await Task.yield()
        }

        if !trainingDone {
            for item in trainingItems {
                let changed = upsert(
                    phrase: item.phrase,
                    moveNotation: item.moveNotation,
                    language: language,
                    minimumCount: item.count,
                    source: .builtIn
                )
                if changed { changes += 1 }
                loaded += 1
                if Self.shouldReportPhraseSeedProgress(loaded: loaded, total: total) {
                    await MainActor.run {
                        onProgress?(loaded, total)
                    }
                    await Task.yield()
                }
            }
        } else {
            loaded += trainingItems.count
        }

        if !recognitionDone {
            let recognitionChanges = batchUpsertRecognitionPhrases(recognitionItems, language: language)
            if recognitionChanges > 0 { changes += 1 }
            loaded += recognitionItems.count
            if let onProgress {
                await MainActor.run {
                    onProgress(loaded, total)
                }
            }
        } else {
            loaded += recognitionItems.count
        }

        if changes > 0 {
            bumpRevision(for: language)
            save()
        }

        if !trainingDone {
            UserDefaults.standard.set(Self.currentBundledTrainingSeedRevision, forKey: Self.bundledTrainingSeedRevisionKey)
        }
        if !recognitionDone {
            UserDefaults.standard.set(Self.currentBundledRecognitionSeedRevision, forKey: Self.bundledRecognitionSeedRevisionKey)
        }

        return changes
    }

    private static func shouldReportPhraseSeedProgress(loaded: Int, total: Int) -> Bool {
        loaded == total || loaded % 200 == 0
    }

    /// Fast lookup key for bulk recognition seeding (not used for move-phrase matching).
    private static func seedPhraseKey(_ phrase: String) -> String {
        phrase
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func batchUpsertRecognitionPhrases(
        _ items: [(phrase: String, count: Int)],
        language: RecognitionLanguage
    ) -> Int {
        var changes = 0

        for item in items {
            let trimmed = item.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = Self.seedPhraseKey(trimmed)
            let key = phraseIndexKey(
                language: language,
                source: .recognitionOnly,
                normalizedPhrase: normalized
            )
            let targetCount = min(max(item.count, 1), 1_000)

            if let index = phraseIndex[key] {
                var entry = phrases[index]
                let changed = entry.count != targetCount || entry.phrase != trimmed
                guard changed else { continue }
                entry.count = targetCount
                entry.phrase = trimmed
                entry.moveNotation = trimmed
                entry.updatedAt = Date()
                phrases[index] = entry
                changes += 1
                continue
            }

            let entry = LearnedPhrase(
                id: UUID(),
                phrase: trimmed,
                moveNotation: trimmed,
                languageCode: language.rawValue,
                count: targetCount,
                updatedAt: Date(),
                source: .recognitionOnly
            )
            phraseIndex[key] = phrases.count
            phrases.append(entry)
            changes += 1
        }

        return changes
    }
    
    @discardableResult
    func learn(phrase: String, moveNotation: String, language: RecognitionLanguage) -> LearnedPhrase {
        let entry = upsertEntry(
            phrase: phrase,
            moveNotation: moveNotation,
            language: language,
            minimumCount: 100,
            increment: 50
        )
        bumpRevision(for: language)
        save()
        return entry
    }

    @discardableResult
    func learnCorrection(heard: String, replacement: String, language: RecognitionLanguage) -> LearnedCorrection {
        let normalizedHeard = Self.normalizePhrase(heard, language: language)
        let trimmedHeard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)

        if let index = corrections.firstIndex(where: {
            $0.languageCode == language.rawValue &&
            Self.normalizePhrase($0.heard, language: language) == normalizedHeard
        }) {
            corrections[index].heard = trimmedHeard
            corrections[index].replacement = trimmedReplacement
            corrections[index].updatedAt = Date()
            bumpRevision(for: language)
            save()
            return corrections[index]
        }

        let entry = LearnedCorrection(
            id: UUID(),
            heard: trimmedHeard,
            replacement: trimmedReplacement,
            languageCode: language.rawValue,
            updatedAt: Date()
        )
        corrections.append(entry)
        bumpRevision(for: language)
        save()
        return entry
    }
    
    func remove(id: UUID) {
        if let index = phrases.firstIndex(where: { $0.id == id }),
           let language = phrases[index].language {
            phrases.remove(at: index)
            rebuildPhraseIndex()
            bumpRevision(for: language)
            save()
            return
        }

        guard let index = corrections.firstIndex(where: { $0.id == id }),
              let language = corrections[index].language else {
            return
        }
        corrections.remove(at: index)
        bumpRevision(for: language)
        save()
    }
    
    func reset(language: RecognitionLanguage) {
        phrases.removeAll { $0.languageCode == language.rawValue && $0.source == .user }
        corrections.removeAll { $0.languageCode == language.rawValue }
        corrections.append(contentsOf: Self.defaultCorrections(for: language))
        rebuildPhraseIndex()
        bumpRevision(for: language)
        save()
    }
    
    func resetAll() {
        phrases.removeAll()
        corrections = Self.bundledVocabulary()?.corrections ?? []
        revisions = Self.bundledVocabulary()?.revisions ?? [:]
        rebuildPhraseIndex()
        for language in RecognitionLanguage.allCases {
            bumpRevision(for: language)
        }
        save()
    }
    
    func speechPhraseCounts(for language: RecognitionLanguage) -> [(phrase: String, count: Int)] {
        phrases
            .filter { $0.languageCode == language.rawValue }
            .map { ($0.phrase, $0.count) }
    }
    
    /// Short hints for live dictation only (Apple limits contextualStrings to 100).
    func contextualStrings(for language: RecognitionLanguage) -> [String] {
        let user = phrases
            .filter { $0.languageCode == language.rawValue && $0.source == .user }
            .map(\.phrase)
        let builtIn = phrases
            .filter { $0.languageCode == language.rawValue && $0.source == .builtIn }
            .map(\.phrase)
        let corrections = correctionEntries(for: language).map(\.heard)
        return user + builtIn + corrections
    }
    
    /// Move candidates from user-taught phrase → move mappings (trailing phrase match).
    func candidateMoves(for text: String, language: RecognitionLanguage) -> [String] {
        let normalized = Self.normalizePhrase(text, language: language)
        let compact = Self.compactLearningKey(normalized, language: language)
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        // "hey 3" must disambiguate via legal moves — not a taught "hey 3" → a3 shortcut.
        if language == .english, ChessTranscriptNormalizer.isAmbiguousEnglishFileRankUtterance(words) {
            return []
        }
        
        var results: [String] = []
        var seen = Set<String>()
        var matches: [(notation: String, phraseWordCount: Int, count: Int)] = []

        let textContainsCaptureIntent = words.contains(where: { token in
            let lowered = token.lowercased()
            return [
                "takes", "take", "captures", "capture",
                "schlagt", "schlaegt", "schagt", "schaegt", "nimmt"
            ].contains(lowered)
        })

        for entry in userMoveMappingEntries(for: language) {
            let learnedPhrase = Self.normalizePhrase(entry.phrase, language: language)
            let learnedWords = learnedPhrase
                .split(separator: " ")
                .map(String.init)
            guard !learnedWords.isEmpty else { continue }

            // Avoid letting short or non-capture tail phrases like "d5" or
            // "d 5" override richer capture utterances such as "e4 takes d5".
            // In those cases the move parser should handle the full phrase
            // instead of the learned-phrase shortcut.
            if textContainsCaptureIntent, !Self.phraseLooksCaptureSpecific(learnedWords, language: language) {
                continue
            }
            
            let learned = learnedWords.joined(separator: " ")
            let learnedCompact = Self.compactLearningKey(learnedPhrase, language: language)
            let tail = words.count >= learnedWords.count
                ? words.suffix(learnedWords.count).joined(separator: " ")
                : ""

            let matchesExactTail = tail == learned
            let matchesCompact = !compact.isEmpty && !learnedCompact.isEmpty
                && (compact == learnedCompact || (
                    compact.hasSuffix(learnedCompact)
                    && !Self.compactSuffixBlockedByTrailingRank(
                        compact: compact,
                        learnedCompact: learnedCompact,
                        language: language
                    )
                ))

            guard (matchesExactTail || matchesCompact) else { continue }

            if matchesExactTail,
               learnedWords.count == 1,
               Self.isSpokenRankOnly(learnedWords[0], language: language),
               words.count >= 2 {
                let prefix = words[words.count - learnedWords.count - 1]
                if ChessTranscriptNormalizer.isAmbiguousEnglishFileToken(prefix)
                    || ChessTranscriptNormalizer.spokenFileLetter(for: prefix, language: language) != nil {
                    continue
                }
            }

            matches.append((entry.moveNotation, learnedWords.count, entry.count))
        }

        guard !matches.isEmpty else { return [] }

        let longestPhraseWordCount = matches.map(\.phraseWordCount).max() ?? 0
        for match in matches where match.phraseWordCount == longestPhraseWordCount {
            guard seen.insert(match.notation).inserted else { continue }
            results.append(match.notation)
        }
        
        return results.sorted { lhs, rhs in
            let lhsCount = matches.first { $0.notation == lhs }?.count ?? 0
            let rhsCount = matches.first { $0.notation == rhs }?.count ?? 0
            return lhsCount > rhsCount
        }
    }
    
    static func normalizePhrase(_ phrase: String, language: RecognitionLanguage) -> String {
        ChessTranscriptNormalizer.normalizeForPhraseMatching(phrase, language: language)
    }

    /// Reject compact matches like `nf3six` for learned `nf3` when trailing text is a conflicting rank.
    private static func compactSuffixBlockedByTrailingRank(
        compact: String,
        learnedCompact: String,
        language: RecognitionLanguage
    ) -> Bool {
        guard compact.count > learnedCompact.count else { return false }

        let remainder = String(compact.dropLast(learnedCompact.count))
        guard let trailingRank = spokenRankDigits(fromCompactRemainder: remainder, language: language),
              let learnedRank = learnedCompact.last,
              learnedRank.isNumber else {
            return false
        }

        return String(learnedRank) != trailingRank
    }

    private static func spokenRankDigits(
        fromCompactRemainder remainder: String,
        language: RecognitionLanguage
    ) -> String? {
        guard !remainder.isEmpty else { return nil }
        return ChessTranscriptNormalizer.spokenRankDigit(for: remainder, language: language)
    }

    private static func isSpokenRankOnly(_ token: String, language: RecognitionLanguage) -> Bool {
        ChessTranscriptNormalizer.spokenRankDigit(for: token, language: language) != nil
    }

    func applyCorrections(
        to text: String,
        language: RecognitionLanguage,
        tracer: SpeechPipelineTracer? = nil
    ) -> String {
        var normalized = Self.normalizePhrase(text, language: language)
        tracer?.record("Corrections", "Before personal corrections", normalized)
        let entries = correctionEntries(for: language).sorted {
            Self.normalizePhrase($0.heard, language: language).count > Self.normalizePhrase($1.heard, language: language).count
        }

        for entry in entries {
            let heard = Self.normalizePhrase(entry.heard, language: language)
            let replacement = Self.normalizePhrase(entry.replacement, language: language)
            guard !heard.isEmpty, !replacement.isEmpty else { continue }

            let before = normalized
            let escaped = NSRegularExpression.escapedPattern(for: heard)
                .replacingOccurrences(of: "\\ ", with: "\\s+")
            let boundaryPattern = "\\b\(escaped)\\b"
            normalized = normalized.replacingOccurrences(
                of: boundaryPattern,
                with: replacement,
                options: .regularExpression
            )

            // Also allow corrections to salvage compact alphanumeric blobs like
            // "931f3" where a user-taught correction such as "9 -> knight" should
            // expand inside the token stream instead of only matching whole words.
            normalized = normalized.replacingOccurrences(
                of: heard,
                with: " \(replacement) ",
                options: []
            )

            if normalized != before {
                tracer?.record("Corrections", "\(entry.heard) → \(entry.replacement)", normalized)
            }
        }

        normalized = normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        tracer?.record("Corrections", "Final corrected transcript", normalized)
        return normalized
    }

    private static func compactLearningKey(_ phrase: String, language: RecognitionLanguage) -> String {
        let normalized = normalizePhrase(phrase, language: language)
        let tokens = normalized
            .split(separator: " ")
            .map(String.init)

        var result = ""
        for token in tokens {
            if let mapped = mappedTokenForLearning(token, language: language) {
                result += mapped
            }
        }

        return result
    }

    private static func mappedTokenForLearning(_ token: String, language: RecognitionLanguage) -> String? {
        let cleaned = token.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return nil }

        if let square = normalizedSquareToken(cleaned, language: language) {
            return square
        }

        if separatorTokens(for: language).contains(cleaned) {
            return nil
        }

        if let piece = pieceToken(cleaned, language: language) {
            return piece
        }

        return cleaned
    }

    private static func normalizedSquareToken(_ token: String, language: RecognitionLanguage) -> String? {
        let token = token.lowercased()
        if token.count == 2,
           let file = token.first,
           let rank = token.last,
           "abcdefgh".contains(file),
           "12345678".contains(rank) {
            return token
        }

        if token.count == 3,
           let file = token.first,
           "abcdefgh".contains(file) {
            let suffix = String(token.dropFirst())
            if let rank = rankWordMap(for: language)[suffix] {
                return String(file) + rank
            }
        }

        return nil
    }

    private static func pieceToken(_ token: String, language: RecognitionLanguage) -> String? {
        switch language {
        case .english:
            switch token {
            case "knight", "night", "n", "9": return "n"
            case "bishop", "b": return "b"
            case "rook", "r", "rock", "look": return "r"
            case "queen", "q": return "q"
            case "king", "k": return "k"
            default: return nil
            }
        case .german:
            switch token {
            case "springer", "s": return "n"
            case "laufer", "lauferin", "l": return "b"
            case "turm", "t": return "r"
            case "dame", "d": return "q"
            case "konig", "k": return "k"
            default: return nil
            }
        }
    }

    private static func separatorTokens(for language: RecognitionLanguage) -> Set<String> {
        switch language {
        case .english:
            return ["to", "too", "two", "2", "from", "on", "at"]
        case .german:
            return ["nach", "zu", "von", "auf", "2"]
        }
    }

    private static func rankWordMap(for language: RecognitionLanguage) -> [String: String] {
        switch language {
        case .english:
            return [
                "one": "1", "two": "2", "three": "3", "four": "4",
                "five": "5", "six": "6", "seven": "7", "eight": "8"
            ]
        case .german:
            return [
                "eins": "1", "zwei": "2", "drei": "3", "vier": "4",
                "funf": "5", "fünf": "5", "sechs": "6", "sieben": "7", "acht": "8"
            ]
        }
    }

    private static func phraseLooksCaptureSpecific(_ words: [String], language: RecognitionLanguage) -> Bool {
        let captureWords: Set<String> = [
            "takes", "take", "captures", "capture",
            "schlagt", "schlaegt", "schagt", "schaegt", "nimmt",
            "x"
        ]

        if words.contains(where: { captureWords.contains($0.lowercased()) }) {
            return true
        }

        let joined = words.joined(separator: " ").lowercased()
        if joined.contains("x") {
            return true
        }

        // Coordinate source-target forms like g1f3 / d4e5 should also be
        // considered specific enough to keep.
        if words.count == 1, looksLikeCoordinateMove(words[0]) {
            return true
        }

        return false
    }

    private static func looksLikeCoordinateMove(_ token: String) -> Bool {
        let cleaned = token.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "x" }
        let compact = cleaned.replacingOccurrences(of: "x", with: "")
        guard compact.count == 4 || compact.count == 5 else { return false }

        let source = String(compact.prefix(2))
        let target = String(compact.dropFirst(2).prefix(2))
        return normalizedSquareToken(source, language: .english) != nil &&
            normalizedSquareToken(target, language: .english) != nil
    }

    private func upsert(
        phrase: String,
        moveNotation: String,
        language: RecognitionLanguage,
        minimumCount: Int,
        source: LearnedPhraseSource
    ) -> Bool {
        let normalizedIncoming = Self.normalizePhrase(phrase, language: language)
        let key = phraseIndexKey(
            language: language,
            source: source,
            normalizedPhrase: normalizedIncoming
        )
        let before = phraseIndex[key].map { phrases[$0] }

        let entry = upsertEntry(
            phrase: phrase,
            moveNotation: moveNotation,
            language: language,
            minimumCount: minimumCount,
            increment: 0,
            source: source,
            normalizedPhrase: normalizedIncoming
        )

        guard let before else { return true }
        return before.moveNotation != entry.moveNotation || before.count != entry.count || before.phrase != entry.phrase
    }

    private func upsertEntry(
        phrase: String,
        moveNotation: String,
        language: RecognitionLanguage,
        minimumCount: Int,
        increment: Int,
        source: LearnedPhraseSource = .user,
        normalizedPhrase: String? = nil
    ) -> LearnedPhrase {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMove = moveNotation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalized = normalizedPhrase ?? Self.normalizePhrase(trimmedPhrase, language: language)
        let key = phraseIndexKey(language: language, source: source, normalizedPhrase: normalized)

        if let index = phraseIndex[key] {
            phrases[index].count = min(max(phrases[index].count + increment, minimumCount), 1_000)
            phrases[index].moveNotation = normalizedMove
            phrases[index].phrase = trimmedPhrase
            phrases[index].updatedAt = Date()
            phrases[index].source = source
            return phrases[index]
        }

        let entry = LearnedPhrase(
            id: UUID(),
            phrase: trimmedPhrase,
            moveNotation: normalizedMove,
            languageCode: language.rawValue,
            count: min(max(minimumCount, 1), 1_000),
            updatedAt: Date(),
            source: source
        )
        phraseIndex[key] = phrases.count
        phrases.append(entry)
        return entry
    }

    private func phraseIndexKey(
        language: RecognitionLanguage,
        source: LearnedPhraseSource,
        normalizedPhrase: String
    ) -> String {
        "\(language.rawValue)|\(source.rawValue)|\(normalizedPhrase)"
    }

    private func rebuildPhraseIndex() {
        phraseIndex.removeAll(keepingCapacity: true)
        for (index, phrase) in phrases.enumerated() {
            guard let language = phrase.language else { continue }
            let normalized = Self.normalizePhrase(phrase.phrase, language: language)
            phraseIndex[phraseIndexKey(
                language: language,
                source: phrase.source,
                normalizedPhrase: normalized
            )] = index
        }
    }

    private static func retiredBuiltInMovePhrases(for language: RecognitionLanguage) -> [String] {
        switch language {
        case .english:
            return [
                "hey 3", "hey three", "ay 3", "ay three",
                "e3", "g3", "b3", "f6", "g6", "c6", "g1", "c3", "h5", "a3",
                "hey siri", "ay siri", "hey sir"
            ]
        case .german:
            return [
                "hey 3", "hey three",
                "g3", "b3", "f6", "c6", "g6", "g1", "c3", "h5", "a3",
                "see three", "sea three", "since we", "her siri", "see we", "sea we",
                "hey siri", "hey sir"
            ]
        }
    }

    private static let bundledTrainingSeedRevisionKey = "PersonalVocabularyBundledTrainingSeedRevision"
    private static let currentBundledTrainingSeedRevision = 3
    private static let bundledRecognitionSeedRevisionKey = "PersonalVocabularyBundledRecognitionSeedRevision"
    private static let currentBundledRecognitionSeedRevision = 2
    private static let legacyRecognitionOnlyPurgeKey = "PersonalVocabularyDidPurgeRecognitionOnly"

    private static func trainingSeedUpToDate(
        for language: RecognitionLanguage,
        in phrases: [LearnedPhrase]
    ) -> Bool {
        guard UserDefaults.standard.integer(forKey: bundledTrainingSeedRevisionKey)
            >= currentBundledTrainingSeedRevision else {
            return false
        }

        let expected = Set(commonTrainingPhrases(for: language).map {
            normalizePhrase($0.phrase, language: language)
        })
        let actual = Set(phrases.filter {
            $0.languageCode == language.rawValue && $0.source == .builtIn
        }.map {
            normalizePhrase($0.phrase, language: language)
        })
        return expected.isSubset(of: actual)
    }

    private static func recognitionSeedUpToDate(
        for language: RecognitionLanguage,
        in phrases: [LearnedPhrase]
    ) -> Bool {
        guard UserDefaults.standard.integer(forKey: bundledRecognitionSeedRevisionKey)
            >= currentBundledRecognitionSeedRevision else {
            return false
        }

        let expectedCount = ChessSpeechTrainingPhrases.generatedRecognitionPhraseCounts(for: language).count
        let actualCount = phrases.filter {
            $0.languageCode == language.rawValue && $0.source == .recognitionOnly
        }.count
        return actualCount >= expectedCount
    }

    private static func retiredRecognitionPhrases(for language: RecognitionLanguage) -> [String] {
        ChessSpeechTrainingPhrases.retiredPromotionBiasedRecognitionPhrases(for: language)
            + ChessSpeechTrainingPhrases.retiredFileBiasedRecognitionPhrases(for: language) + {
            switch language {
            case .english:
                return ["bishop shop takes d7"]
            case .german:
                return []
            }
        }()
    }

    private static func commonTrainingPhrases(for language: RecognitionLanguage) -> [(phrase: String, moveNotation: String, count: Int)] {
        switch language {
        case .english:
            return [
                ("d4", "d4", 350), ("d 4", "d4", 300),
                ("e4", "e4", 350), ("e 4", "e4", 300),
                ("c4", "c4", 300), ("c 4", "c4", 250),
                ("e5", "e5", 350), ("e 5", "e5", 300),
                ("d5", "d5", 300), ("d 5", "d5", 250),
                ("c5", "c5", 300), ("c 5", "c5", 250),
                ("nf3", "nf3", 300), ("knight f3", "nf3", 350), ("knight f 3", "nf3", 300),
                ("nf6", "nf6", 300), ("knight f6", "nf6", 360), ("knight f 6", "nf6", 320),
                ("nc3", "nc3", 260), ("knight c3", "nc3", 300), ("knight c 3", "nc3", 260),
                ("nc6", "nc6", 300), ("knight c6", "nc6", 380), ("knight c 6", "nc6", 340),
                ("bf4", "bf4", 220), ("bishop f4", "bf4", 260),
                ("bb5", "bb5", 220), ("bishop b5", "bb5", 260),
                ("castle", "o-o", 240), ("castle kingside", "o-o", 260),
                ("castle on kingside", "o-o", 250), ("castling kingside", "o-o", 250),
                ("castle queenside", "o-o-o", 220), ("castle on queenside", "o-o-o", 220),
                ("castling queenside", "o-o-o", 220)
            ]
        case .german:
            return [
                ("d4", "d4", 350), ("d 4", "d4", 300), ("d vier", "d4", 360), ("die vier", "d4", 340),
                ("e4", "e4", 350), ("e 4", "e4", 300), ("e vier", "e4", 360),
                ("c4", "c4", 300), ("c 4", "c4", 250), ("c vier", "c4", 300),
                ("e5", "e5", 350), ("e 5", "e5", 300), ("e funf", "e5", 360), ("e fünf", "e5", 360),
                ("d5", "d5", 300), ("d 5", "d5", 250), ("d funf", "d5", 300), ("d fünf", "d5", 300),
                ("c5", "c5", 300), ("c 5", "c5", 250), ("c funf", "c5", 280), ("c fünf", "c5", 280),
                ("sf3", "nf3", 280), ("springer f3", "nf3", 360), ("springer f 3", "nf3", 320), ("springer f drei", "nf3", 380),
                ("sf6", "nf6", 280), ("springer f6", "nf6", 360), ("springer f 6", "nf6", 320), ("springer f sechs", "nf6", 380),
                ("sc3", "nc3", 240), ("springer c3", "nc3", 300), ("springer c drei", "nc3", 320),
                ("sc6", "nc6", 280), ("springer c6", "nc6", 380), ("springer c 6", "nc6", 340),
                ("springer c sechs", "nc6", 400),
                ("lf4", "bf4", 220), ("laufer f4", "bf4", 260), ("läufer f4", "bf4", 260), ("laufer f vier", "bf4", 280), ("läufer f vier", "bf4", 280),
                ("lb5", "bb5", 220), ("laufer b5", "bb5", 260), ("läufer b5", "bb5", 260),
                ("kurz rochiert", "o-o", 240), ("kleine rochade", "o-o", 240), ("kurz rochade", "o-o", 240),
                ("kurze rochade", "o-o", 240), ("rochade", "o-o", 180),
                ("rochade auf konigsseite", "o-o", 260), ("rochade auf konig seite", "o-o", 240),
                ("lang rochiert", "o-o-o", 240), ("lange rochade", "o-o-o", 260), ("lang rochade", "o-o-o", 260),
                ("rochade auf damenseite", "o-o-o", 280), ("rochade auf damen seite", "o-o-o", 260),
                ("rochade auf damenflugel", "o-o-o", 260), ("rochade auf konigsflugel", "o-o", 240),
                ("grosse rochade", "o-o-o", 240), ("große rochade", "o-o-o", 240)
            ]
        }
    }

    private func bumpRevision(for language: RecognitionLanguage) {
        revisions[language.rawValue] = revision(for: language) + 1
    }

    private static func bundledVocabulary() -> PersonalVocabularyFile? {
        guard let url = Bundle.main.url(forResource: "DefaultVocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersonalVocabularyFile.self, from: data)
    }

    private static func defaultCorrections(for language: RecognitionLanguage) -> [LearnedCorrection] {
        bundledVocabulary()?.corrections.filter { $0.languageCode == language.rawValue } ?? []
    }
    
    private static let bundledDefaultsMigrationKey = "PersonalVocabularyDidMigrateBundledDefaults"
    private static let bundledCorrectionsRevisionKey = "PersonalVocabularyBundledCorrectionsRevision"
    private static let currentBundledCorrectionsRevision = 4

    private func load() {
        if let file = Self.loadVocabulary(from: storageURL) {
            apply(file)
            rebuildPhraseIndex()
            migrateLegacyRecognitionOnlyPhrasesIfNeeded()
            migrateBundledDefaultsIfNeeded()
            migrateBundledCorrectionsIfNeeded()
            return
        }

        if let bundled = Self.bundledVocabulary() {
            apply(bundled)
            rebuildPhraseIndex()
            save()
        }

        UserDefaults.standard.set(true, forKey: Self.bundledDefaultsMigrationKey)
        UserDefaults.standard.set(Self.currentBundledCorrectionsRevision, forKey: Self.bundledCorrectionsRevisionKey)
    }

    /// Drops thousands of legacy `recognitionOnly` rows now covered by runtime generators + CLM templates.
    private func migrateLegacyRecognitionOnlyPhrasesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.legacyRecognitionOnlyPurgeKey) else { return }

        let before = phrases.count
        phrases.removeAll { $0.source == .recognitionOnly }
        UserDefaults.standard.set(true, forKey: Self.legacyRecognitionOnlyPurgeKey)

        guard phrases.count != before else { return }
        rebuildPhraseIndex()
        for language in RecognitionLanguage.allCases {
            bumpRevision(for: language)
        }
        save()
    }

    /// Adds bundled default corrections introduced after the initial install.
    private func migrateBundledCorrectionsIfNeeded() {
        let storedRevision = UserDefaults.standard.integer(forKey: Self.bundledCorrectionsRevisionKey)
        guard storedRevision < Self.currentBundledCorrectionsRevision else { return }

        ensureBundledCorrections()
        UserDefaults.standard.set(Self.currentBundledCorrectionsRevision, forKey: Self.bundledCorrectionsRevisionKey)
    }

    /// Adds any bundled default corrections missing from the user's saved vocabulary.
    private func ensureBundledCorrections() {
        guard let bundled = Self.bundledVocabulary() else { return }

        var changed = false
        for bundledCorrection in bundled.corrections {
            guard let language = bundledCorrection.language else { continue }
            let normalizedHeard = Self.normalizePhrase(bundledCorrection.heard, language: language)
            let alreadyPresent = corrections.contains { existing in
                existing.languageCode == bundledCorrection.languageCode &&
                Self.normalizePhrase(existing.heard, language: language) == normalizedHeard
            }
            guard !alreadyPresent else { continue }
            corrections.append(bundledCorrection)
            changed = true
        }

        if changed {
            save()
        }
    }

    /// One-time upgrade path for installs that predated bundled default corrections.
    private func migrateBundledDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.bundledDefaultsMigrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: Self.bundledDefaultsMigrationKey) }

        guard corrections.isEmpty,
              let bundled = Self.bundledVocabulary(),
              !bundled.corrections.isEmpty else {
            return
        }

        corrections = bundled.corrections
        save()
    }

    private static func loadVocabulary(from url: URL) -> PersonalVocabularyFile? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersonalVocabularyFile.self, from: data)
    }

    private func apply(_ file: PersonalVocabularyFile) {
        phrases = file.phrases
        corrections = file.corrections
        revisions = file.revisions
    }
    
    private func save() {
        let file = PersonalVocabularyFile(phrases: phrases, corrections: corrections, revisions: revisions)
        do {
            let data = try JSONEncoder.vocabularyEncoder.encode(file)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("PersonalVocabularyStore: failed to save — \(error.localizedDescription)")
        }
    }
}

private extension JSONEncoder {
    static var vocabularyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
