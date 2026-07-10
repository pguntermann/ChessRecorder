//
//  Chess_RecorderApp.swift
//  Chess Recorder
//
//  Created by Philipp on 08.07.26.
//

import SwiftUI

@main
struct Chess_RecorderApp: App {
    @State private var settingsStore = SettingsStore()
    @State private var vocabularyStore = PersonalVocabularyStore()
    @State private var developerModeStore = DeveloperModeStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                settingsStore: settingsStore,
                vocabularyStore: vocabularyStore,
                developerModeStore: developerModeStore
            )
            .statusBar(hidden: developerModeStore.hidesStatusBar)
        }
    }
}
