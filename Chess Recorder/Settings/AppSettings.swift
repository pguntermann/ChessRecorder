//
//  AppSettings.swift
//  Chess Recorder
//

import SwiftUI

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    
    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    init(_ color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
    }
    
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct AppSettings: Codable, Equatable {
    var boardSizePercent: Double
    var pieceSizePercent: Double
    var lightSquareColor: CodableColor
    var darkSquareColor: CodableColor
    var defaultLanguage: String
    var coordinateColor: CodableColor
    var coordinateFontName: String
    var coordinateFontSize: Double
    var showCoordinates: Bool
    var coordinatesOutsideBoard: Bool
    var moveAnimationDuration: Double
    var gameSwitchAnimationEnabled: Bool
    var dictationPauseSeconds: Double
    var touchInputEnabled: Bool
    var touchInputHighlightColor: CodableColor
    var showLastMoveArrow: Bool
    var lastMoveArrowColor: CodableColor
    var engineAnalysisVisible: Bool
    var engineAnalysisDepth: Double
    var engineAnalysisShowEvaluationBar: Bool
    var engineAnalysisUseAlgebraicNotation: Bool
    var engineAnalysisShowBoardArrow: Bool
    var engineAnalysisArrowColor: CodableColor
    var moveAssessmentEnabled: Bool
    var moveAssessmentDepth: Double
    var moveAssessmentInaccuracyColor: CodableColor
    var moveAssessmentMistakeColor: CodableColor
    var moveAssessmentBlunderColor: CodableColor
    var moveAssessmentMissColor: CodableColor
    var openingNameVisible: Bool
    var openingBookMiniBoardSide: Double
    var openingBookMiniBoardFollowsOrientation: Bool
    var pgnEvent: String
    var pgnSite: String
    var pgnWhite: String
    var pgnBlack: String
    var pgnHideHeaderTags: Bool
    var pgnIncludeMoveAssessmentSymbols: Bool
    var pgnShowAccuracySummary: Bool

    static let defaultPGNEvent = "Chess Recorder"
    
    enum CodingKeys: String, CodingKey {
        case boardSizePercent
        case pieceSizePercent
        case lightSquareColor
        case darkSquareColor
        case defaultLanguage
        case coordinateColor
        case coordinateFontName
        case coordinateFontSize
        case showCoordinates
        case coordinatesOutsideBoard
        case moveAnimationDuration
        case gameSwitchAnimationEnabled
        case dictationPauseSeconds
        case touchInputEnabled
        case touchInputHighlightColor
        case showLastMoveArrow
        case lastMoveArrowColor
        case engineAnalysisVisible
        case engineAnalysisDepth
        case engineAnalysisShowEvaluationBar
        case engineAnalysisUseAlgebraicNotation
        case engineAnalysisShowBoardArrow
        case engineAnalysisArrowColor
        case moveAssessmentEnabled
        case moveAssessmentDepth
        case moveAssessmentInaccuracyColor
        case moveAssessmentMistakeColor
        case moveAssessmentBlunderColor
        case moveAssessmentMissColor
        case openingNameVisible
        case openingBookMiniBoardSide
        case openingBookMiniBoardFollowsOrientation
        case pgnEvent
        case pgnSite
        case pgnWhite
        case pgnBlack
        case pgnHideHeaderTags
        case pgnIncludeMoveAssessmentSymbols
        case pgnShowAccuracySummary
    }
    
    init(
        boardSizePercent: Double = 1.0,
        pieceSizePercent: Double,
        lightSquareColor: CodableColor,
        darkSquareColor: CodableColor,
        defaultLanguage: String,
        coordinateColor: CodableColor,
        coordinateFontName: String,
        coordinateFontSize: Double,
        showCoordinates: Bool = true,
        coordinatesOutsideBoard: Bool = true,
        moveAnimationDuration: Double,
        gameSwitchAnimationEnabled: Bool = true,
        dictationPauseSeconds: Double = 0.9,
        touchInputEnabled: Bool = true,
        touchInputHighlightColor: CodableColor = CodableColor(red: 0, green: 0.478, blue: 1),
        showLastMoveArrow: Bool = true,
        lastMoveArrowColor: CodableColor = CodableColor(red: 0.85, green: 0.65, blue: 0.1),
        engineAnalysisVisible: Bool = true,
        engineAnalysisDepth: Double = 18,
        engineAnalysisShowEvaluationBar: Bool = false,
        engineAnalysisUseAlgebraicNotation: Bool = false,
        engineAnalysisShowBoardArrow: Bool = false,
        engineAnalysisArrowColor: CodableColor = CodableColor(red: 0, green: 0.478, blue: 1),
        moveAssessmentEnabled: Bool = true,
        moveAssessmentDepth: Double = 14,
        moveAssessmentInaccuracyColor: CodableColor = AppSettings.defaultMoveAssessmentInaccuracyColor,
        moveAssessmentMistakeColor: CodableColor = AppSettings.defaultMoveAssessmentMistakeColor,
        moveAssessmentBlunderColor: CodableColor = AppSettings.defaultMoveAssessmentBlunderColor,
        moveAssessmentMissColor: CodableColor = AppSettings.defaultMoveAssessmentMissColor,
        openingNameVisible: Bool = true,
        openingBookMiniBoardSide: Double = AppSettings.defaultOpeningBookMiniBoardSide,
        openingBookMiniBoardFollowsOrientation: Bool = true,
        pgnEvent: String = AppSettings.defaultPGNEvent,
        pgnSite: String = "?",
        pgnWhite: String = "?",
        pgnBlack: String = "?",
        pgnHideHeaderTags: Bool = true,
        pgnIncludeMoveAssessmentSymbols: Bool = false,
        pgnShowAccuracySummary: Bool = true
    ) {
        self.boardSizePercent = boardSizePercent
        self.pieceSizePercent = pieceSizePercent
        self.lightSquareColor = lightSquareColor
        self.darkSquareColor = darkSquareColor
        self.defaultLanguage = defaultLanguage
        self.coordinateColor = coordinateColor
        self.coordinateFontName = coordinateFontName
        self.coordinateFontSize = coordinateFontSize
        self.showCoordinates = showCoordinates
        self.coordinatesOutsideBoard = coordinatesOutsideBoard
        self.moveAnimationDuration = moveAnimationDuration
        self.gameSwitchAnimationEnabled = gameSwitchAnimationEnabled
        self.dictationPauseSeconds = dictationPauseSeconds
        self.touchInputEnabled = touchInputEnabled
        self.touchInputHighlightColor = touchInputHighlightColor
        self.showLastMoveArrow = showLastMoveArrow
        self.lastMoveArrowColor = lastMoveArrowColor
        self.engineAnalysisVisible = engineAnalysisVisible
        self.engineAnalysisDepth = engineAnalysisDepth
        self.engineAnalysisShowEvaluationBar = engineAnalysisShowEvaluationBar
        self.engineAnalysisUseAlgebraicNotation = engineAnalysisUseAlgebraicNotation
        self.engineAnalysisShowBoardArrow = engineAnalysisShowBoardArrow
        self.engineAnalysisArrowColor = engineAnalysisArrowColor
        self.moveAssessmentEnabled = moveAssessmentEnabled
        self.moveAssessmentDepth = moveAssessmentDepth
        self.moveAssessmentInaccuracyColor = moveAssessmentInaccuracyColor
        self.moveAssessmentMistakeColor = moveAssessmentMistakeColor
        self.moveAssessmentBlunderColor = moveAssessmentBlunderColor
        self.moveAssessmentMissColor = moveAssessmentMissColor
        self.openingNameVisible = openingNameVisible
        self.openingBookMiniBoardSide = openingBookMiniBoardSide
        self.openingBookMiniBoardFollowsOrientation = openingBookMiniBoardFollowsOrientation
        self.pgnEvent = pgnEvent
        self.pgnSite = pgnSite
        self.pgnWhite = pgnWhite
        self.pgnBlack = pgnBlack
        self.pgnHideHeaderTags = pgnHideHeaderTags
        self.pgnIncludeMoveAssessmentSymbols = pgnIncludeMoveAssessmentSymbols
        self.pgnShowAccuracySummary = pgnShowAccuracySummary
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boardSizePercent = try container.decodeIfPresent(Double.self, forKey: .boardSizePercent) ?? 1.0
        pieceSizePercent = try container.decode(Double.self, forKey: .pieceSizePercent)
        lightSquareColor = try container.decode(CodableColor.self, forKey: .lightSquareColor)
        darkSquareColor = try container.decode(CodableColor.self, forKey: .darkSquareColor)
        defaultLanguage = try container.decode(String.self, forKey: .defaultLanguage)
        coordinateColor = try container.decode(CodableColor.self, forKey: .coordinateColor)
        coordinateFontName = try container.decode(String.self, forKey: .coordinateFontName)
        coordinateFontSize = try container.decode(Double.self, forKey: .coordinateFontSize)
        showCoordinates = try container.decodeIfPresent(Bool.self, forKey: .showCoordinates) ?? true
        coordinatesOutsideBoard = try container.decodeIfPresent(Bool.self, forKey: .coordinatesOutsideBoard) ?? true
        moveAnimationDuration = try container.decodeIfPresent(Double.self, forKey: .moveAnimationDuration) ?? 0.35
        gameSwitchAnimationEnabled = try container.decodeIfPresent(Bool.self, forKey: .gameSwitchAnimationEnabled) ?? true
        dictationPauseSeconds = try container.decodeIfPresent(Double.self, forKey: .dictationPauseSeconds) ?? 0.9
        touchInputEnabled = try container.decodeIfPresent(Bool.self, forKey: .touchInputEnabled) ?? true
        touchInputHighlightColor = try container.decodeIfPresent(CodableColor.self, forKey: .touchInputHighlightColor)
            ?? CodableColor(red: 0, green: 0.478, blue: 1)
        showLastMoveArrow = try container.decodeIfPresent(Bool.self, forKey: .showLastMoveArrow) ?? true
        lastMoveArrowColor = try container.decodeIfPresent(CodableColor.self, forKey: .lastMoveArrowColor)
            ?? CodableColor(red: 0.85, green: 0.65, blue: 0.1)
        engineAnalysisVisible = try container.decodeIfPresent(Bool.self, forKey: .engineAnalysisVisible) ?? true
        engineAnalysisDepth = try container.decodeIfPresent(Double.self, forKey: .engineAnalysisDepth) ?? 18
        if let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self),
           (try? legacyContainer.decodeIfPresent(Bool.self, forKey: .engineAnalysisUnlimitedDepth)) == true {
            engineAnalysisDepth = Self.uncappedEngineAnalysisDepth
        }
        engineAnalysisShowEvaluationBar = try container.decodeIfPresent(Bool.self, forKey: .engineAnalysisShowEvaluationBar) ?? false
        engineAnalysisUseAlgebraicNotation = try container.decodeIfPresent(Bool.self, forKey: .engineAnalysisUseAlgebraicNotation) ?? false
        engineAnalysisShowBoardArrow = try container.decodeIfPresent(Bool.self, forKey: .engineAnalysisShowBoardArrow) ?? false
        engineAnalysisArrowColor = try container.decodeIfPresent(CodableColor.self, forKey: .engineAnalysisArrowColor)
            ?? CodableColor(red: 0, green: 0.478, blue: 1)
        moveAssessmentEnabled = try container.decodeIfPresent(Bool.self, forKey: .moveAssessmentEnabled) ?? true
        moveAssessmentDepth = try container.decodeIfPresent(Double.self, forKey: .moveAssessmentDepth) ?? 14
        moveAssessmentInaccuracyColor = try container.decodeIfPresent(CodableColor.self, forKey: .moveAssessmentInaccuracyColor)
            ?? Self.defaultMoveAssessmentInaccuracyColor
        moveAssessmentMistakeColor = try container.decodeIfPresent(CodableColor.self, forKey: .moveAssessmentMistakeColor)
            ?? Self.defaultMoveAssessmentMistakeColor
        moveAssessmentBlunderColor = try container.decodeIfPresent(CodableColor.self, forKey: .moveAssessmentBlunderColor)
            ?? Self.defaultMoveAssessmentBlunderColor
        moveAssessmentMissColor = try container.decodeIfPresent(CodableColor.self, forKey: .moveAssessmentMissColor)
            ?? Self.defaultMoveAssessmentMissColor
        openingNameVisible = try container.decodeIfPresent(Bool.self, forKey: .openingNameVisible) ?? true
        openingBookMiniBoardSide = try container.decodeIfPresent(Double.self, forKey: .openingBookMiniBoardSide)
            ?? Self.defaultOpeningBookMiniBoardSide
        openingBookMiniBoardFollowsOrientation = try container.decodeIfPresent(
            Bool.self,
            forKey: .openingBookMiniBoardFollowsOrientation
        ) ?? true
        pgnEvent = try container.decodeIfPresent(String.self, forKey: .pgnEvent) ?? Self.defaultPGNEvent
        pgnSite = try container.decodeIfPresent(String.self, forKey: .pgnSite) ?? "?"
        pgnWhite = try container.decodeIfPresent(String.self, forKey: .pgnWhite) ?? "?"
        pgnBlack = try container.decodeIfPresent(String.self, forKey: .pgnBlack) ?? "?"
        pgnHideHeaderTags = try container.decodeIfPresent(Bool.self, forKey: .pgnHideHeaderTags) ?? true
        pgnIncludeMoveAssessmentSymbols = try container.decodeIfPresent(Bool.self, forKey: .pgnIncludeMoveAssessmentSymbols) ?? false
        pgnShowAccuracySummary = try container.decodeIfPresent(Bool.self, forKey: .pgnShowAccuracySummary) ?? true
    }
    
    var pgnMetadata: PGNMetadata {
        PGNMetadata(
            event: pgnEvent.isEmpty ? Self.defaultPGNEvent : pgnEvent,
            site: pgnSite.isEmpty ? "?" : pgnSite,
            white: pgnWhite.isEmpty ? "?" : pgnWhite,
            black: pgnBlack.isEmpty ? "?" : pgnBlack
        )
    }
    
    var defaultRecognitionLanguage: RecognitionLanguage {
        RecognitionLanguage(rawValue: defaultLanguage) ?? .english
    }
    
    static let `default` = AppSettings(
        pieceSizePercent: 0.9,
        lightSquareColor: CodableColor(red: 0.86, green: 0.93, blue: 0.98),
        darkSquareColor: CodableColor(red: 0.36, green: 0.52, blue: 0.71),
        defaultLanguage: RecognitionLanguage.english.rawValue,
        coordinateColor: CodableColor(red: 0.35, green: 0.38, blue: 0.42),
        coordinateFontName: "",
        coordinateFontSize: 14,
        showCoordinates: true,
        coordinatesOutsideBoard: true,
        moveAnimationDuration: 0.35,
        gameSwitchAnimationEnabled: true,
        dictationPauseSeconds: 0.9,
        touchInputEnabled: true,
        touchInputHighlightColor: CodableColor(red: 0, green: 0.478, blue: 1),
        showLastMoveArrow: true,
        lastMoveArrowColor: CodableColor(red: 0.85, green: 0.65, blue: 0.1),
        engineAnalysisVisible: true,
        engineAnalysisDepth: 18,
        engineAnalysisShowEvaluationBar: false,
        engineAnalysisUseAlgebraicNotation: true,
        engineAnalysisShowBoardArrow: true,
        engineAnalysisArrowColor: CodableColor(red: 0, green: 0.478, blue: 1),
        moveAssessmentEnabled: true,
        moveAssessmentDepth: 14,
        moveAssessmentInaccuracyColor: defaultMoveAssessmentInaccuracyColor,
        moveAssessmentMistakeColor: defaultMoveAssessmentMistakeColor,
        moveAssessmentBlunderColor: defaultMoveAssessmentBlunderColor,
        moveAssessmentMissColor: defaultMoveAssessmentMissColor,
        openingNameVisible: true,
        openingBookMiniBoardSide: defaultOpeningBookMiniBoardSide,
        openingBookMiniBoardFollowsOrientation: true,
        pgnEvent: defaultPGNEvent,
        pgnSite: "?",
        pgnWhite: "?",
        pgnBlack: "?",
        pgnHideHeaderTags: true,
        pgnIncludeMoveAssessmentSymbols: false,
        pgnShowAccuracySummary: true
    )

    static var bundled: AppSettings? {
        guard let url = Bundle.main.url(forResource: "DefaultSettings", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

private enum LegacyCodingKeys: String, CodingKey {
    case engineAnalysisUnlimitedDepth
}

@Observable
final class SettingsStore {
    private(set) var settings: AppSettings
    
    private let settingsURL: URL
    
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settingsURL = directory.appending(path: "settings.json")
        
        if let loaded = Self.load(from: settingsURL) {
            settings = loaded
        } else if let bundled = AppSettings.bundled {
            settings = bundled
            save()
        } else {
            settings = .default
            save()
        }
    }
    
    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        save()
    }
    
    func resetToDefaults() {
        if let bundled = AppSettings.bundled {
            settings = bundled
        } else {
            settings = .default
        }
        save()
    }
    
    private func save() {
        do {
            let data = try JSONEncoder.prettyPrinted.encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            print("SettingsStore: failed to save — \(error.localizedDescription)")
        }
    }
    
    private static func load(from url: URL) -> AppSettings? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension AppSettings {
    static let defaultMoveAssessmentInaccuracyColor = CodableColor(red: 0.95, green: 0.78, blue: 0.2)
    static let defaultMoveAssessmentMistakeColor = CodableColor(red: 0.95, green: 0.45, blue: 0.2)
    static let defaultMoveAssessmentBlunderColor = CodableColor(red: 0.9, green: 0.2, blue: 0.2)
    static let defaultMoveAssessmentMissColor = CodableColor(red: 1.0, green: 0.45, blue: 0.75)
    static let defaultOpeningBookMiniBoardSide = 72.0

    static let uncappedEngineAnalysisDepth = 31.0

    var isEngineAnalysisUncapped: Bool {
        engineAnalysisDepth >= Self.uncappedEngineAnalysisDepth
    }

    var cappedEngineAnalysisDepth: Int {
        Int(min(max(engineAnalysisDepth, 1), 30))
    }

    var cappedMoveAssessmentDepth: Int {
        Int(min(max(moveAssessmentDepth, 1), 30))
    }

    var moveAssessmentColors: MoveAssessmentColors {
        MoveAssessmentColors(settings: self)
    }

    var moveAssessmentColorsCacheKey: String {
        [
            moveAssessmentInaccuracyColor,
            moveAssessmentMistakeColor,
            moveAssessmentBlunderColor,
            moveAssessmentMissColor
        ]
        .map { "\($0.red),\($0.green),\($0.blue),\($0.alpha)" }
        .joined(separator: "|")
    }

    var cappedOpeningBookMiniBoardSide: CGFloat {
        CGFloat(min(max(openingBookMiniBoardSide, 48), 144))
    }

    var usesOutsideCoordinates: Bool {
        showCoordinates && coordinatesOutsideBoard
    }

    func coordinateFont(boardScale: Double = 1) -> Font {
        let size = coordinateFontSize * boardScale
        if coordinateFontName.isEmpty {
            return .system(size: size)
        }
        return .custom(coordinateFontName, size: size)
    }
}
