//
//  DeveloperPGNImportSheet.swift
//  Chess Recorder
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !os(iOS)
import AppKit
#endif

struct DeveloperPGNImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onImport: (String) throws -> Int

    @State private var pgnText = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showingFileImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $pgnText)
                        .font(.body.monospaced())
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("PGN")
                } footer: {
                    Text("Paste an exported Chess Recorder session or another standard multi-game PGN (mainline only, standard start).")
                }

                Section {
                    Button("Paste from Clipboard") {
                        pasteFromClipboard()
                    }
                    Button("Choose PGN File…") {
                        showingFileImporter = true
                    }
                    Button("Import Games") {
                        importPGN()
                    }
                    .disabled(pgnText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import PGN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: pgnContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    loadFile(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    statusMessage = nil
                }
            }
        }
    }

    private var pgnContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .utf8PlainText]
        if let pgn = UTType(filenameExtension: "pgn") {
            types.append(pgn)
        }
        return types
    }

    private func pasteFromClipboard() {
        #if canImport(UIKit)
        if let string = UIPasteboard.general.string, !string.isEmpty {
            pgnText = string
            errorMessage = nil
            statusMessage = "Pasted from clipboard."
            return
        }
        #endif
        #if canImport(AppKit) && !os(iOS)
        if let string = NSPasteboard.general.string(forType: .string), !string.isEmpty {
            pgnText = string
            errorMessage = nil
            statusMessage = "Pasted from clipboard."
            return
        }
        #endif
        errorMessage = "Clipboard has no text."
        statusMessage = nil
    }

    private func loadFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            pgnText = try String(contentsOf: url, encoding: .utf8)
            errorMessage = nil
            statusMessage = "Loaded \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func importPGN() {
        do {
            let count = try onImport(pgnText)
            statusMessage = count == 1 ? "Imported 1 game." : "Imported \(count) games."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }
}
