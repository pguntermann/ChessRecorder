//
//  MoveInterpreter.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import Foundation

nonisolated enum MoveInterpreter {
    
    /// Returns candidate algebraic notations ordered from most to least likely.
    static func candidates(
        from text: String,
        language: RecognitionLanguage,
        personalVocabulary: PersonalVocabularyStore? = nil,
        transcriptAlreadyNormalized: Bool = false,
        tracer: SpeechPipelineTracer? = nil
    ) -> [String] {
        let normalized: String
        if transcriptAlreadyNormalized {
            normalized = text
        } else {
            normalized = normalizeTranscript(
                text,
                language: language,
                personalVocabulary: personalVocabulary,
                tracer: tracer
            )
        }
        let rawTokens = tokenize(normalized)
        tracer?.record("Move parsing", "Tokenized", rawTokens.joined(separator: " "))
        let allTokens = coalesceTokens(rawTokens, language: language)
        tracer?.record("Move parsing", "Coalesced tokens", allTokens.joined(separator: " "))

        // Specific castling phrases must win over generic personal phrases like "rochade" -> O-O.
        if let specificCastle = extractSpecificCastling(from: normalized, language: language) {
            tracer?.record("Move parsing", "Specific castling phrase", specificCastle)
            return [specificCastle]
        }

        var results: [String] = []
        var seen = Set<String>()

        func append(_ moves: [String]) {
            for move in moves {
                let key = move.lowercased()
                guard seen.insert(key).inserted else { continue }
                results.append(move)
            }
        }

        if let personalVocabulary,
           !isAmbiguousEnglishFileRankUtterance(allTokens, language: language) {
            let personalMoves = personalVocabulary.candidateMoves(for: normalized, language: language)
            if !personalMoves.isEmpty {
                tracer?.record("Move parsing", "User phrase matches", personalMoves.joined(separator: ", "))
            }
            append(personalMoves)
        } else if isAmbiguousEnglishFileRankUtterance(allTokens, language: language) {
            tracer?.record("Move parsing", "User phrase matches", "(skipped — ambiguous file+rank)")
        }

        var interpreted: [String] = []
        // Always interpret the trailing phrase — ASR accumulates old failed attempts.
        // Try the full suffix first (includes 5-token phrases like "springer c schlagt e 2"),
        // then fall back to sparse shorter windows without probing every intermediate length.
        let transcriptWideMoves = extractTranscriptWideCandidates(
            from: normalized,
            allTokens: allTokens,
            language: language
        )
        for size in trailingWindowSizes(tokenCount: allTokens.count) {
            let tokens = Array(allTokens.suffix(size))
            let phrase = tokens.joined(separator: " ")
            var tokenResults = candidatesFromTokenWindow(
                tokens,
                normalized: normalized,
                allTokens: allTokens,
                language: language
            )
            if !transcriptWideMoves.isEmpty {
                tokenResults = deduplicatedMoves(tokenResults + transcriptWideMoves)
            }
            if !tokenResults.isEmpty {
                interpreted = tokenResults
                tracer?.record("Move parsing", "Parsed from window (\(size) tokens): \"\(phrase)\"", tokenResults.joined(separator: ", "))
                break
            }
        }

        if interpreted.isEmpty {
            tracer?.record("Move parsing", "Parsed from tokens", "(none)")
        }

        // Prefer parsed moves over learned shortcuts when both are available.
        let combined = deduplicatedMoves([interpreted, results].flatMap { $0 })
        let ranked = prioritizeCandidates(
            combined,
            hasCaptureIntent: allTokens.contains(where: isCaptureVerb)
        )
        tracer?.record("Move parsing", "Before file-confusion expansion", ranked.joined(separator: ", "))
        let expanded = expandFileConfusionCandidates(ranked)
        if expanded.count > ranked.count {
            let added = expanded.filter { move in
                !ranked.contains { $0.caseInsensitiveCompare(move) == .orderedSame }
            }
            tracer?.record("Move parsing", "File-confusion variants added", added.joined(separator: ", "))
        }
        tracer?.record("Move parsing", "Final candidates", expanded.joined(separator: ", "))
        return expanded
    }

    private static func prioritizeCandidates(_ moves: [String], hasCaptureIntent: Bool) -> [String] {
        var seen = Set<String>()

        func appendUnique(_ move: String, to bucket: inout [String]) {
            let key = move.lowercased()
            guard seen.insert(key).inserted else { return }
            bucket.append(move)
        }

        if hasCaptureIntent {
            var captures: [String] = []
            var nonCaptures: [String] = []
            for move in moves {
                if isCaptureNotation(move) {
                    appendUnique(move, to: &captures)
                } else {
                    appendUnique(move, to: &nonCaptures)
                }
            }
            return captures + nonCaptures
        }

        var coordinates: [String] = []
        var squares: [String] = []
        var others: [String] = []

        for move in moves {
            let key = move.lowercased()
            guard seen.insert(key).inserted else { continue }
            if sanitizeSourceTarget(move) != nil {
                coordinates.append(move)
            } else if move.count == 2, sanitizeSquare(move) != nil {
                squares.append(move)
            } else {
                others.append(move)
            }
        }

        return coordinates + squares + others
    }

    static func prefersCaptureResolution(
        from text: String,
        language: RecognitionLanguage,
        transcriptAlreadyNormalized: Bool = false
    ) -> Bool {
        let normalized = transcriptAlreadyNormalized
            ? text
            : ChessTranscriptNormalizer.normalizeForPhraseMatching(text, language: language)
        let tokens = coalesceTokens(tokenize(normalized), language: language)
        return tokens.contains(where: isCaptureVerb)
    }

    static func isCaptureNotation(_ move: String) -> Bool {
        let lowered = move.lowercased()
        if ChessKitMapping.isPawnFileCaptureSAN(lowered) {
            return true
        }
        guard let xIndex = lowered.firstIndex(of: "x") else { return false }
        let prefix = lowered[..<xIndex]
        guard let first = prefix.first else { return false }
        if "nbrqk".contains(first) {
            return true
        }
        return prefix.count == 1 && "abcdefgh".contains(first)
    }

    /// Adds nearby file variants when ASR confuses short vowels (e/g/a, c/e, b/d).
    private static func expandFileConfusionCandidates(_ moves: [String]) -> [String] {
        var expanded = moves
        var seen = Set(moves.map { $0.lowercased() })

        func append(_ move: String) {
            let key = move.lowercased()
            guard seen.insert(key).inserted else { return }
            expanded.append(move)
        }

        for move in moves {
            if move.count == 2 {
                for variant in LegalMoveResolver.squareNotationVariants(for: move) {
                    append(variant)
                }
                continue
            }

            if move.count == 3,
               let first = move.first,
               "NBRQK".contains(String(first).uppercased()) {
                let square = String(move.suffix(2))
                for variant in LegalMoveResolver.squareNotationVariants(for: square) {
                    append(String(first) + variant)
                }
                continue
            }

            if move.count == 4,
               move.dropFirst().first?.lowercased() == "x",
               let first = move.first,
               "NBRQK".contains(String(first).uppercased()) {
                let square = String(move.suffix(2))
                for variant in LegalMoveResolver.squareNotationVariants(for: square) {
                    append(String(first) + "x" + variant)
                }
            }
        }

        return expanded
    }

    private static func deduplicatedMoves(_ moves: [String]) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        for move in moves {
            let key = move.lowercased()
            guard seen.insert(key).inserted else { continue }
            results.append(move)
        }
        return results
    }
    
    private static let sparseTrailingWindowSizes = [10, 8, 6, 5, 4, 3, 2, 1]

    /// Suffix lengths to try, largest first. Always includes the full token count (up to 10).
    private static func trailingWindowSizes(tokenCount: Int) -> [Int] {
        let capped = min(tokenCount, 10)
        var sizes = [capped]
        for size in sparseTrailingWindowSizes where size < capped {
            sizes.append(size)
        }
        return sizes
    }

    private static func extractTranscriptWideCandidates(
        from normalized: String,
        allTokens: [String],
        language: RecognitionLanguage
    ) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        func add(_ move: String?) {
            guard let move, isValidMoveNotation(move), seen.insert(move).inserted else { return }
            results.append(move)
        }

        let fullWords = tokenize(normalized)
        let hasCaptureVerb = allTokens.contains(where: isCaptureVerb)
            || fullWords.contains(where: isCaptureVerb)
        let hasPieceName = allTokens.contains(where: isPieceName)
            || fullWords.contains(where: isPieceName)

        add(extractCastle(from: normalized, language: language))
        for move in extractPatterns(
            from: normalized,
            language: language,
            allowBareSquares: !hasPieceName && !hasCaptureVerb
        ) {
            add(move)
        }

        return results
    }

    private static func candidatesFromTokenWindow(
        _ tokens: [String],
        normalized: String,
        allTokens: [String],
        language: RecognitionLanguage
    ) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        
        func add(_ move: String?) {
            guard let move, isValidMoveNotation(move), seen.insert(move).inserted else { return }
            results.append(move)
        }

        for move in extractPawnPromotions(from: tokens, language: language) {
            add(move)
        }

        let fullWords = tokenize(normalized)
        let hasCaptureVerb = allTokens.contains(where: isCaptureVerb)
            || fullWords.contains(where: isCaptureVerb)
        let hasPieceName = tokens.contains(where: isPieceName)
            || fullWords.contains(where: isPieceName)
        let pawnCaptureTokens = allTokens.contains(where: isCaptureVerb) ? allTokens : tokens

        switch language {
        case .english:
            for move in extractDisambiguatedPieceMoves(from: tokens, piecePrefix: englishPiecePrefix, language: language) { add(move) }
            for move in extractPieceSourceTarget(from: tokens, piecePrefix: englishPiecePrefix) { add(move) }
            for move in extractPieceCaptures(from: tokens, piecePrefix: englishPiecePrefix, language: language) { add(move) }
            for move in extractPawnCaptures(from: pawnCaptureTokens, language: language) { add(move) }
            for move in extractSpacedSquares(from: tokens, language: language) { add(move) }
            for move in extractImplicitPawnCaptures(from: tokens, language: language) { add(move) }
            for move in extractSquareToSquareMoves(from: tokens, language: language) { add(move) }
            for move in extractPieceToSquare(from: tokens, piecePrefix: englishPiecePrefix) { add(move) }
            if !hasCaptureVerb && !hasPieceName {
                add(latestSquare(from: tokens, normalize: normalizeEnglishToken))
                add(normalizeEnglishToken(tokens.last ?? ""))
            }
        case .german:
            for move in extractDisambiguatedPieceMoves(from: tokens, piecePrefix: germanPiecePrefix, language: language) { add(move) }
            for move in extractPieceSourceTarget(from: tokens, piecePrefix: germanPiecePrefix) { add(move) }
            for move in extractPieceCaptures(from: tokens, piecePrefix: germanPiecePrefix, language: language) { add(move) }
            for move in extractPawnCaptures(from: pawnCaptureTokens, language: language) { add(move) }
            for move in extractSpacedSquares(from: tokens, language: language) { add(move) }
            for move in extractImplicitPawnCaptures(from: tokens, language: language) { add(move) }
            for move in extractSquareToSquareMoves(from: tokens, language: language) { add(move) }
            for move in extractPieceToSquare(from: tokens, piecePrefix: germanPiecePrefix) { add(move) }
            if !hasCaptureVerb && !hasPieceName {
                add(latestSquare(from: tokens, normalize: normalizeGermanToken))
                add(normalizeGermanToken(tokens.last ?? ""))
            }
        }

        return results
    }
    
    private static func trailingTokens(from text: String, language: RecognitionLanguage, maxCount: Int = 10) -> [String] {
        let normalized = normalizeTranscript(text, language: language, personalVocabulary: nil)
        let tokens = coalesceTokens(tokenize(normalized), language: language)
        return Array(tokens.suffix(maxCount))
    }
    
    // MARK: - Normalization
    
    private static func normalizeTranscript(
        _ text: String,
        language: RecognitionLanguage,
        personalVocabulary: PersonalVocabularyStore?,
        tracer: SpeechPipelineTracer? = nil
    ) -> String {
        let normalized = ChessTranscriptNormalizer.normalizeForPhraseMatching(
            text,
            language: language,
            tracer: tracer
        )
        return personalVocabulary?.applyCorrections(
            to: normalized,
            language: language,
            tracer: tracer
        ) ?? normalized
    }
    
    private static func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }
    
    private static func coalesceTokens(_ words: [String], language: RecognitionLanguage) -> [String] {
        var result: [String] = []
        var index = 0
        
        while index < words.count {
            // ASR hears "d4" as "die 4"
            if language == .german,
               words[index].lowercased() == "die",
               index + 1 < words.count,
               let square = combineSquare(file: "d", rank: words[index + 1]) {
                result.append(square)
                index += 2
                continue
            }
            
            if index + 2 < words.count,
               words[index].count == 1,
               let file = words[index].first,
               "abcdefgh".contains(file),
               !isCaptureVerb(words[index + 1]),
               let merged = mergedMisheardRankSquare(
                   file: file,
                   middleToken: words[index + 1],
                   thirdToken: words[index + 2],
                   language: language
               ) {
                result.append(merged)
                index += 3
                continue
            }

            if index + 1 < words.count,
               !isCaptureVerb(words[index + 1]),
               !isCaptureVerb(words[index]),
               !(index > 0 && isCaptureVerb(words[index - 1])) {
                let candidates = fileRankSquareCandidates(
                    fileToken: words[index],
                    rankToken: words[index + 1],
                    language: language
                )
                if candidates.count == 1 {
                    result.append(candidates[0])
                    index += 2
                    continue
                }

                if let coordinate = combinedCoordinateNotation(
                    fileToken: words[index],
                    remainderToken: words[index + 1]
                ) {
                    result.append(coordinate)
                    index += 2
                    continue
                }
            }
            
            if index > 0,
               isPieceName(words[index - 1]),
               let merged = rankDisambiguatedTarget(in: words[index]) {
                result.append(merged.rank)
                result.append(merged.square)
                index += 1
                continue
            }

            if let square = sanitizeSquare(words[index]) {
                if index + 1 < words.count,
                   sanitizeSquare(words[index + 1]) == nil,
                   !isMovePreposition(words[index + 1]),
                   let file = square.first,
                   let trailingRank = ChessTranscriptNormalizer.spokenRankDigit(for: words[index + 1], language: language),
                   String(square.suffix(1)) != trailingRank {
                    result.append(String(file) + trailingRank)
                    index += 2
                    continue
                }

                if String(square.suffix(1)) == "3",
                   index + 1 < words.count,
                   words[index + 1] == "6",
                   let file = square.first {
                    result.append(String(file) + "6")
                    index += 2
                    continue
                }

                result.append(square)
                index += 1
                continue
            }
            
            result.append(words[index])
            index += 1
        }
        
        return result.filter { word in
            !stopWords(for: language).contains(word.lowercased())
        }
    }
    
    private static func stopWords(for language: RecognitionLanguage) -> Set<String> {
        switch language {
        case .english:
            return ["siri", "the", "and", "or", "on",
                    "check", "checkmate", "mate", "shop",
                    "promote", "promotion", "promoting", "promoted"]
        case .german:
            return ["siri", "und", "oder",
                    "schach", "schachmatt", "matt",
                    "umwandlung", "umwandeln", "umwandelt"]
        }
    }
    
    // MARK: - Extraction
    
    private static func latestSquare(
        from tokens: [String],
        normalize: (String) -> String?
    ) -> String? {
        for token in tokens.reversed() {
            if let square = sanitizeSquare(token) {
                return square
            }
            if let move = normalize(token) {
                return move
            }
        }
        return nil
    }
    
    private static func extractCastle(from text: String, language: RecognitionLanguage) -> String? {
        if let specific = extractSpecificCastling(from: text, language: language) {
            return specific
        }

        let normalized = text.lowercased()
        switch language {
        case .english:
            if normalized.contains("castle") {
                return "O-O"
            }
        case .german:
            if normalized.contains("rochiert") || normalized.contains("rochade") {
                return "O-O"
            }
        }
        return nil
    }

    private static func extractSpecificCastling(from text: String, language: RecognitionLanguage) -> String? {
        let normalized = text.lowercased()

        switch language {
        case .english:
            if matchesAny(normalized, phrases: englishQueensideCastlingPhrases) {
                return "O-O-O"
            }
            if matchesAny(normalized, phrases: englishKingsideCastlingPhrases) {
                return "O-O"
            }
        case .german:
            if matchesAny(normalized, phrases: germanQueensideCastlingPhrases) {
                return "O-O-O"
            }
            if matchesAny(normalized, phrases: germanKingsideCastlingPhrases) {
                return "O-O"
            }
        }
        return nil
    }

    private static let englishQueensideCastlingPhrases = [
        "castle queenside", "castles queenside", "castle on queenside", "castles on queenside",
        "castling queenside", "castlings queenside",
        "castle long", "castles long", "queenside castle", "long castle"
    ]

    private static let englishKingsideCastlingPhrases = [
        "castle kingside", "castles kingside", "castle on kingside", "castles on kingside",
        "castling kingside", "castlings kingside",
        "castle short", "castles short", "kingside castle", "short castle"
    ]

    private static let germanQueensideCastlingPhrases = [
        "lang rochiert", "gross rochiert", "groß rochiert",
        "lang rochade",
        "lange rochade", "große rochade", "grosse rochade", "gross rochade",
        "groß rochade",
        "rochade auf damenseite", "rochade auf damen seite",
        "rochade auf damenflugel", "rochade auf damen flugel"
    ]

    private static let germanKingsideCastlingPhrases = [
        "kurz rochiert", "kleine rochade", "klein rochade", "kurze rochade",
        "kurz rochade",
        "rochade auf konigsseite", "rochade auf konigs seite", "rochade auf konig seite",
        "rochade auf konigsflugel", "rochade auf konigs flugel"
    ]
    
    private static func matchesAny(_ text: String, phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
    
    private static func extractPieceCaptures(
        from words: [String],
        piecePrefix: (String) -> String,
        language: RecognitionLanguage
    ) -> [String] {
        guard words.count >= 3 else { return [] }
        
        var moves: [String] = []
        
        for verbIndex in stride(from: words.count - 2, through: 1, by: -1) {
            guard isCaptureVerb(words[verbIndex]) else { continue }

            let targets = targetSquareCandidates(from: words, verbIndex: verbIndex, language: language)
            guard !targets.isEmpty else { continue }

            for target in targets {
                if verbIndex >= 2, isPieceName(words[verbIndex - 2]),
                   let fromSquare = sanitizeSquare(words[verbIndex - 1]) {
                    let piece = piecePrefix(words[verbIndex - 2])
                    if !piece.isEmpty {
                        moves.append(piece + fromSquare + "x" + target)
                    }
                }

                if verbIndex >= 2,
                   isPieceName(words[verbIndex - 2]),
                   let suffix = disambiguationSuffix(forToken: words[verbIndex - 1], language: language) {
                    let piece = piecePrefix(words[verbIndex - 2])
                    if !piece.isEmpty {
                        moves.append(piece + suffix + "x" + target)
                    }
                }

                if isPieceName(words[verbIndex - 1]) {
                    let piece = piecePrefix(words[verbIndex - 1])
                    if !piece.isEmpty {
                        moves.append(piece + "x" + target)
                    }
                }
            }
        }
        
        return moves
    }
    
    /// Handles "Knight g1 to f3", "Springer g1 auf Springer f3", "Turm f auf d1", etc.
    private static func extractDisambiguatedPieceMoves(
        from words: [String],
        piecePrefix: (String) -> String,
        language: RecognitionLanguage
    ) -> [String] {
        var moves: [String] = []
        guard words.count >= 3 else { return moves }
        
        for start in 0..<words.count {
            guard isPieceName(words[start]) else { continue }
            
            let piece = piecePrefix(words[start])
            guard !piece.isEmpty else { continue }

            let rankMoves = extractPieceFileOrRankMove(
                from: words,
                start: start,
                piece: piece,
                language: language
            )
            moves.append(contentsOf: rankMoves)
            
            guard start + 1 < words.count,
                  let from = sanitizeSquare(words[start + 1]) else { continue }
            
            var cursor = start + 2
            if cursor < words.count && isMovePreposition(words[cursor]) {
                cursor += 1
            }
            if cursor < words.count && isPieceName(words[cursor]) {
                cursor += 1
            }
            guard cursor < words.count else { continue }

            let destinationSquares = squareCandidates(from: words[cursor], language: language)
            guard !destinationSquares.isEmpty else { continue }

            for to in destinationSquares {
                moves.append(from + to)
                moves.append(piece + to)
                moves.append(piece + disambiguationSuffix(for: from) + to)

                if start + 2 < words.count,
                   isCaptureVerb(words[start + 2]) || (start + 3 < words.count && isCaptureVerb(words[start + 3])) {
                    moves.append(piece + from + "x" + to)
                    moves.append(piece + disambiguationSuffix(for: from) + "x" + to)
                }
            }
        }
        
        return moves
    }

    /// "Turm f auf d1" -> Rfd1, "Rook 1 to d1" -> R1d1
    private static func extractPieceFileOrRankMove(
        from words: [String],
        start: Int,
        piece: String,
        language: RecognitionLanguage
    ) -> [String] {
        guard start + 1 < words.count else { return [] }

        // "springer 5f3" — ASR may merge rank disambiguation with destination square.
        if let merged = rankDisambiguatedTarget(in: words[start + 1]) {
            return [piece + merged.rank + merged.square]
        }

        // "knight bd7" — ASR may merge file disambiguation with destination square.
        if let merged = fileDisambiguatedTarget(in: words[start + 1]) {
            return [piece + merged.file + merged.square]
        }

        guard start + 2 < words.count else { return [] }

        let disambiguator = words[start + 1]
        guard let suffix = disambiguationSuffix(forToken: disambiguator, language: language) else {
            return []
        }

        var cursor = start + 2
        if cursor < words.count && isMovePreposition(words[cursor]) {
            cursor += 1
        }
        if cursor < words.count && isPieceName(words[cursor]) {
            cursor += 1
        }
        guard cursor < words.count else { return [] }

        let destinationSquares = squareCandidates(from: words[cursor], language: language)
        guard !destinationSquares.isEmpty else { return [] }

        return destinationSquares.map { piece + suffix + $0 }
    }

    /// "5f3" → rank 5 + square f3 (ASR often merges rank disambiguation with the destination).
    private static func rankDisambiguatedTarget(in token: String) -> (rank: String, square: String)? {
        let lowered = token.lowercased()
        guard lowered.count == 3,
              let rank = lowered.first,
              "12345678".contains(rank),
              let square = sanitizeSquare(String(lowered.dropFirst())),
              rank != square.last else {
            return nil
        }
        return (String(rank), square)
    }

    /// "bd7" → file b + square d7 (ASR often merges file disambiguation with the destination).
    private static func fileDisambiguatedTarget(in token: String) -> (file: String, square: String)? {
        let lowered = token.lowercased()
        guard lowered.count == 3,
              let file = lowered.first,
              "abcdefgh".contains(file),
              let square = sanitizeSquare(String(lowered.dropFirst())),
              file != square.first else {
            return nil
        }
        return (String(file), square)
    }

    private static func disambiguationSuffix(for square: String) -> String {
        guard square.count == 2 else { return square }
        return String(square.prefix(1))
    }

    private static func disambiguationSuffix(forToken token: String, language: RecognitionLanguage) -> String? {
        if token.count == 1, let file = token.first, "abcdefgh".contains(file) {
            return String(file)
        }
        if let file = ChessTranscriptNormalizer.spokenFileLetter(for: token, language: language) {
            return String(file)
        }
        let rank = ChessTranscriptNormalizer.normalizeSpokenRankToken(token, language: language)
        if rank.count == 1, "12345678".contains(rank) {
            return rank
        }
        return nil
    }

    /// Expands a rank-only token (e.g. "7" after "to") into all squares on that rank.
    private static func squareCandidates(from token: String, language: RecognitionLanguage) -> [String] {
        if let square = sanitizeSquare(token) {
            return [square]
        }
        if let rank = ChessTranscriptNormalizer.spokenRankDigit(for: token, language: language) {
            return "abcdefgh".map { "\($0)\(rank)" }
        }
        return []
    }
    
    private static func isMovePreposition(_ word: String) -> Bool {
        ["auf", "nach", "to", "too", "two", "2"].contains(word.lowercased())
    }
    
    private static func extractPieceToSquare(
        from words: [String],
        piecePrefix: (String) -> String
    ) -> [String] {
        guard words.count >= 2 else { return [] }
        
        var moves: [String] = []
        for index in 1..<words.count {
            guard isPieceName(words[index - 1]) else { continue }
            let piece = piecePrefix(words[index - 1])
            guard !piece.isEmpty else { continue }

            var target = index
            while target < words.count && isPieceMoveFiller(words[target]) {
                target += 1
            }
            guard target < words.count else { continue }

            if let square = sanitizeSquare(words[target]), !isPromotionRank(square) {
                moves.append(piece + square)
                continue
            }

            if target + 1 < words.count,
               isMovePreposition(words[target]),
               let square = sanitizeSquare(words[target + 1]),
               !isPromotionRank(square) {
                moves.append(piece + square)
            }
        }
        return moves
    }

    private static func isPieceMoveFiller(_ word: String) -> Bool {
        ["at"].contains(word.lowercased()) || isMovePreposition(word)
    }

    private static func extractPieceSourceTarget(
        from words: [String],
        piecePrefix: (String) -> String
    ) -> [String] {
        guard words.count >= 2 else { return [] }

        var moves: [String] = []
        for index in 1..<words.count {
            guard isPieceName(words[index - 1]),
                  let sourceTarget = sanitizeSourceTarget(words[index]) else { continue }
            let piece = piecePrefix(words[index - 1])
            if !piece.isEmpty {
                moves.append(sourceTarget)
            }
        }

        return moves
    }
    
    /// "g8 rook", "rook g8", "f takes e8 queen" → pawn promotion SAN (e.g. g8=R).
    private static func extractPawnPromotions(
        from words: [String],
        language: RecognitionLanguage
    ) -> [String] {
        var moves: [String] = []

        func appendPromotion(to square: String, pieceWord: String) {
            guard let suffix = promotionSuffix(from: pieceWord, language: language) else { return }
            moves.append(square + "=" + suffix)
        }

        for index in 0..<words.count {
            guard let square = sanitizeSquare(words[index]),
                  isPromotionRank(square) else { continue }

            var pieceIndex = index + 1
            while pieceIndex < words.count && isMovePreposition(words[pieceIndex]) {
                pieceIndex += 1
            }
            if pieceIndex < words.count {
                appendPromotion(to: square, pieceWord: words[pieceIndex])
            }
        }

        for index in 0..<words.count {
            guard let suffix = promotionSuffix(from: words[index], language: language) else { continue }

            var squareIndex = index + 1
            while squareIndex < words.count && isMovePreposition(words[squareIndex]) {
                squareIndex += 1
            }
            guard squareIndex < words.count,
                  let square = sanitizeSquare(words[squareIndex]),
                  isPromotionRank(square) else { continue }

            moves.append(square + "=" + suffix)
        }

        for verbIndex in stride(from: words.count - 2, through: 1, by: -1) {
            guard isCaptureVerb(words[verbIndex]) else { continue }

            let targets = targetSquareCandidates(from: words, verbIndex: verbIndex, language: language)
                .filter(isPromotionRank)
            guard !targets.isEmpty else { continue }

            var scan = verbIndex + 1
            while scan < words.count {
                let tokenCandidates = squareCandidates(from: words[scan], language: language)
                let tokenSquare = tokenCandidates.first
                    ?? sanitizeSquare(words[scan])
                    ?? (scan + 1 < words.count
                        ? combineSquare(file: words[scan], rank: words[scan + 1])
                        : nil)

                guard let tokenSquare,
                      targets.contains(tokenSquare) else {
                    scan += 1
                    continue
                }

                let target = tokenSquare
                let targetTokenCount = sanitizeSquare(words[scan]) != nil
                    || !squareCandidates(from: words[scan], language: language).isEmpty ? 1 : 2
                var pieceIndex = scan + targetTokenCount
                while pieceIndex < words.count && isMovePreposition(words[pieceIndex]) {
                    pieceIndex += 1
                }
                guard pieceIndex < words.count,
                      let suffix = promotionSuffix(from: words[pieceIndex], language: language) else { break }

                let source = words[verbIndex - 1]
                if source.count == 1, let file = source.first, "abcdefgh".contains(file) {
                    moves.append(String(file) + "x" + target + "=" + suffix)
                } else if let fromSquare = sanitizeSquare(source), let file = fromSquare.first {
                    moves.append(String(file) + "x" + target + "=" + suffix)
                }
                break
            }
        }

        return moves
    }

    private static func isPromotionRank(_ square: String) -> Bool {
        guard let rank = square.last else { return false }
        return rank == "1" || rank == "8"
    }

    private static func promotionSuffix(from word: String, language: RecognitionLanguage) -> String? {
        let prefix = language == .english
            ? englishPiecePrefix(for: word)
            : germanPiecePrefix(for: word)
        guard !prefix.isEmpty, prefix != "K" else { return nil }
        return prefix
    }

    private static func extractPawnCaptures(from words: [String], language: RecognitionLanguage) -> [String] {
        guard words.count >= 3 else { return [] }
        
        var moves: [String] = []
        
        for verbIndex in stride(from: words.count - 2, through: 1, by: -1) {
            guard isCaptureVerb(words[verbIndex]) else { continue }

            let targets = targetSquareCandidates(from: words, verbIndex: verbIndex, language: language)
            guard !targets.isEmpty else { continue }

            // "Springer b schlägt d7" — the file token is piece disambiguation, not a pawn file.
            if verbIndex >= 2, isPieceName(words[verbIndex - 2]) {
                continue
            }

            let source = words[verbIndex - 1]
            let sourceFiles = sourceFileLetters(from: source, language: language)

            for target in targets {
                for file in sourceFiles {
                    moves.append(String(file) + "x" + target)
                }
                if let fromSquare = sanitizeSquare(source) {
                    moves.append(fromSquare + target)
                    moves.append(String(fromSquare.first!) + "x" + target)
                    if source.count == 2 {
                        moves.append(fromSquare + "x" + target)
                    }
                }
            }
        }
        
        return moves
    }

    /// "c d4", "she d4", "c5 d4" — ASR often omits the capture verb entirely.
    private static func extractImplicitPawnCaptures(from words: [String], language: RecognitionLanguage) -> [String] {
        guard words.count >= 2,
              !words.contains(where: isCaptureVerb),
              !words.contains(where: isPieceName) else {
            return []
        }

        var moves: [String] = []

        for index in 1..<words.count {
            let sourceToken = words[index - 1]
            if fileRankSquareCandidates(
                fileToken: sourceToken,
                rankToken: words[index],
                language: language
            ).count > 1 {
                // "hey 3" is a square utterance, not an implicit capture onto every rank-3 square.
                continue
            }

            let targets = squareCandidates(from: words[index], language: language)
            guard targets.count == 1 else { continue }

            let sourceFiles = sourceFileLetters(from: sourceToken, language: language)

            for target in targets {
                for sourceFile in sourceFiles {
                    moves.append(String(sourceFile) + "x" + target)
                }
                if let fromSquare = sanitizeSquare(sourceToken), let file = fromSquare.first {
                    moves.append(fromSquare + "x" + target)
                    moves.append(String(file) + "x" + target)
                }
            }
        }

        return moves
    }

    /// "e2 nach d4", "g1 to f3" → coordinate notation (e2d4, g1f3).
    private static func extractSquareToSquareMoves(
        from words: [String],
        language: RecognitionLanguage
    ) -> [String] {
        var moves: [String] = []

        for index in 0..<words.count {
            guard let from = sanitizeSquare(words[index]) else { continue }

            var cursor = index + 1
            while cursor < words.count && isMovePreposition(words[cursor]) {
                cursor += 1
            }
            guard cursor < words.count else { continue }

            var destinations = squareCandidates(from: words[cursor], language: language)
            if destinations.isEmpty,
               cursor + 1 < words.count {
                destinations = fileRankSquareCandidates(
                    fileToken: words[cursor],
                    rankToken: words[cursor + 1],
                    language: language
                )
            }

            for to in destinations where to != from {
                moves.append(from + to)
            }
        }

        return moves
    }

    private static func extractSpacedSquares(from words: [String], language: RecognitionLanguage) -> [String] {
        guard words.count >= 2 else { return [] }

        return fileRankSquareCandidates(
            fileToken: words[words.count - 2],
            rankToken: words[words.count - 1],
            language: language
        )
    }
    
    private static func extractPatterns(from text: String, language: RecognitionLanguage, allowBareSquares: Bool) -> [String] {
        let stripped = ChessTranscriptNormalizer.stripSpokenArticles(from: text, language: language)
        let compact = stripped.replacingOccurrences(of: " ", with: "")
        var moves: [String] = []
        
        let captureVerbs = "(?:schlagt|schlaegt|schagt|nimmt|takes|take|captures|capture)"
        
        let piecePatterns: [(String, String)] = [
            ("(?:springer|knight|night)", "N"),
            ("(?:laufer|laeufer|lauferin|bishop)", "B"),
            ("(?:turm|rook|rock|look)", "R"),
            ("(?:dame|queen)", "Q"),
            ("(?:konig|king)", "K")
        ]
        
        for (piecePattern, prefix) in piecePatterns {
            let regex = try! Regex("\(piecePattern)([a-h][1-8])?\(captureVerbs)([a-h][1-8])")
            if let match = compact.matches(of: regex).last {
                let output = String(compact[match.range])
                if let move = pieceCaptureNotation(compact: output, prefix: prefix, markers: markerNames(for: piecePattern)) {
                    moves.append(move)
                }
            }
            
            let toSquareRegex = try! Regex("\(piecePattern)([a-h][1-8])")
            if let match = compact.matches(of: toSquareRegex).last {
                let output = String(compact[match.range])
                if let move = pieceToSquareNotation(compact: output, prefix: prefix, markers: markerNames(for: piecePattern)) {
                    moves.append(move)
                }
            }

            let sourceTargetRegex = try! Regex("\(piecePattern)([a-h][1-8])(?:to|too|two|2)?([a-h][1-8])")
            if let match = compact.matches(of: sourceTargetRegex).last {
                let output = String(compact[match.range])
                if let move = pieceSourceTargetNotation(compact: output, markers: markerNames(for: piecePattern)) {
                    moves.append(move)
                }
            }
            
            let aufMoveRegex = try! Regex("\(piecePattern)([a-h][1-8])auf(?:\(piecePattern))?([a-h][1-8])")
            if let match = compact.matches(of: aufMoveRegex).last {
                let output = String(compact[match.range])
                moves.append(contentsOf: pieceAufMoveNotations(compact: output, prefix: prefix, markers: markerNames(for: piecePattern)))
            }

            let fileAufMoveRegex = try! Regex("\(piecePattern)([a-h])(?:auf|nach|to)([a-h][1-8])")
            if let match = compact.matches(of: fileAufMoveRegex).last {
                let output = String(compact[match.range])
                if let move = pieceFileAufMoveNotation(compact: output, prefix: prefix, markers: markerNames(for: piecePattern)) {
                    moves.append(move)
                }
            }

            let fileDisambiguatedRegex = try! Regex("\(piecePattern)([a-h])([a-h][1-8])")
            if let match = compact.matches(of: fileDisambiguatedRegex).last {
                let output = String(compact[match.range])
                if let move = pieceFileDisambiguatedTargetNotation(
                    compact: output,
                    prefix: prefix,
                    markers: markerNames(for: piecePattern)
                ) {
                    moves.append(move)
                }
            }

            let rankDisambiguatedRegex = try! Regex("\(piecePattern)([1-8])([a-h][1-8])")
            if let match = compact.matches(of: rankDisambiguatedRegex).last {
                let output = String(compact[match.range])
                if let move = pieceRankDisambiguatedTargetNotation(
                    compact: output,
                    prefix: prefix,
                    markers: markerNames(for: piecePattern)
                ) {
                    moves.append(move)
                }
            }
        }
        
        if let move = extractCompactPawnCapture(from: compact) {
            moves.append(move)
        }

        moves.append(contentsOf: extractCompactPawnPromotions(from: compact))

        if let coordinateMove = extractCompactCoordinateMove(from: compact) {
            moves.append(coordinateMove)
        }

        if let bareCoordinateMove = extractBareCompactCoordinateMove(from: compact) {
            moves.append(bareCoordinateMove)
        }
        
        if allowBareSquares {
            let compactPatterns = [
                "[nbrqk][a-h]?[1-8]?x[a-h][1-8]",
                "[a-h](?:[1-8])?x[a-h][1-8]",
                "(?:[nbrqk][a-h]?[1-8]?)?[a-h][1-8](?:=[nbrqk])?"
            ]
            
            for pattern in compactPatterns {
                if let match = compact.matches(of: try! Regex(pattern)).last {
                    moves.append(String(compact[match.range]))
                }
            }
        }
        
        return moves
    }

    private static func extractCompactCoordinateMove(from compact: String) -> String? {
        guard let match = compact.firstMatch(of: /([a-h][1-8])(?:auf|nach|to|too|two|2)([a-h][1-8])/) else {
            return nil
        }

        let from = String(match.output.1)
        let to = String(match.output.2)
        guard from != to else { return nil }
        return from + to
    }

    /// Bare UCI-style coordinate moves without a preposition, e.g. "g1f3" from ASR "g 1f3".
    private static func extractBareCompactCoordinateMove(from compact: String) -> String? {
        guard let match = compact.firstMatch(of: /([a-h][1-8])([a-h][1-8])/) else {
            return nil
        }

        let from = String(match.output.1)
        let to = String(match.output.2)
        guard from != to else { return nil }
        return sanitizeSourceTarget(from + to)
    }

    private static func combinedCoordinateNotation(fileToken: String, remainderToken: String) -> String? {
        guard fileToken.count == 1,
              let file = fileToken.first,
              "abcdefgh".contains(file) else {
            return nil
        }

        let remainder = remainderToken.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !remainder.isEmpty else { return nil }

        return sanitizeSourceTarget(String(file) + remainder)
    }
    
    private static func pieceToSquareNotation(compact: String, prefix: String, markers: [String]) -> String? {
        guard let marker = markers.first(where: { compact.hasPrefix($0) }) else { return nil }
        let square = String(compact.dropFirst(marker.count))
        guard square.count == 2,
              let file = square.first,
              let rank = square.last,
              "abcdefgh".contains(file),
              "12345678".contains(rank) else {
            return nil
        }
        return prefix + square
    }

    private static func pieceSourceTargetNotation(compact: String, markers: [String]) -> String? {
        guard let marker = markers.first(where: { compact.hasPrefix($0) }) else { return nil }
        var remainder = String(compact.dropFirst(marker.count))
        remainder = remainder.replacingOccurrences(of: "too", with: "to")
        remainder = remainder.replacingOccurrences(of: "two", with: "to")
        remainder = remainder.replacingOccurrences(of: "2", with: "to")

        if remainder.count == 4,
           let sourceTarget = sanitizeSourceTarget(remainder) {
            return sourceTarget
        }

        guard let toRange = remainder.range(of: "to") else { return nil }
        let fromPart = String(remainder[..<toRange.lowerBound])
        let toPart = String(remainder[toRange.upperBound...])
        guard let from = sanitizeSquare(fromPart),
              let to = sanitizeSquare(toPart) else { return nil }
        return from + to
    }
    
    private static func pieceAufMoveNotations(compact: String, prefix: String, markers: [String]) -> [String] {
        guard let marker = markers.first(where: { compact.hasPrefix($0) }) else { return [] }
        let remainder = String(compact.dropFirst(marker.count))
        guard let aufRange = remainder.range(of: "auf") else { return [] }
        
        let fromPart = String(remainder[..<aufRange.lowerBound])
        var afterAuf = String(remainder[aufRange.upperBound...])
        
        if let secondMarker = markers.first(where: { afterAuf.hasPrefix($0) }) {
            afterAuf = String(afterAuf.dropFirst(secondMarker.count))
        }
        
        guard fromPart.count == 2,
              afterAuf.count == 2,
              sanitizeSquare(fromPart) != nil,
              sanitizeSquare(afterAuf) != nil else {
            return []
        }

        let from = fromPart
        let to = afterAuf
        return [
            from + to,
            prefix + to,
            prefix + disambiguationSuffix(for: from) + to
        ]
    }

    private static func pieceFileAufMoveNotation(compact: String, prefix: String, markers: [String]) -> String? {
        guard let marker = markers.first(where: { compact.hasPrefix($0) }) else { return nil }
        let remainder = String(compact.dropFirst(marker.count))
        let prepositions = ["auf", "nach", "to"]
        guard let prep = prepositions.first(where: { remainder.contains($0) }),
              let prepRange = remainder.range(of: prep) else { return nil }

        let filePart = String(remainder[..<prepRange.lowerBound])
        let toPart = String(remainder[prepRange.upperBound...])
        guard filePart.count == 1,
              let file = filePart.first,
              "abcdefgh".contains(file),
              sanitizeSquare(toPart) != nil else {
            return nil
        }

        return prefix + filePart + toPart
    }

    /// "knightbd7" → Nbd7 (file disambiguation + destination square, no "to").
    private static func pieceFileDisambiguatedTargetNotation(
        compact: String,
        prefix: String,
        markers: [String]
    ) -> String? {
        guard let marker = markers.first(where: { compact.hasPrefix($0) }) else { return nil }
        let remainder = String(compact.dropFirst(marker.count))
        guard let merged = fileDisambiguatedTarget(in: remainder) else { return nil }
        return prefix + merged.file + merged.square
    }

    /// "springer5f3" → N5f3 (rank disambiguation + destination square, no "to").
    private static func pieceRankDisambiguatedTargetNotation(
        compact: String,
        prefix: String,
        markers: [String]
    ) -> String? {
        guard let marker = markers.first(where: { compact.hasPrefix($0) }) else { return nil }
        let remainder = String(compact.dropFirst(marker.count))
        guard let merged = rankDisambiguatedTarget(in: remainder) else { return nil }
        return prefix + merged.rank + merged.square
    }
    
    private static func extractCompactPawnPromotions(from compact: String) -> [String] {
        var moves: [String] = []
        let pieceNames = [
            ("springer|knight|night", "N"),
            ("laufer|laeufer|lauferin|bishop", "B"),
            ("turm|rook|rock|look", "R"),
            ("dame|queen", "Q")
        ]

        for (piecePattern, suffix) in pieceNames {
            let squarePiece = try! Regex("([a-h][18])(?:\(piecePattern))")
            for match in compact.matches(of: squarePiece) {
                let output = String(compact[match.range])
                if output.count >= 2 {
                    moves.append(String(output.prefix(2)) + "=" + suffix)
                }
            }

            let pieceSquare = try! Regex("(?:\(piecePattern))([a-h][18])")
            for match in compact.matches(of: pieceSquare) {
                let output = String(compact[match.range])
                if output.count >= 2 {
                    moves.append(String(output.suffix(2)) + "=" + suffix)
                }
            }
        }

        let capturePromotion = try! Regex("([a-h])(?:schlagt|schlaegt|schagt|nimmt|takes|take|captures|capture)([a-h][18])(?:springer|knight|night|laufer|laeufer|lauferin|bishop|turm|rook|rock|look|dame|queen)")
        if let match = compact.matches(of: capturePromotion).last {
            let output = String(compact[match.range])
            if let parsed = parseCompactCapturePromotion(output) {
                moves.append(parsed)
            }
        }

        return moves
    }

    private static func parseCompactCapturePromotion(_ compact: String) -> String? {
        let verbs = ["schlagt", "schlaegt", "schagt", "nimmt", "takes", "take", "captures", "capture"]
        guard let verb = verbs.first(where: { compact.contains($0) }) else { return nil }

        let pieces: [(String, String)] = [
            ("springer", "N"), ("knight", "N"), ("night", "N"),
            ("laufer", "B"), ("laeufer", "B"), ("lauferin", "B"), ("bishop", "B"),
            ("turm", "R"), ("rook", "R"), ("rock", "R"), ("look", "R"),
            ("dame", "Q"), ("queen", "Q")
        ]

        guard let (pieceName, suffix) = pieces.first(where: { compact.hasSuffix($0.0) }) else { return nil }
        var body = compact
        body.removeLast(pieceName.count)
        let parts = body.components(separatedBy: verb)
        guard parts.count == 2,
              parts[0].count == 1,
              let file = parts[0].first,
              "abcdefgh".contains(file),
              parts[1].count == 2,
              sanitizeSquare(parts[1]) != nil else { return nil }

        return String(file) + "x" + parts[1] + "=" + suffix
    }

    private static func extractCompactPawnCapture(from compact: String) -> String? {
        let verbs = ["schlagt", "schlaegt", "schagt", "nimmt", "takes", "take", "captures", "capture"]
        guard let verb = verbs.first(where: { compact.contains($0) }) else { return nil }
        
        let parts = compact.components(separatedBy: verb)
        guard parts.count == 2 else { return nil }
        
        let sourcePart = parts[0]
        let targetPart = parts[1]
        guard targetPart.count == 2,
              let targetFile = targetPart.first,
              let targetRank = targetPart.last,
              "abcdefgh".contains(targetFile),
              "12345678".contains(targetRank) else {
            return nil
        }
        
        let target = String(targetFile) + String(targetRank)
        
        if sourcePart.count == 1, let file = sourcePart.first, "abcdefgh".contains(file) {
            return String(file) + "x" + target
        }
        
        if sourcePart.count == 2,
           let file = sourcePart.first,
           "abcdefgh".contains(file) {
            return String(file) + "x" + target
        }
        
        return nil
    }
    
    private static func markerNames(for piecePattern: String) -> [String] {
        switch piecePattern {
        case "(?:springer|knight|night)": return ["springer", "knight", "night"]
        case "(?:laufer|laeufer|lauferin|bishop)": return ["laufer", "laeufer", "lauferin", "bishop"]
        case "(?:turm|rook|rock|look)": return ["turm", "rook", "rock", "look"]
        case "(?:dame|queen)": return ["dame", "queen"]
        case "(?:konig|king)": return ["konig", "king"]
        default: return []
        }
    }
    
    private static func pieceCaptureNotation(compact: String, prefix: String, markers: [String]) -> String? {
        guard let marker = markers.first(where: { compact.hasPrefix($0) }) else { return nil }
        let remainder = String(compact.dropFirst(marker.count))
        let captureMarkers = ["schlagt", "schlaegt", "nimmt", "takes", "take", "captures", "capture"]
        guard let captureMarker = captureMarkers.first(where: { remainder.contains($0) }) else { return nil }
        
        let parts = remainder.components(separatedBy: captureMarker)
        guard parts.count == 2 else { return nil }
        
        let fromPart = parts[0]
        let target = parts[1]
        guard target.count == 2, "abcdefgh".contains(target.first!) else { return nil }
        
        if fromPart.isEmpty {
            return prefix + "x" + target
        }
        if fromPart.count == 2, "abcdefgh".contains(fromPart.first!) {
            return prefix + fromPart + "x" + target
        }
        return nil
    }
    
    // MARK: - Helpers
    
    private static func targetSquareCandidates(
        from words: [String],
        verbIndex: Int,
        language: RecognitionLanguage
    ) -> [String] {
        var targetIndex = verbIndex + 1
        while targetIndex < words.count && isMovePreposition(words[targetIndex]) {
            targetIndex += 1
        }
        while targetIndex < words.count && isPieceName(words[targetIndex]) {
            targetIndex += 1
        }
        while targetIndex < words.count && isFillerWord(words[targetIndex], language: language) {
            targetIndex += 1
        }
        guard targetIndex < words.count else { return [] }

        let candidates = squareCandidates(from: words[targetIndex], language: language)
        if !candidates.isEmpty {
            return candidates
        }

        if targetIndex + 1 < words.count {
            let candidates = fileRankSquareCandidates(
                fileToken: words[targetIndex],
                rankToken: words[targetIndex + 1],
                language: language
            )
            if !candidates.isEmpty {
                return candidates
            }
        }

        return []
    }

    private static func isAmbiguousEnglishFileRankUtterance(_ words: [String], language: RecognitionLanguage) -> Bool {
        language == .english && ChessTranscriptNormalizer.isAmbiguousEnglishFileRankUtterance(words)
    }

    private static let ambiguousEnglishFileLetters: [Character] = ["e", "g", "a"]

    private static func sourceFileLetters(from token: String, language: RecognitionLanguage) -> [Character] {
        if token.count == 1, let file = token.first, "abcdefgh".contains(file) {
            return [file]
        }
        if let file = ChessTranscriptNormalizer.spokenFileLetter(for: token, language: language) {
            return [file]
        }
        if language == .english, ChessTranscriptNormalizer.isAmbiguousEnglishFileToken(token) {
            return ambiguousEnglishFileLetters
        }
        return []
    }

    private static func fileRankSquareCandidates(
        fileToken: String,
        rankToken: String,
        language: RecognitionLanguage
    ) -> [String] {
        if let square = combineSquare(file: fileToken, rank: rankToken) {
            return [square]
        }
        guard language == .english,
              ChessTranscriptNormalizer.isAmbiguousEnglishFileToken(fileToken) else {
            return []
        }
        let normalizedRank = ChessTranscriptNormalizer.normalizeSpokenRankToken(rankToken, language: language)
        guard normalizedRank.count == 1, "12345678".contains(normalizedRank) else {
            return []
        }
        return ambiguousEnglishFileLetters.map { String($0) + normalizedRank }
    }
    
    private static func combineSquare(file: String, rank: String) -> String? {
        guard file.count == 1,
              let fileChar = file.first,
              "abcdefgh".contains(fileChar) else {
            return nil
        }
        
        let normalizedRank = normalizeRank(rank)
        guard normalizedRank.count == 1, "12345678".contains(normalizedRank) else {
            return nil
        }
        
        return String(fileChar) + normalizedRank
    }

    /// Repairs split mis-hearings like "f 3 six" → f6, but not "e 2 d4" or "e 2 nach".
    private static func mergedMisheardRankSquare(
        file: Character,
        middleToken: String,
        thirdToken: String,
        language: RecognitionLanguage
    ) -> String? {
        if sanitizeSquare(thirdToken) != nil || isMovePreposition(thirdToken) {
            return nil
        }

        let middleRank = ChessTranscriptNormalizer.normalizeSpokenRankToken(middleToken, language: language)
        guard middleRank.count == 1, "12345678".contains(middleRank),
              let trailingRank = ChessTranscriptNormalizer.spokenRankDigit(for: thirdToken, language: language),
              middleRank != trailingRank else {
            return nil
        }

        return String(file) + trailingRank
    }
    
    private static func sanitizeSquare(_ token: String) -> String? {
        ChessTranscriptNormalizer.normalizeSquareToken(token)
    }

    private static func sanitizeSourceTarget(_ token: String) -> String? {
        let cleaned = token
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        guard cleaned.count == 4 else { return nil }

        let sourcePart = String(cleaned.prefix(2))
        let targetPart = String(cleaned.suffix(2))
        guard let source = sanitizeSquare(sourcePart),
              let target = sanitizeSquare(targetPart) else {
            return nil
        }

        return source + target
    }
    
    private static func normalizeRank(_ token: String) -> String {
        let normalized = ChessTranscriptNormalizer.normalizeSpokenRankToken(token, language: .english)
        if normalized.count == 1, "12345678".contains(normalized) {
            return normalized
        }
        return token.filter(\.isNumber)
    }
    
    private static func isCaptureVerb(_ word: String) -> Bool {
        [
            "takes", "take", "captures", "capture",
            "schlagt", "schlaegt", "schagt", "schaegt", "nimmt"
        ].contains(word.lowercased())
    }

    private static func isFillerWord(_ word: String, language: RecognitionLanguage) -> Bool {
        switch language {
        case .english:
            return ["the", "a", "an"].contains(word.lowercased())
        case .german:
            return ["der", "das", "die", "ein", "eine"].contains(word.lowercased())
        }
    }
    
    private static func isPieceName(_ word: String) -> Bool {
        isEnglishPieceName(word) || isGermanPieceName(word)
    }
    
    private static func isEnglishPieceName(_ word: String) -> Bool {
        ["knight", "night", "bishop", "rook", "rock", "look", "queen", "king", "pawn"].contains(word.lowercased())
    }
    
    private static func isGermanPieceName(_ word: String) -> Bool {
        ["springer", "laufer", "laeufer", "lauferin", "turm", "dame", "konig", "bauer"].contains(word.lowercased())
    }
    
    private static func englishPiecePrefix(for word: String) -> String {
        switch word.lowercased() {
        case "knight", "night": return "N"
        case "bishop": return "B"
        case "rook", "rock", "look": return "R"
        case "queen": return "Q"
        case "king": return "K"
        default: return ""
        }
    }
    
    private static func germanPiecePrefix(for word: String) -> String {
        switch word.lowercased() {
        case "springer": return "N"
        case "laufer", "laeufer", "lauferin": return "B"
        case "turm": return "R"
        case "dame": return "Q"
        case "konig": return "K"
        default: return ""
        }
    }
    
    private static func normalizeEnglishToken(_ word: String) -> String? {
        var move = word.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "x" || $0 == "=" }
        let replacements = [
            "knight": "N", "night": "N", "bishop": "B", "rook": "R", "rock": "R", "look": "R",
            "queen": "Q", "king": "K", "takes": "x", "captures": "x"
        ]
        for (spoken, notation) in replacements {
            move = move.replacingOccurrences(of: spoken, with: notation)
        }
        return isValidMoveNotation(move) ? move : nil
    }
    
    private static func normalizeGermanToken(_ word: String) -> String? {
        var move = word.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "x" || $0 == "=" }
        
        if move.count == 2,
           let file = move.first,
           let rank = move.last,
           "abcdefgh".contains(file),
           rank.isNumber {
            return move
        }
        
        if move.hasPrefix("s") && move.count >= 2 { move = "N" + String(move.dropFirst()) }
        else if move.hasPrefix("l") && move.count >= 2 { move = "B" + String(move.dropFirst()) }
        else if move.hasPrefix("t") && move.count >= 2 { move = "R" + String(move.dropFirst()) }
        else if move.hasPrefix("d") && move.count >= 2 { move = "Q" + String(move.dropFirst()) }
        
        return isValidMoveNotation(move) ? move : nil
    }
    
    private static func isValidMoveNotation(_ notation: String) -> Bool {
        let lowered = notation.lowercased()
        let pattern = #/^(o-o(-o)?|[a-h](?:[1-8])?x[a-h][1-8](=[nbrqk])?|[a-h][1-8](=[nbrqk])?|[nbrqk]?[a-h]?[1-8]?x?[a-h][1-8](=?[nbrqk])?|[a-h][1-8]x?[a-h][1-8](=?[nbrqk])?|[nbrqk]?[a-h][1-8]x?[a-h][1-8](=?[nbrqk])?)$/#
        return lowered.contains(pattern)
    }
    
    static func isCastlingPhrase(_ text: String, language: RecognitionLanguage) -> Bool {
        extractCastle(from: text, language: language) != nil
    }
}
