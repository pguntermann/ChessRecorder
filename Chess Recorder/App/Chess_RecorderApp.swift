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
    @State private var sessionStore = SessionStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                settingsStore: settingsStore,
                vocabularyStore: vocabularyStore,
                developerModeStore: developerModeStore,
                sessionStore: sessionStore
            )
            .statusBar(hidden: developerModeStore.hidesStatusBar)
        }
    }
}
