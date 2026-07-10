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

    private func recognitionEntries(for language: RecognitionLanguage) -> [LearnedPhrase] {
        phrases
            .filter { $0.languageCode == language.rawValue }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func revision(for language: RecognitionLanguage) -> Int {
        revisions[language.rawValue] ?? 0
    }

    @discardableResult
    func seedCommonPhrasesIfNeeded(for language: RecognitionLanguage) -> Int {
        var changes = 0

        for item in Self.commonTrainingPhrases(for: language) {
            let changed = upsert(
                phrase: item.phrase,
                moveNotation: item.moveNotation,
                language: language,
                minimumCount: item.count,
                source: .builtIn
            )
            if changed { changes += 1 }
        }

        for item in Self.commonRecognitionPhrases(for: language) {
            let changed = upsert(
                phrase: item.phrase,
                moveNotation: item.phrase,
                language: language,
                minimumCount: item.count,
                source: .recognitionOnly
            )
            if changed { changes += 1 }
        }

        if changes > 0 {
            bumpRevision(for: language)
            save()
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
        bumpRevision(for: language)
        save()
    }
    
    func resetAll() {
        phrases.removeAll()
        corrections.removeAll()
        for language in RecognitionLanguage.allCases {
            bumpRevision(for: language)
        }
        save()
    }
    
    func speechPhraseCounts(for language: RecognitionLanguage) -> [(phrase: String, count: Int)] {
        recognitionEntries(for: language).map { ($0.phrase, $0.count) }
    }
    
    func contextualStrings(for language: RecognitionLanguage) -> [String] {
        recognitionEntries(for: language).map(\.phrase) + correctionEntries(for: language).map(\.heard)
    }
    
    /// Move candidates from learned phrase → move mappings (trailing phrase match).
    func candidateMoves(for text: String, language: RecognitionLanguage) -> [String] {
        let normalized = Self.normalizePhrase(text, language: language)
        let compact = Self.compactLearningKey(normalized, language: language)
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        
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

        for entry in recognitionEntries(for: language) {
            if entry.source == .recognitionOnly {
                continue
            }

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

    func applyCorrections(to text: String, language: RecognitionLanguage) -> String {
        var normalized = Self.normalizePhrase(text, language: language)
        let entries = correctionEntries(for: language).sorted {
            Self.normalizePhrase($0.heard, language: language).count > Self.normalizePhrase($1.heard, language: language).count
        }

        for entry in entries {
            let heard = Self.normalizePhrase(entry.heard, language: language)
            let replacement = Self.normalizePhrase(entry.replacement, language: language)
            guard !heard.isEmpty, !replacement.isEmpty else { continue }

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
        }

        return normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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
        let before = phrases.first(where: {
            $0.languageCode == language.rawValue &&
            $0.source == source &&
            Self.normalizePhrase($0.phrase, language: language) == Self.normalizePhrase(phrase, language: language)
        })

        let entry = upsertEntry(
            phrase: phrase,
            moveNotation: moveNotation,
            language: language,
            minimumCount: minimumCount,
            increment: 0,
            source: source
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
        source: LearnedPhraseSource = .user
    ) -> LearnedPhrase {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMove = moveNotation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedPhrase = Self.normalizePhrase(trimmedPhrase, language: language)

        if let index = phrases.firstIndex(where: {
            $0.languageCode == language.rawValue &&
            $0.source == source &&
            Self.normalizePhrase($0.phrase, language: language) == normalizedPhrase
        }) {
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
        phrases.append(entry)
        return entry
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
                ("g3", "g3", 220), ("g 3", "g3", 200),
                ("b3", "b3", 200), ("b 3", "b3", 180),
                ("f6", "f6", 280), ("f 6", "f6", 260), ("g6", "g6", 240), ("g 6", "g6", 220),
                ("c6", "c6", 280), ("c 6", "c6", 260),
                ("g1", "g1", 220), ("g 1", "g1", 200), ("c3", "c3", 240), ("c 3", "c3", 220),
                ("h5", "h5", 200), ("h 5", "h5", 180),
                ("a3", "a3", 420), ("a 3", "a3", 400), ("hey three", "a3", 450),
                ("hey 3", "a3", 440), ("ay three", "a3", 430), ("hey siri", "a3", 500),
                ("ay siri", "a3", 480), ("hey sir", "a3", 460),
                ("castle", "o-o", 240), ("castle kingside", "o-o", 260),
                ("castle queenside", "o-o-o", 220)
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
                ("g3", "g3", 220), ("g 3", "g3", 200), ("g drei", "g3", 230),
                ("b3", "b3", 200), ("b 3", "b3", 180), ("b drei", "b3", 210),
                ("f6", "f6", 280), ("f 6", "f6", 260), ("f sechs", "f6", 300),
                ("c6", "c6", 280), ("c 6", "c6", 260), ("c sechs", "c6", 300),
                ("g6", "g6", 240), ("g 6", "g6", 220), ("g sechs", "g6", 260),
                ("g1", "g1", 220), ("g 1", "g1", 200), ("g eins", "g1", 240),
                ("c3", "c3", 320), ("c 3", "c3", 300), ("see three", "c3", 320),
                ("sea three", "c3", 320), ("since we", "c3", 300), ("her siri", "c3", 300),
                ("see we", "c3", 300), ("sea we", "c3", 300),
                ("c drei", "c3", 250),
                ("h5", "h5", 200), ("h 5", "h5", 180), ("h funf", "h5", 210), ("h fünf", "h5", 210),
                ("a3", "a3", 420), ("a 3", "a3", 400), ("a drei", "a3", 410),
                ("hey three", "a3", 450), ("hey siri", "a3", 500), ("hey sir", "a3", 460),
                ("kurz rochiert", "o-o", 240), ("kleine rochade", "o-o", 240), ("kurz rochade", "o-o", 240),
                ("kurze rochade", "o-o", 240), ("rochade", "o-o", 180),
                ("lang rochiert", "o-o-o", 240), ("lange rochade", "o-o-o", 260),
                ("grosse rochade", "o-o-o", 240), ("große rochade", "o-o-o", 240)
            ]
        }
    }

    /// Phrases that boost on-device recognition only — excluded from move mapping.
    private static func commonRecognitionPhrases(for language: RecognitionLanguage) -> [(phrase: String, count: Int)] {
        let files = Array("abcdefgh").map(String.init)
        let digits = (1...8).map(String.init)

        var phrases: [(String, Int)] = []
        for file in files {
            phrases.append((file, 320))
        }
        for digit in digits {
            phrases.append((digit, 200))
        }

        switch language {
        case .english:
            let spokenRanks = [
                "one", "two", "three", "four", "five", "six", "seven", "eight"
            ]
            let spokenFiles = [
                "see", "sea", "bee", "dee", "gee", "aitch"
            ]
            let pieces = ["knight", "bishop", "rook", "queen", "king", "pawn"]
            for word in spokenRanks {
                phrases.append((word, 160))
            }
            for word in spokenFiles {
                phrases.append((word, 220))
            }
            for word in ["hey", "ay"] {
                phrases.append((word, 240))
            }
            for piece in pieces {
                phrases.append((piece, 480))
            }
            for (phrase, count) in ChessTranscriptNormalizer.englishPawnCaptureBoostPhrases(
                fileCount: 380,
                misheardCount: 360
            ) {
                phrases.append((phrase, count))
            }
            for phrase in [
                "c3", "c 3", "see three", "sea three", "see 3", "sea 3",
                "a3", "a 3", "hey three", "hey 3", "ay three", "ay 3",
                "a6", "a 6", "hey six", "ay six", "hey 6",
                "bishop b5 check", "knight f3 check", "rook d1 check",
                "bishop takes d7", "bishop shop takes d7", "bishop takes 7",
                "bishop e4 to e5", "bishop f1 to c4", "bishop takes e5",
                "bishop to e5", "bishop e5", "knight to f3", "knight f3",
                "knight g1 to f3", "knight f3 to e5", "knight takes d4",
                "d takes c4", "d takes e4", "c takes d4", "e takes d5",
                "detects c4", "detects c 4", "detects e4", "de takes c4", "de takes c 4",
                "knight e5 to d7", "night e5 to d7", "knight e5 to 7",
                "knight b to d7", "night b to d7", "knight be to d7", "night to be 7",
                "knight bd7", "night bd7",
                "rook f to d1", "rook g1 to f3", "rook e1 to e8", "rook to d1",
                "queen d1 to h5", "queen to h5", "king e1 to e2", "pawn to e4",
                "g8 rook", "e8 queen", "f8 knight", "e8 bishop",
                "rook g8", "queen e8", "f takes e8 rook"
            ] {
                phrases.append((phrase, 300))
            }
        case .german:
            let spokenRanks = [
                "eins", "zwei", "drei", "vier", "funf", "fünf", "sechs", "sieben", "acht"
            ]
            let pieces = ["springer", "laufer", "läufer", "turm", "dame", "konig", "könig", "bauer"]
            for word in spokenRanks {
                phrases.append((word, 160))
            }
            for piece in pieces {
                phrases.append((piece, 480))
            }
            for rank in 1...8 {
                let rankText = String(rank)
                phrases.append(("e\(rankText)", 280))
                phrases.append(("e \(rankText)", 260))
            }
            for spoken in ["eins", "zwei", "drei", "vier", "funf", "fünf", "sechs", "sieben", "acht"] {
                phrases.append(("e \(spoken)", 280))
            }
            for rank in 1...8 {
                let rankText = String(rank)
                phrases.append(("h\(rankText)", 360))
                phrases.append(("h \(rankText)", 340))
            }
            for phrase in [
                "turm f auf d1", "springer g1 auf f3", "turm f1 auf d1",
                "turm h auf g1", "turm h auf h1",
                "d schlagt e4", "d schlagt e vier",
                "läufer h auf g5", "springer h auf f3", "h auf f3", "h schlagt g5",
                "läufer auf e5", "läufer e5", "springer auf f3", "springer f3",
                "turm auf d1", "dame auf h5",
                "läufer b5 schach", "springer f3 schach", "turm d1 schach",
                "läufer auf e5 schach",
                "g8 turm", "e8 dame", "f8 springer", "e8 läufer", "f1 läufer",
                "turm g8", "dame e8", "f schlägt e8 turm"
            ] {
                phrases.append((phrase, 300))
            }
        }

        return phrases
    }
    
    private func bumpRevision(for language: RecognitionLanguage) {
        revisions[language.rawValue] = revision(for: language) + 1
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(PersonalVocabularyFile.self, from: data) else {
            return
        }
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
