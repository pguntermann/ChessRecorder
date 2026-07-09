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
        personalVocabulary: PersonalVocabularyStore? = nil
    ) -> [String] {
        let normalized = normalizeTranscript(text, language: language, personalVocabulary: personalVocabulary)
        let allTokens = coalesceTokens(tokenize(normalized), language: language)

        // Specific castling phrases must win over generic personal phrases like "rochade" -> O-O.
        if let specificCastle = extractSpecificCastling(from: normalized, language: language) {
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

        if let personalVocabulary {
            append(personalVocabulary.candidateMoves(for: normalized, language: language))
        }

        var interpreted: [String] = []
        // Always interpret the trailing phrase — ASR accumulates old failed attempts.
        let windowSizes = [10, 8, 6, 4, 3, 2, 1].filter { $0 <= allTokens.count }
        for size in windowSizes {
            let tokens = Array(allTokens.suffix(size))
            let phrase = tokens.joined(separator: " ")
            let tokenResults = candidatesFromTokens(tokens, normalized: phrase, language: language)
            if !tokenResults.isEmpty {
                interpreted = tokenResults
                break
            }
        }

        // Prefer parsed moves over learned shortcuts when both are available.
        let combined = deduplicatedMoves([interpreted, results].flatMap { $0 })
        if language == .german {
            return expandGermanFileConfusionCandidates(combined)
        }
        return combined
    }

    /// Adds e/g/a file variants — German ASR often confuses the short "e" sound.
    private static func expandGermanFileConfusionCandidates(_ moves: [String]) -> [String] {
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
    
    private static func candidatesFromTokens(
        _ tokens: [String],
        normalized: String,
        language: RecognitionLanguage
    ) -> [String] {
        var results: [String] = []
        var seen = Set<String>()
        
        func add(_ move: String?) {
            guard let move, isValidMoveNotation(move), seen.insert(move).inserted else { return }
            results.append(move)
        }
        
        let hasCaptureVerb = tokens.contains(where: isCaptureVerb)
        let hasPieceName = tokens.contains(where: isPieceName)
        
        switch language {
        case .english:
            add(extractCastle(from: normalized, language: language))
            for move in extractPatterns(from: normalized, allowBareSquares: !hasPieceName && !hasCaptureVerb) { add(move) }
            for move in extractDisambiguatedPieceMoves(from: tokens, piecePrefix: englishPiecePrefix, language: language) { add(move) }
            for move in extractPieceSourceTarget(from: tokens, piecePrefix: englishPiecePrefix) { add(move) }
            for move in extractPieceCaptures(from: tokens, piecePrefix: englishPiecePrefix) { add(move) }
            for move in extractPawnCaptures(from: tokens) { add(move) }
            for move in extractPieceToSquare(from: tokens, piecePrefix: englishPiecePrefix) { add(move) }
            for move in extractSpacedSquares(from: tokens) { add(move) }
            if !hasCaptureVerb && !hasPieceName {
                add(latestSquare(from: tokens, normalize: normalizeEnglishToken))
                add(normalizeEnglishToken(tokens.last ?? ""))
            }
        case .german:
            add(extractCastle(from: normalized, language: language))
            for move in extractPatterns(from: normalized, allowBareSquares: !hasPieceName && !hasCaptureVerb) { add(move) }
            for move in extractDisambiguatedPieceMoves(from: tokens, piecePrefix: germanPiecePrefix, language: language) { add(move) }
            for move in extractPieceSourceTarget(from: tokens, piecePrefix: germanPiecePrefix) { add(move) }
            for move in extractPieceCaptures(from: tokens, piecePrefix: germanPiecePrefix) { add(move) }
            for move in extractPawnCaptures(from: tokens) { add(move) }
            for move in extractPieceToSquare(from: tokens, piecePrefix: germanPiecePrefix) { add(move) }
            for move in extractSpacedSquares(from: tokens) { add(move) }
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
        personalVocabulary: PersonalVocabularyStore?
    ) -> String {
        let normalized = ChessTranscriptNormalizer.normalizeForPhraseMatching(text, language: language)
        return personalVocabulary?.applyCorrections(to: normalized, language: language) ?? normalized
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
               "abcdefgh".contains(file) {
                let middleRank = ChessTranscriptNormalizer.normalizeSpokenRankToken(words[index + 1], language: language)
                let trailingRank = ChessTranscriptNormalizer.spokenRankDigit(for: words[index + 2], language: language)
                if middleRank.count == 1,
                   "12345678".contains(middleRank),
                   let trailingRank,
                   middleRank != trailingRank {
                    result.append(String(file) + trailingRank)
                    index += 3
                    continue
                }
            }

            if index + 1 < words.count,
               let square = combineSquare(file: words[index], rank: words[index + 1]) {
                result.append(square)
                index += 2
                continue
            }
            
            if let square = sanitizeSquare(words[index]) {
                if index + 1 < words.count,
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
            !stopWords(for: language).contains(word)
        }
    }
    
    private static func stopWords(for language: RecognitionLanguage) -> Set<String> {
        switch language {
        case .english:
            return ["hey", "siri", "the", "a", "an", "to", "and", "or", "on"]
        case .german:
            return ["hey", "siri", "der", "das", "ein", "eine", "und", "oder"]
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
            if matchesAny(normalized, phrases: [
                "castle queenside", "castles queenside", "castle long", "castles long",
                "queenside castle", "long castle"
            ]) {
                return "O-O-O"
            }
            if matchesAny(normalized, phrases: [
                "castle kingside", "castles kingside", "castle short", "castles short",
                "kingside castle", "short castle"
            ]) {
                return "O-O"
            }
        case .german:
            if matchesAny(normalized, phrases: [
                "lang rochiert", "gross rochiert", "groß rochiert",
                "lange rochade", "große rochade", "grosse rochade", "gross rochade",
                "groß rochade"
            ]) {
                return "O-O-O"
            }
            if matchesAny(normalized, phrases: [
                "kurz rochiert", "kleine rochade", "klein rochade", "kurze rochade",
                "kurz rochade"
            ]) {
                return "O-O"
            }
        }
        return nil
    }
    
    private static func matchesAny(_ text: String, phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
    
    private static func extractPieceCaptures(
        from words: [String],
        piecePrefix: (String) -> String
    ) -> [String] {
        guard words.count >= 3 else { return [] }
        
        var moves: [String] = []
        
        for verbIndex in stride(from: words.count - 2, through: 1, by: -1) {
            guard isCaptureVerb(words[verbIndex]) else { continue }
            
            guard let target = targetSquare(from: words, verbIndex: verbIndex) else { continue }
            
            if verbIndex >= 2, isPieceName(words[verbIndex - 2]),
               let fromSquare = sanitizeSquare(words[verbIndex - 1]) {
                let piece = piecePrefix(words[verbIndex - 2])
                if !piece.isEmpty {
                    moves.append(piece + fromSquare + "x" + target)
                }
            }
            
            if isPieceName(words[verbIndex - 1]) {
                let piece = piecePrefix(words[verbIndex - 1])
                if !piece.isEmpty {
                    moves.append(piece + "x" + target)
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

            if let move = extractPieceFileOrRankMove(
                from: words,
                start: start,
                piece: piece,
                language: language
            ) {
                moves.append(move)
            }
            
            guard start + 1 < words.count,
                  let from = sanitizeSquare(words[start + 1]) else { continue }
            
            var cursor = start + 2
            if cursor < words.count && isMovePreposition(words[cursor]) {
                cursor += 1
            }
            if cursor < words.count && isPieceName(words[cursor]) {
                cursor += 1
            }
            guard cursor < words.count, let to = sanitizeSquare(words[cursor]) else { continue }
            
            moves.append(from + to)
            moves.append(piece + to)
            moves.append(piece + disambiguationSuffix(for: from) + to)

            if start + 2 < words.count,
               isCaptureVerb(words[start + 2]) || (start + 3 < words.count && isCaptureVerb(words[start + 3])) {
                moves.append(piece + from + "x" + to)
                moves.append(piece + disambiguationSuffix(for: from) + "x" + to)
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
    ) -> String? {
        guard start + 2 < words.count else { return nil }

        let disambiguator = words[start + 1]
        guard let suffix = disambiguationSuffix(forToken: disambiguator, language: language) else {
            return nil
        }

        var cursor = start + 2
        if cursor < words.count && isMovePreposition(words[cursor]) {
            cursor += 1
        }
        if cursor < words.count && isPieceName(words[cursor]) {
            cursor += 1
        }
        guard cursor < words.count, let to = sanitizeSquare(words[cursor]) else { return nil }

        return piece + suffix + to
    }

    private static func disambiguationSuffix(for square: String) -> String {
        guard square.count == 2 else { return square }
        return String(square.prefix(1))
    }

    private static func disambiguationSuffix(forToken token: String, language: RecognitionLanguage) -> String? {
        if token.count == 1, let file = token.first, "abcdefgh".contains(file) {
            return String(file)
        }
        let rank = ChessTranscriptNormalizer.normalizeSpokenRankToken(token, language: language)
        if rank.count == 1, "12345678".contains(rank) {
            return rank
        }
        return nil
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

            if let square = sanitizeSquare(words[index]) {
                moves.append(piece + square)
                continue
            }

            if index + 1 < words.count,
               isMovePreposition(words[index]),
               let square = sanitizeSquare(words[index + 1]) {
                moves.append(piece + square)
            }
        }
        return moves
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
    
    private static func extractPawnCaptures(from words: [String]) -> [String] {
        guard words.count >= 3 else { return [] }
        
        var moves: [String] = []
        
        for verbIndex in stride(from: words.count - 2, through: 1, by: -1) {
            guard isCaptureVerb(words[verbIndex]) else { continue }
            guard let target = targetSquare(from: words, verbIndex: verbIndex) else { continue }
            
            let source = words[verbIndex - 1]
            
            if source.count == 1, let file = source.first, "abcdefgh".contains(file) {
                moves.append(String(file) + "x" + target)
            } else if let fromSquare = sanitizeSquare(source) {
                moves.append(fromSquare + target)
                moves.append(String(fromSquare.first!) + "x" + target)
                if source.count == 2 {
                    moves.append(fromSquare + "x" + target)
                }
            }
        }
        
        return moves
    }
    
    private static func extractSpacedSquares(from words: [String]) -> [String] {
        guard words.count >= 2 else { return [] }
        
        if let square = combineSquare(file: words[words.count - 2], rank: words[words.count - 1]) {
            return [square]
        }
        return []
    }
    
    private static func extractPatterns(from text: String, allowBareSquares: Bool) -> [String] {
        let compact = text.replacingOccurrences(of: " ", with: "")
        var moves: [String] = []
        
        let captureVerbs = "(?:schlagt|schlaegt|schagt|nimmt|takes|take|captures|capture)"
        
        let piecePatterns: [(String, String)] = [
            ("(?:springer|knight|night)", "N"),
            ("(?:laufer|laeufer|lauferin|bishop)", "B"),
            ("(?:turm|rook)", "R"),
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
        }
        
        if let move = extractCompactPawnCapture(from: compact) {
            moves.append(move)
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
        case "(?:turm|rook)": return ["turm", "rook"]
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
    
    private static func targetSquare(from words: [String], verbIndex: Int) -> String? {
        var targetIndex = verbIndex + 1
        while targetIndex < words.count && isMovePreposition(words[targetIndex]) {
            targetIndex += 1
        }
        while targetIndex < words.count && isPieceName(words[targetIndex]) {
            targetIndex += 1
        }
        guard targetIndex < words.count else { return nil }
        
        if let square = sanitizeSquare(words[targetIndex]) {
            return square
        }
        
        if targetIndex + 1 < words.count,
           let square = combineSquare(file: words[targetIndex], rank: words[targetIndex + 1]) {
            return square
        }
        
        return nil
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
    
    private static func sanitizeSquare(_ token: String) -> String? {
        let cleaned = token
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        
        guard cleaned.count == 2,
              let file = cleaned.first,
              let rank = cleaned.last,
              "abcdefgh".contains(file),
              "12345678".contains(rank) else {
            return nil
        }
        
        return String(file) + String(rank)
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
    
    private static func isPieceName(_ word: String) -> Bool {
        isEnglishPieceName(word) || isGermanPieceName(word)
    }
    
    private static func isEnglishPieceName(_ word: String) -> Bool {
        ["knight", "night", "bishop", "rook", "queen", "king", "pawn"].contains(word.lowercased())
    }
    
    private static func isGermanPieceName(_ word: String) -> Bool {
        ["springer", "laufer", "laeufer", "lauferin", "turm", "dame", "konig", "bauer"].contains(word.lowercased())
    }
    
    private static func englishPiecePrefix(for word: String) -> String {
        switch word.lowercased() {
        case "knight", "night": return "N"
        case "bishop": return "B"
        case "rook": return "R"
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
            "knight": "N", "night": "N", "bishop": "B", "rook": "R",
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
        let pattern = #/^(o-o(-o)?|[a-h](?:[1-8])?x[a-h][1-8]|[nbrqk]?[a-h]?[1-8]?x?[a-h][1-8]([nbrqk])?|[a-h][1-8]x?[a-h][1-8]([nbrqk])?|[nbrqk]?[a-h][1-8]x?[a-h][1-8]([nbrqk])?)$/#
        return lowered.contains(pattern)
    }
    
    static func isCastlingPhrase(_ text: String, language: RecognitionLanguage) -> Bool {
        extractCastle(from: text, language: language) != nil
    }
}
