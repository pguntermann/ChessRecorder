//
//  SettingsView.swift
//  Chess Recorder
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settingsStore: SettingsStore
    @Bindable var vocabularyStore: PersonalVocabularyStore
    @Bindable var developerModeStore: DeveloperModeStore
    @Binding var pendingSpeechModelWork: PendingSpeechModelWork
    
    @State private var lightColor: Color
    @State private var darkColor: Color
    @State private var coordinateColor: Color
    @State private var analysisArrowColor: Color
    @State private var selectedLanguage: RecognitionLanguage
    @State private var showingAddPhrase = false
    @State private var showingAddCorrection = false
    @State private var phraseListLanguage: RecognitionLanguage
    
    init(
        settingsStore: SettingsStore,
        vocabularyStore: PersonalVocabularyStore,
        developerModeStore: DeveloperModeStore,
        pendingSpeechModelWork: Binding<PendingSpeechModelWork>
    ) {
        self.settingsStore = settingsStore
        self.vocabularyStore = vocabularyStore
        self.developerModeStore = developerModeStore
        _pendingSpeechModelWork = pendingSpeechModelWork
        let settings = settingsStore.settings
        _lightColor = State(initialValue: settings.lightSquareColor.color)
        _darkColor = State(initialValue: settings.darkSquareColor.color)
        _coordinateColor = State(initialValue: settings.coordinateColor.color)
        _analysisArrowColor = State(initialValue: settings.engineAnalysisArrowColor.color)
        _selectedLanguage = State(initialValue: settings.defaultRecognitionLanguage)
        _phraseListLanguage = State(initialValue: settings.defaultRecognitionLanguage)
    }
    
    var body: some View {
        navigationContent
            .sheet(isPresented: $showingAddPhrase) {
                TeachPhraseView(
                    language: selectedLanguage,
                    initialPhrase: "",
                    attemptedMoves: []
                ) { phrase, move in
                    vocabularyStore.learn(phrase: phrase, moveNotation: move, language: selectedLanguage)
                    scheduleSpeechModelUpdate(for: selectedLanguage)
                }
            }
            .sheet(isPresented: $showingAddCorrection) {
                TeachCorrectionView(language: selectedLanguage) { heard, replacement in
                    vocabularyStore.learnCorrection(heard: heard, replacement: replacement, language: selectedLanguage)
                    scheduleSpeechModelUpdate(for: selectedLanguage)
                }
            }
    }

    private var navigationContent: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(RecognitionLanguage.allCases, id: \.self) { language in
                            Text("\(language.flag) \(language.displayName)").tag(language)
                        }
                    }
                    .onChange(of: selectedLanguage) { _, language in
                        settingsStore.update { $0.defaultLanguage = language.rawValue }
                        requestLanguageChange(language)
                        phraseListLanguage = language
                    }
                    
                    VStack(alignment: .leading) {
                        Text(dictationPauseLabel)
                        Slider(value: Binding(
                            get: { settingsStore.settings.dictationPauseSeconds },
                            set: { newValue in
                                settingsStore.update { $0.dictationPauseSeconds = newValue }
                            }
                        ), in: 0.3...2.0, step: 0.05)
                    }
                } header: {
                    Text("Speech")
                } footer: {
                    Text("How long to wait after you stop speaking before a move is interpreted. A countdown appears in the live transcript while recording.")
                }
                
                Section {
                    Toggle("Show engine analysis", isOn: Binding(
                        get: { settingsStore.settings.engineAnalysisVisible },
                        set: { newValue in
                            settingsStore.update { $0.engineAnalysisVisible = newValue }
                        }
                    ))

                    Toggle("Main line in algebraic notation", isOn: Binding(
                        get: { settingsStore.settings.engineAnalysisUseAlgebraicNotation },
                        set: { newValue in
                            settingsStore.update { $0.engineAnalysisUseAlgebraicNotation = newValue }
                        }
                    ))

                    Toggle("Show best-move arrow on board", isOn: Binding(
                        get: { settingsStore.settings.engineAnalysisShowBoardArrow },
                        set: { newValue in
                            settingsStore.update { $0.engineAnalysisShowBoardArrow = newValue }
                        }
                    ))

                    ColorPicker("Best-move arrow color", selection: $analysisArrowColor, supportsOpacity: false)
                        .disabled(!settingsStore.settings.engineAnalysisShowBoardArrow)
                        .onChange(of: analysisArrowColor) { _, color in
                            settingsStore.update { $0.engineAnalysisArrowColor = CodableColor(color) }
                        }

                    Toggle("Show evaluation bar", isOn: Binding(
                        get: { settingsStore.settings.engineAnalysisShowEvaluationBar },
                        set: { newValue in
                            settingsStore.update { $0.engineAnalysisShowEvaluationBar = newValue }
                        }
                    ))

                    VStack(alignment: .leading) {
                        Text(engineDepthLabel)
                        Slider(value: Binding(
                            get: { settingsStore.settings.engineAnalysisDepth },
                            set: { newValue in
                                settingsStore.update { $0.engineAnalysisDepth = newValue.rounded() }
                            }
                        ), in: 1...AppSettings.uncappedEngineAnalysisDepth, step: 1)
                    }
                } header: {
                    Text("Engine")
                }
                
                Section {
                    LabeledContent("Site") {
                        TextField("?", text: Binding(
                            get: { settingsStore.settings.pgnSite },
                            set: { newValue in
                                settingsStore.update { $0.pgnSite = newValue }
                            }
                        ))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    }
                    
                    LabeledContent("White") {
                        TextField("?", text: Binding(
                            get: { settingsStore.settings.pgnWhite },
                            set: { newValue in
                                settingsStore.update { $0.pgnWhite = newValue }
                            }
                        ))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    }
                    
                    LabeledContent("Black") {
                        TextField("?", text: Binding(
                            get: { settingsStore.settings.pgnBlack },
                            set: { newValue in
                                settingsStore.update { $0.pgnBlack = newValue }
                            }
                        ))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    }
                    
                    Button {
                        swapPGNPlayers()
                    } label: {
                        Label("Switch White & Black", systemImage: "arrow.left.arrow.right")
                    }

                    Toggle("Hide PGN header tags", isOn: Binding(
                        get: { settingsStore.settings.pgnHideHeaderTags },
                        set: { newValue in
                            settingsStore.update { $0.pgnHideHeaderTags = newValue }
                        }
                    ))
                } header: {
                    Text("PGN")
                } footer: {
                    Text("Player names are used for [White] and [Black] tags in exported PGN. Use Switch to swap sides between games. Hiding header tags affects the notation panel only; Copy and Share still include full PGN headers.")
                }
                
                Section {
                    Toggle("Touch input", isOn: Binding(
                        get: { settingsStore.settings.touchInputEnabled },
                        set: { newValue in
                            settingsStore.update { $0.touchInputEnabled = newValue }
                        }
                    ))

                    Toggle("Show opening name", isOn: Binding(
                        get: { settingsStore.settings.openingNameVisible },
                        set: { newValue in
                            settingsStore.update { $0.openingNameVisible = newValue }
                        }
                    ))
                    
                    VStack(alignment: .leading) {
                        Text("Board size: \(Int(settingsStore.settings.boardSizePercent * 100))%")
                        Slider(value: Binding(
                            get: { settingsStore.settings.boardSizePercent },
                            set: { newValue in
                                settingsStore.update { $0.boardSizePercent = newValue }
                            }
                        ), in: 0.5...1.0, step: 0.05)
                    }

                    VStack(alignment: .leading) {
                        Text("Piece size: \(Int(settingsStore.settings.pieceSizePercent * 100))%")
                        Slider(value: Binding(
                            get: { settingsStore.settings.pieceSizePercent },
                            set: { newValue in
                                settingsStore.update { $0.pieceSizePercent = newValue }
                            }
                        ), in: 0.5...1.0, step: 0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(moveAnimationLabel)
                        Slider(value: Binding(
                            get: { settingsStore.settings.moveAnimationDuration },
                            set: { newValue in
                                settingsStore.update { $0.moveAnimationDuration = newValue }
                            }
                        ), in: 0...1.0, step: 0.05)
                    }
                    
                    ColorPicker("Light squares", selection: $lightColor, supportsOpacity: false)
                        .onChange(of: lightColor) { _, color in
                            settingsStore.update { $0.lightSquareColor = CodableColor(color) }
                        }
                    
                    ColorPicker("Dark squares", selection: $darkColor, supportsOpacity: false)
                        .onChange(of: darkColor) { _, color in
                            settingsStore.update { $0.darkSquareColor = CodableColor(color) }
                        }
                } header: {
                    Text("Board")
                } footer: {
                    Text("Board size scales the chessboard relative to the largest size that fits on screen. At 100%, the board uses all available space; reducing it leaves more room for the notation panels in portrait or landscape. When Touch input is enabled, tap a piece and then a destination square to make moves on the board. The opening name appears above the board when moves are played.")
                }
                
                Section {
                    Button {
                        showingAddPhrase = true
                    } label: {
                        Label("Add phrase", systemImage: "plus")
                    }

                    if learnedEntries.isEmpty {
                        Text("No custom phrases yet. Use “Add phrase” or teach a phrase after a failed move.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(learnedEntries.enumerated()), id: \.element.id) { index, entry in
                            SwipeToDeleteRow(
                                onDelete: { deleteLearnedPhrase(entry) },
                                cornerRadii: .insetGroupedListRow(
                                    index: index,
                                    count: learnedEntries.count,
                                    roundsTop: false,
                                    roundsBottom: false
                                ),
                                showsSeparatorBelow: index < learnedEntries.count - 1
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.phrase)
                                        .font(.subheadline)
                                    Text("→ \(entry.moveNotation)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .environment(\.defaultMinListRowHeight, 0)
                        }
                    }
                    
                    if !learnedEntries.isEmpty {
                        Button("Clear \(phraseListLanguage.displayName) phrases", role: .destructive) {
                            vocabularyStore.reset(language: phraseListLanguage)
                            scheduleSpeechModelUpdate(for: phraseListLanguage)
                        }
                    }
                } header: {
                    Text("Learned phrases")
                } footer: {
                    Text("This section is for your own custom phrases, which boost on-device speech recognition and map your wording to SAN.")
                }

                Section {
                    Button {
                        showingAddCorrection = true
                    } label: {
                        Label("Add correction", systemImage: "wand.and.stars")
                    }

                    if correctionEntries.isEmpty {
                        Text("No custom corrections yet. Add one for repeated recognition mistakes like “9” -> “knight”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(correctionEntries.enumerated()), id: \.element.id) { index, entry in
                            SwipeToDeleteRow(
                                onDelete: { deleteCorrection(entry) },
                                cornerRadii: .insetGroupedListRow(
                                    index: index,
                                    count: correctionEntries.count,
                                    roundsTop: false
                                ),
                                showsSeparatorBelow: index < correctionEntries.count - 1
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.heard)
                                        .font(.subheadline)
                                    Text("→ \(entry.replacement)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .environment(\.defaultMinListRowHeight, 0)
                        }
                    }
                } header: {
                    Text("Speech Corrections")
                } footer: {
                    Text("Corrections are applied before move parsing and phrase matching. Use them for recurring ASR mistakes such as digits, homophones, or misheard piece names.")
                }
                
                Section("Coordinates") {
                    ColorPicker("Color", selection: $coordinateColor, supportsOpacity: false)
                        .onChange(of: coordinateColor) { _, color in
                            settingsStore.update { $0.coordinateColor = CodableColor(color) }
                        }
                    
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text("\(Int(settingsStore.settings.coordinateFontSize)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { settingsStore.settings.coordinateFontSize },
                        set: { newValue in
                            settingsStore.update { $0.coordinateFontSize = newValue }
                        }
                    ), in: 6...18, step: 1)
                }
                
                Section {
                    Button("Reset to defaults", role: .destructive) {
                        settingsStore.resetToDefaults()
                        vocabularyStore.resetAll()
                        applyLocalStateFromStore()
                        requestLanguageChange(settingsStore.settings.defaultRecognitionLanguage)
                        for language in RecognitionLanguage.allCases {
                            scheduleSpeechModelUpdate(for: language)
                        }
                    }
                } footer: {
                    Text("Restores app settings and the default speech correction examples.")
                }

                if developerModeStore.showsDeveloperSettings {
                    Section {
                        Toggle("Screenshot mode", isOn: $developerModeStore.isScreenshotModeEnabled)
                        Toggle("Speech pipeline trace", isOn: $developerModeStore.isSpeechPipelineTracingEnabled)
                    } footer: {
                        Text("Screenshot mode hides the system status bar. Speech pipeline trace logs each ASR and normalization step to the Xcode console when a move is processed.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var learnedEntries: [LearnedPhrase] {
        vocabularyStore.entries(for: phraseListLanguage)
    }

    private var correctionEntries: [LearnedCorrection] {
        vocabularyStore.correctionEntries(for: phraseListLanguage)
    }

    private func scheduleSpeechModelUpdate(for language: RecognitionLanguage) {
        requestVocabularyReload(for: language)
    }

    private func requestLanguageChange(_ language: RecognitionLanguage) {
        var work = pendingSpeechModelWork
        work.requestLanguageChange(language)
        pendingSpeechModelWork = work
    }

    private func requestVocabularyReload(for language: RecognitionLanguage) {
        var work = pendingSpeechModelWork
        work.requestVocabularyReload(for: language)
        pendingSpeechModelWork = work
    }
    
    private var moveAnimationLabel: String {
        let duration = settingsStore.settings.moveAnimationDuration
        if duration <= 0 {
            return "Move animation: Instant"
        }
        return String(format: "Move animation: %.2f s", duration)
    }
    
    private var dictationPauseLabel: String {
        String(format: "Dictation pause: %.2f s", settingsStore.settings.dictationPauseSeconds)
    }

    private var engineDepthLabel: String {
        if settingsStore.settings.isEngineAnalysisUncapped {
            return "Analysis Max Depth: Uncapped"
        }
        return "Analysis Max Depth: \(Int(settingsStore.settings.engineAnalysisDepth))"
    }
    
    private func swapPGNPlayers() {
        settingsStore.update {
            let white = $0.pgnWhite
            $0.pgnWhite = $0.pgnBlack
            $0.pgnBlack = white
        }
    }
    
    private func deleteLearnedPhrase(_ entry: LearnedPhrase) {
        vocabularyStore.remove(id: entry.id)
        scheduleSpeechModelUpdate(for: phraseListLanguage)
    }

    private func deleteCorrection(_ entry: LearnedCorrection) {
        vocabularyStore.remove(id: entry.id)
        scheduleSpeechModelUpdate(for: phraseListLanguage)
    }

    private func applyLocalStateFromStore() {
        let settings = settingsStore.settings
        lightColor = settings.lightSquareColor.color
        darkColor = settings.darkSquareColor.color
        coordinateColor = settings.coordinateColor.color
        analysisArrowColor = settings.engineAnalysisArrowColor.color
        selectedLanguage = settings.defaultRecognitionLanguage
        phraseListLanguage = settings.defaultRecognitionLanguage
    }
}
