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
    var pieceSizePercent: Double
    var lightSquareColor: CodableColor
    var darkSquareColor: CodableColor
    var defaultLanguage: String
    var coordinateColor: CodableColor
    var coordinateFontName: String
    var coordinateFontSize: Double
    var moveAnimationDuration: Double
    var dictationPauseSeconds: Double
    var touchInputEnabled: Bool
    var engineAnalysisVisible: Bool
    var engineAnalysisDepth: Double
    var engineAnalysisShowEvaluationBar: Bool
    var engineAnalysisUseAlgebraicNotation: Bool
    var engineAnalysisShowBoardArrow: Bool
    var engineAnalysisArrowColor: CodableColor
    var openingNameVisible: Bool
    var pgnSite: String
    var pgnWhite: String
    var pgnBlack: String
    var pgnHideHeaderTags: Bool
    
    enum CodingKeys: String, CodingKey {
        case pieceSizePercent
        case lightSquareColor
        case darkSquareColor
        case defaultLanguage
        case coordinateColor
        case coordinateFontName
        case coordinateFontSize
        case moveAnimationDuration
        case dictationPauseSeconds
        case touchInputEnabled
        case engineAnalysisVisible
        case engineAnalysisDepth
        case engineAnalysisShowEvaluationBar
        case engineAnalysisUseAlgebraicNotation
        case engineAnalysisShowBoardArrow
        case engineAnalysisArrowColor
        case openingNameVisible
        case pgnSite
        case pgnWhite
        case pgnBlack
        case pgnHideHeaderTags
    }
    
    init(
        pieceSizePercent: Double,
        lightSquareColor: CodableColor,
        darkSquareColor: CodableColor,
        defaultLanguage: String,
        coordinateColor: CodableColor,
        coordinateFontName: String,
        coordinateFontSize: Double,
        moveAnimationDuration: Double,
        dictationPauseSeconds: Double = 0.9,
        touchInputEnabled: Bool = true,
        engineAnalysisVisible: Bool = true,
        engineAnalysisDepth: Double = 10,
        engineAnalysisShowEvaluationBar: Bool = false,
        engineAnalysisUseAlgebraicNotation: Bool = false,
        engineAnalysisShowBoardArrow: Bool = false,
        engineAnalysisArrowColor: CodableColor = CodableColor(red: 0, green: 0.478, blue: 1),
        openingNameVisible: Bool = true,
        pgnSite: String = "?",
        pgnWhite: String = "?",
        pgnBlack: String = "?",
        pgnHideHeaderTags: Bool = true
    ) {
        self.pieceSizePercent = pieceSizePercent
        self.lightSquareColor = lightSquareColor
        self.darkSquareColor = darkSquareColor
        self.defaultLanguage = defaultLanguage
        self.coordinateColor = coordinateColor
        self.coordinateFontName = coordinateFontName
        self.coordinateFontSize = coordinateFontSize
        self.moveAnimationDuration = moveAnimationDuration
        self.dictationPauseSeconds = dictationPauseSeconds
        self.touchInputEnabled = touchInputEnabled
        self.engineAnalysisVisible = engineAnalysisVisible
        self.engineAnalysisDepth = engineAnalysisDepth
        self.engineAnalysisShowEvaluationBar = engineAnalysisShowEvaluationBar
        self.engineAnalysisUseAlgebraicNotation = engineAnalysisUseAlgebraicNotation
        self.engineAnalysisShowBoardArrow = engineAnalysisShowBoardArrow
        self.engineAnalysisArrowColor = engineAnalysisArrowColor
        self.openingNameVisible = openingNameVisible
        self.pgnSite = pgnSite
        self.pgnWhite = pgnWhite
        self.pgnBlack = pgnBlack
        self.pgnHideHeaderTags = pgnHideHeaderTags
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pieceSizePercent = try container.decode(Double.self, forKey: .pieceSizePercent)
        lightSquareColor = try container.decode(CodableColor.self, forKey: .lightSquareColor)
        darkSquareColor = try container.decode(CodableColor.self, forKey: .darkSquareColor)
        defaultLanguage = try container.decode(String.self, forKey: .defaultLanguage)
        coordinateColor = try container.decode(CodableColor.self, forKey: .coordinateColor)
        coordinateFontName = try container.decode(String.self, forKey: .coordinateFontName)
        coordinateFontSize = try container.decode(Double.self, forKey: .coordinateFontSize)
        moveAnimationDuration = try container.decodeIfPresent(Double.self, forKey: .moveAnimationDuration) ?? 0.35
        dictationPauseSeconds = try container.decodeIfPresent(Double.self, forKey: .dictationPauseSeconds) ?? 0.9
        touchInputEnabled = try container.decodeIfPresent(Bool.self, forKey: .touchInputEnabled) ?? true
        engineAnalysisVisible = try container.decodeIfPresent(Bool.self, forKey: .engineAnalysisVisible) ?? true
        engineAnalysisDepth = try container.decodeIfPresent(Double.self, forKey: .engineAnalysisDepth) ?? 10
        if let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self),
           (try? legacyContainer.decodeIfPresent(Bool.self, forKey: .engineAnalysisUnlimitedDepth)) == true {
            engineAnalysisDepth = Self.uncappedEngineAnalysisDepth
        }
        engineAnalysisShowEvaluationBar = try container.decodeIfPresent(Bool.self, forKey: .engineAnalysisShowEvaluationBar) ?? false
        engineAnalysisUseAlgebraicNotation = try container.decodeIfPresent(Bool.self, forKey: .engineAnalysisUseAlgebraicNotation) ?? false
        engineAnalysisShowBoardArrow = try container.decodeIfPresent(Bool.self, forKey: .engineAnalysisShowBoardArrow) ?? false
        engineAnalysisArrowColor = try container.decodeIfPresent(CodableColor.self, forKey: .engineAnalysisArrowColor)
            ?? CodableColor(red: 0, green: 0.478, blue: 1)
        openingNameVisible = try container.decodeIfPresent(Bool.self, forKey: .openingNameVisible) ?? true
        pgnSite = try container.decodeIfPresent(String.self, forKey: .pgnSite) ?? "?"
        pgnWhite = try container.decodeIfPresent(String.self, forKey: .pgnWhite) ?? "?"
        pgnBlack = try container.decodeIfPresent(String.self, forKey: .pgnBlack) ?? "?"
        pgnHideHeaderTags = try container.decodeIfPresent(Bool.self, forKey: .pgnHideHeaderTags) ?? true
    }
    
    var pgnMetadata: PGNMetadata {
        PGNMetadata(
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
        coordinateColor: CodableColor(red: 0.12, green: 0.22, blue: 0.35),
        coordinateFontName: "",
        coordinateFontSize: 14,
        moveAnimationDuration: 0.35,
        dictationPauseSeconds: 0.9,
        touchInputEnabled: true,
        engineAnalysisVisible: true,
        engineAnalysisDepth: 10,
        engineAnalysisShowEvaluationBar: false,
        engineAnalysisUseAlgebraicNotation: true,
        engineAnalysisShowBoardArrow: true,
        engineAnalysisArrowColor: CodableColor(red: 0, green: 0.478, blue: 1),
        openingNameVisible: true,
        pgnSite: "?",
        pgnWhite: "?",
        pgnBlack: "?",
        pgnHideHeaderTags: true
    )
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
        } else if let bundled = Self.loadBundledDefaults() {
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
        if let bundled = Self.loadBundledDefaults() {
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
    
    private static func loadBundledDefaults() -> AppSettings? {
        guard let url = Bundle.main.url(forResource: "DefaultSettings", withExtension: "json"),
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
    static let uncappedEngineAnalysisDepth = 31.0

    var isEngineAnalysisUncapped: Bool {
        engineAnalysisDepth >= Self.uncappedEngineAnalysisDepth
    }

    var cappedEngineAnalysisDepth: Int {
        Int(min(max(engineAnalysisDepth, 1), 30))
    }

    func coordinateFont() -> Font {
        if coordinateFontName.isEmpty {
            return .system(size: coordinateFontSize)
        }
        return .custom(coordinateFontName, size: coordinateFontSize)
    }
}
