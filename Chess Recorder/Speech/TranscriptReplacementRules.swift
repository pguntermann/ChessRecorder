//
//  TranscriptReplacementRules.swift
//  Chess Recorder
//

import Foundation

enum TranscriptReplacementRules {
  static func rules(
    for language: RecognitionLanguage,
    stage: TranscriptReplacementStage
  ) -> [TranscriptReplacementRule] {
    switch (language, stage) {
    case (.english, .locale):
      return englishLocaleRules()
    case (.german, .locale):
      return germanLocaleRules()
    case (.english, .phraseMatching):
      return englishPhraseMatchingRules()
    case (.german, .phraseMatching):
      return germanPhraseMatchingRules()
    case (.english, .rawASR):
      return []
    case (.german, .rawASR):
      return germanAFileRules()
    }
  }

  // MARK: - English

  private static func englishLocaleRules() -> [TranscriptReplacementRule] {
    let lexicon = ChessSpeechLexicon.lexicon(for: .english)
    return [
      rule("en.knight-digit", #"\b9\b"#, "knight"),
      rule("en.shop-redundant", #"\b(pet|bee|bit|fish|dish|this)\s+shop\s+shop\b"#, "$1 shop"),
      rule("en.shop-dedupe", #"\b(\w+shop)\s+shop\b"#, "$1"),
      rule("en.petshop", #"\bpet\s*shop\b"#, "bishop"),
      rule("en.beeshop", #"\bbee\s*shop\b"#, "bishop"),
      rule("en.bitshop", #"\bbit\s*shop\b"#, "bishop"),
      rule("en.petshop-compact", #"\bpetshop\b"#, "bishop"),
      rule("en.beeshop-compact", #"\bbeeshop\b"#, "bishop"),
      rule("en.bishup", #"\bbishup\b"#, "bishop"),
      rule("en.bishopp", #"\bbishopp\b"#, "bishop"),
      rule("en.bishop-shop", #"\bbishop\s+shop\b"#, "bishop"),
      rule("en.piece-shop", #"\b(bishop|knight|night|rook|queen|king)\s+shop\b"#, "$1"),
      rule("en.brooke", #"\bbrooke\b"#, "rook"),
      rule("en.rock", #"\brock\b"#, "rook"),
      rule("en.look-at-square", #"\b(look|rock)\s+at\s+([a-h][1-8])\b"#, "rook $2"),
      rule(
        "en.look-at-file-rank",
        #"\b(look|rock)\s+at\s+([a-h])\s+(one|two|three|four|five|six|seven|eight|[1-8])\b"#,
        "rook $2 $3"
      ),
      rule("en.look-verb", #"\blook\s+(takes|take|captures|capture|to)\b"#, "rook $1"),
      rule("en.look-square", #"\blook\s+([a-h][1-8])\b"#, "rook $1"),
      rule("en.look-file-verb", #"\blook\s+([a-h])\s+(to|takes|take|captures|capture)\b"#, "rook $1 $2"),
      rule(
        "en.look-file-rank",
        #"\blook\s+([a-h])\s+(one|two|three|four|five|six|seven|eight|[1-8])\b"#,
        "rook $1 $2"
      ),
      rule("en.square-rock-suffix", #"\b([a-h][18])\s+(rock|look)\b"#, "$1 rook"),
      rule("en.rock-square-prefix", #"\b(rock|look)\s+([a-h][18])\b"#, "rook $2"),
      rule("en.knit", #"\bknit\b"#, "knight"),
      rule("en.nite", #"\bnite\b"#, "knight"),
      rule("en.night", #"\bnight\b"#, "knight")
    ]
    + englishFileBeforeRankRules(lexicon: lexicon)
  }

  private static func englishPhraseMatchingRules() -> [TranscriptReplacementRule] {
    let lexicon = ChessSpeechLexicon.lexicon(for: .english)
    return englishDetectsRules(lexicon: lexicon)
      + englishPieceMoveRules(lexicon: lexicon)
      + englishSquareGarbageRules()
      + englishAFileRules()
      + englishPawnCaptureRules(lexicon: lexicon)
      + englishCompactMoveBlobRules()
      + englishInvalidDigitFileRules()
  }

  private static func englishFileBeforeRankRules(
    lexicon: ChessSpeechLexicon.LanguageLexicon
  ) -> [TranscriptReplacementRule] {
    let rank = lexicon.rankPattern
    return [
      rule("en.file-c-rank", #"\b(see|sea|cee|she)\s+(?=\#(rank))\b"#, "c "),
      rule("en.file-b-rank", #"\b(bee|be)\s+(?=\#(rank))\b"#, "b "),
      rule("en.file-d-rank", #"\bdee\s+(?=\#(rank))\b"#, "d "),
      rule("en.file-e-rank", #"\b(he|ee)\s+(?=\#(rank))\b"#, "e "),
      rule("en.file-g-rank", #"\bgee\s+(?=\#(rank))\b"#, "g "),
      rule("en.file-h-rank", #"\b(aitch|each)\s+(?=\#(rank))\b"#, "h "),
      rule("en.file-f-rank", #"\b(eff|ef)\s+(?=\#(rank))\b"#, "f ")
    ]
  }

  private static func englishDetectsRules(
    lexicon: ChessSpeechLexicon.LanguageLexicon
  ) -> [TranscriptReplacementRule] {
    let homophones = (Array(lexicon.spokenFileLetters.keys) + Array(lexicon.ambiguousFileTokens))
      .sorted { $0.count > $1.count }
      .joined(separator: "|")
    let captureTarget = "(?:\(homophones)|[a-h])(?:[1-8]|\\s+(?:\(lexicon.rankPattern)))"
    return [
      rule("en.detects-capture", #"\bdetects\s*(?=\#(captureTarget))"#, "d takes "),
      rule("en.detects-square", #"\bdetects(?=[a-h][1-8]\b)"#, "d takes "),
      rule("en.detect-capture", #"\bdetect\s*(?=\#(captureTarget))"#, "d take "),
      rule("en.detect-square", #"\bdetect(?=[a-h][1-8]\b)"#, "d take "),
      rule("en.d-e-takes", #"\bd\s+e\s+(takes|take|captures|capture)\b"#, "d $1")
    ]
  }

  private static func englishPieceMoveRules(
    lexicon: ChessSpeechLexicon.LanguageLexicon
  ) -> [TranscriptReplacementRule] {
    let pieces = "knight|bishop|rook|queen|king"
    return [
      rule("en.piece-to-be", #"\b(\#(pieces))\s+to\s+(bee|be)\s+"#, "$1 b to "),
      rule("en.piece-be-to", #"\b(\#(pieces))\s+(bee|be)\s+(?=to\b)"#, "$1 b "),
      rule("en.look-at-square-phrase", #"\b(look|rock)\s+at\s+([a-h][1-8])\b"#, "rook $2"),
      rule(
        "en.look-at-file-rank-phrase",
        #"\b(look|rock)\s+at\s+([a-h])\s+(one|two|three|four|five|six|seven|eight|[1-8])\b"#,
        "rook $2 $3"
      )
    ]
  }

  private static func englishPawnCaptureRules(
    lexicon: ChessSpeechLexicon.LanguageLexicon
  ) -> [TranscriptReplacementRule] {
    lexicon.pawnCaptureMishearingPatterns().map { pattern, replacement in
      TranscriptReplacementRule(id: "en.pawn-capture.\(pattern)", pattern: pattern, replacement: replacement)
    }
  }

  private static func englishAFileRules() -> [TranscriptReplacementRule] {
    [
      rule("en.a-hey-siri", #"\b(hey|ay)\s+siri\b"#, "a3"),
      rule("en.a-hey-sir", #"\b(hey|ay)\s+sir\b"#, "a3"),
      rule("en.a-hey-seri", #"\b(hey|ay)\s+seri\b"#, "a3"),
      rule("en.a-hey-sery", #"\b(hey|ay)\s+sery\b"#, "a3"),
      rule("en.a-hey-cery", #"\b(hey|ay)\s+cery\b"#, "a3"),
      rule("en.a-siri", #"\ba\s+siri\b"#, "a3"),
      rule("en.a-sir", #"\ba\s+sir\b"#, "a3"),
      rule("en.a-8-3", #"\b8\s+3\b"#, "a3"),
      rule("en.a-83", #"\b83\b"#, "a3")
    ]
  }

  private static func englishSquareGarbageRules() -> [TranscriptReplacementRule] {
    [
      rule("en.since-we", #"\bsince\s+we\b"#, "c3"),
      rule("en.her-siri", #"\bher\s+siri\b"#, "c3"),
      rule("en.see-we", #"\bsee\s+we\b"#, "c3"),
      rule("en.sea-we", #"\bsea\s+we\b"#, "c3"),
      rule("en.see-three", #"\bsee\s+three\b"#, "c3"),
      rule("en.sea-three", #"\bsea\s+three\b"#, "c3"),
      rule("en.c-tree", #"\bc\s+tree\b"#, "c3"),
      rule("en.see-free", #"\bsee\s+free\b"#, "c3"),
      rule("en.cee-three", #"\bcee\s+three\b"#, "c3"),
      rule("en.sea-only", #"^\s*sea\s*$"#, "c3"),
      rule("en.see-three-only", #"^\s*see\s+three\s*$"#, "c3"),
      rule("en.sea-three-only", #"^\s*sea\s+three\s*$"#, "c3")
    ]
  }

  private static func englishCompactMoveBlobRules() -> [TranscriptReplacementRule] {
    [
      rule("en.blob-knight-full", #"\b9([a-h])([1-8])([a-h])([1-8])\b"#, "knight $1$2 to $3$4"),
      rule("en.blob-knight-partial", #"\b9([a-h])([1-8])2([1-8])\b"#, "knight $1$2 to $3"),
      rule("en.blob-knight-ranks", #"\b9([1-8])2([1-8])\b"#, "knight $1 to $2"),
      rule("en.blob-knight-to-rank", #"\b9([a-h])([1-8])\s+to\s+([1-8])\b"#, "knight $1$2 to $3"),
      rule("en.blob-knight-rank-to-rank", #"\b9([1-8])\s+to\s+([1-8])\b"#, "knight $1 to $2")
    ]
  }

  private static func englishInvalidDigitFileRules() -> [TranscriptReplacementRule] {
    [
      rule("en.invalid-8-rank", #"\b8([1-8])\b"#, "a$1"),
      rule("en.invalid-8-spaced-rank", #"\b8\s+([1-8])\b"#, "a$1")
    ]
  }

  // MARK: - German

  private static func germanLocaleRules() -> [TranscriptReplacementRule] {
    let lexicon = ChessSpeechLexicon.lexicon(for: .german)
    return [
      rule("de.laeufer", #"\blaeufer(in)?\b"#, "laufer$1"),
      rule("de.je-file", #"\bje\s+"#, "e "),
      rule(
        "de.die-rank",
        #"\bdie\s+(?=[1-8]|eins|zwei|drei|vier|funf|fünf|sechs|sieben|acht)\b"#,
        "d "
      ),
      rule(
        "de.die-capture",
        #"\bdie\s+(\#(lexicon.captureVerbPattern))\b"#,
        "d $1"
      ),
      rule(
        "de.square-merged-capture",
        #"([a-h])[1-8]\s+(\#(lexicon.captureVerbPattern))\s"#,
        "$1 $2 "
      )
    ]
    + germanSpokenLetterSpacingRules()
    + germanHFileRules(lexicon: lexicon)
  }

  private static func germanPhraseMatchingRules() -> [TranscriptReplacementRule] {
    germanAFileRules()
  }

  private static func germanSpokenLetterSpacingRules() -> [TranscriptReplacementRule] {
    [
      rule("de.spacing-dee", " dee ", " d "),
      rule("de.spacing-tee", " tee ", " t "),
      rule("de.spacing-bee", " bee ", " b "),
      rule("de.spacing-eh", " eh ", " e ")
    ]
  }

  private static func germanHFileRules(
    lexicon: ChessSpeechLexicon.LanguageLexicon
  ) -> [TranscriptReplacementRule] {
    let pieces = lexicon.piecePattern
    let verbs = lexicon.captureVerbPattern
    let rank = lexicon.rankPattern
    return [
      rule("de.h-piece-haar", #"\b(\#(pieces))haar\b"#, "$1 h"),
      rule("de.h-piece-hache", #"\b(\#(pieces))hache\b"#, "$1 h"),
      rule("de.h-piece-ha-verb", #"\b(\#(pieces))ha\s+(?=auf|nach|\#(verbs))\b"#, "$1 h "),
      rule("de.h-haar-rank", #"\bhaar\s+(?=\#(rank))\b"#, "h "),
      rule("de.h-haar-auf", #"\bhaar\s+auf\b"#, "h auf"),
      rule("de.h-haar-verb", #"\bhaar\s+(\#(verbs))\b"#, "h $1"),
      rule("de.h-ha-rank", #"\bha\s+(?=\#(rank))\b"#, "h "),
      rule("de.h-ha-auf", #"\bha\s+auf\b"#, "h auf"),
      rule("de.h-hache-rank", #"\bhache\s+(?=\#(rank))\b"#, "h "),
      rule("de.h-ache-rank", #"\bache\s+(?=\#(rank))\b"#, "h "),
      rule("de.h-haar-fallback", #"\bhaar\b"#, "h")
    ]
  }

  static func germanAFileRules() -> [TranscriptReplacementRule] {
    let lexicon = ChessSpeechLexicon.lexicon(for: .german)
    let pieces = lexicon.piecePattern
    let verbs = lexicon.captureVerbPattern
    let rank = lexicon.rankPattern
    return [
      rule("de.a-arsch-rank", #"\barsch\s+(?=\#(rank))\b"#, "a "),
      rule("de.a-arsch-verb", #"\barsch\s+(\#(verbs))\b"#, "a $1"),
      rule("de.a-arsch-auf", #"\barsch\s+auf\b"#, "a auf"),
      rule("de.a-arsch-nach", #"\barsch\s+nach\b"#, "a nach"),
      rule("de.a-piece-arsch-rank", #"\b(\#(pieces))\s+(\#(verbs))\s+arsch\s+(?=\#(rank))\b"#, "$1 $2 a "),
      rule("de.a-piece-arsch-square", #"\b(\#(pieces))\s+(\#(verbs))\s+arsch\s+(?=[a-h][1-8]\b)"#, "$1 $2 a "),
      rule("de.a-piece-arsch-tail", #"\b(\#(pieces))\s+(\#(verbs))\s+arsch\s*$"#, "$1 $2 a")
    ]
  }

  private static func rule(
    _ id: String,
    _ pattern: String,
    _ replacement: String
  ) -> TranscriptReplacementRule {
    TranscriptReplacementRule(id: id, pattern: pattern, replacement: replacement)
  }
}
