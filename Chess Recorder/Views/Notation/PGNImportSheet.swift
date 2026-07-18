//
//  PGNImportSheet.swift
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

struct PGNImportSheet: View {
    /// Full PGN in a `TextEditor` above this size freezes/crashes SwiftUI layout.
    private static let maxEditableUTF8ByteCount = 24_000
    private static let previewCharacterLimit = 1_200

    @Environment(\.dismiss) private var dismiss

    let onImport: (String) throws -> Int

    @State private var pgnText = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showingFileImporter = false
    @State private var showingEditor = false
    @State private var showingLargeImportNotice = false
    @State private var importedCountForNotice = 0
    @State private var loadedByteCount = 0
    @State private var estimatedGameCount = 0
    @State private var previewText = ""

    private var hasPGNText: Bool {
        !pgnText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canEditInSheet: Bool {
        loadedByteCount > 0 && loadedByteCount <= Self.maxEditableUTF8ByteCount
    }

    private var canImport: Bool {
        hasPGNText
            && estimatedGameCount > 0
            && estimatedGameCount <= PGNImportService.maxGamesPerImport
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Choose PGN File…", systemImage: "doc.badge.plus")
                    }

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    Text("Imports up to \(PGNImportService.maxGamesPerImport) games from a standard PGN (mainline only, standard starting position). Games are added to your current session.")
                }

                Section {
                    Button("Import Games") {
                        importPGN()
                    }
                    .disabled(!canImport)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if hasPGNText {
                    Section {
                        DisclosureGroup(
                            canEditInSheet ? "Review or edit PGN" : "Preview PGN",
                            isExpanded: $showingEditor
                        ) {
                            if canEditInSheet {
                                TextEditor(text: $pgnText)
                                    .font(.body.monospaced())
                                    .frame(minHeight: 160)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                largePGNPreview
                            }
                        }
                    } footer: {
                        if canEditInSheet {
                            Text("Optional — open only if you want to inspect or tweak the text before importing.")
                        } else {
                            Text("This PGN is too large to edit here. You can preview the start of the file, then import as-is (still limited to \(PGNImportService.maxGamesPerImport) games).")
                        }
                    }
                }
            }
            .navigationTitle("Import PGN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importPGN()
                    }
                    .disabled(!canImport)
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
            .alert(
                "Games Imported",
                isPresented: $showingLargeImportNotice
            ) {
                Button("OK") { dismiss() }
            } message: {
                Text(largeImportNoticeMessage(for: importedCountForNotice))
            }
        }
    }

    private var largePGNPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summaryLine)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(previewText)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if pgnText.count > Self.previewCharacterLimit {
                Text("Preview truncated.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var summaryLine: String {
        let sizeLabel: String
        if loadedByteCount >= 1_000 {
            sizeLabel = String(format: "%.1f KB", Double(loadedByteCount) / 1_000)
        } else {
            sizeLabel = "\(loadedByteCount) bytes"
        }
        guard estimatedGameCount > 0 else {
            return "\(sizeLabel) · no PGN games detected"
        }
        let gamesLabel = estimatedGameCount == 1
            ? "1 game detected"
            : "\(estimatedGameCount) games detected"
        return "\(sizeLabel) · \(gamesLabel)"
    }

    private var pgnContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .utf8PlainText]
        if let pgn = UTType(filenameExtension: "pgn") {
            types.append(pgn)
        }
        return types
    }

    private func largeImportNoticeMessage(for count: Int) -> String {
        """
        Imported \(count) games.

        Chess Recorder is not a chess database app and isn’t built for importing or managing large game collections. Move assessments may take a while to run through after import.
        """
    }

    private func pasteFromClipboard() {
        #if canImport(UIKit)
        let board = UIPasteboard.general
        if let string = board.string, !string.isEmpty {
            applyLoadedText(string, status: "Pasted from clipboard — ready to import.")
            return
        }
        if let string = board.strings?.first(where: { !$0.isEmpty }) {
            applyLoadedText(string, status: "Pasted from clipboard — ready to import.")
            return
        }
        #endif
        #if canImport(AppKit) && !os(iOS)
        if let string = NSPasteboard.general.string(forType: .string), !string.isEmpty {
            applyLoadedText(string, status: "Pasted from clipboard — ready to import.")
            return
        }
        #endif
        errorMessage = "Clipboard has no text. On iPhone/iPad, allow Paste when prompted, or paste into the text field manually."
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
            let data = try Data(contentsOf: url)
            guard data.count <= PGNImportService.maxInputUTF8ByteCount else {
                errorMessage = PGNImportService.ImportError.inputTooLarge(
                    byteCount: data.count,
                    limitBytes: PGNImportService.maxInputUTF8ByteCount
                ).localizedDescription
                statusMessage = nil
                return
            }
            guard let string = String(data: data, encoding: .utf8) else {
                errorMessage = "Could not read this file as text."
                statusMessage = nil
                return
            }
            applyLoadedText(string, status: "Loaded \(url.lastPathComponent) — ready to import.")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func applyLoadedText(_ string: String, status: String) {
        pgnText = string
        loadedByteCount = string.utf8.count
        estimatedGameCount = PGNImportService.estimateGameCount(in: string)
        if string.count <= Self.previewCharacterLimit {
            previewText = string
        } else {
            previewText = String(string.prefix(Self.previewCharacterLimit)) + "…"
        }
        // Keep review collapsed so Import stays on-screen; never open TextEditor for huge PGNs.
        showingEditor = false
        errorMessage = nil

        if !PGNImportService.looksLikePGN(string) {
            statusMessage = nil
            errorMessage = PGNImportService.ImportError.notPGN.localizedDescription
        } else if estimatedGameCount > PGNImportService.maxGamesPerImport {
            statusMessage = status
            errorMessage = PGNImportService.ImportError.tooManyGames(
                found: estimatedGameCount,
                limit: PGNImportService.maxGamesPerImport
            ).localizedDescription
        } else {
            statusMessage = status
        }
    }

    private func importPGN() {
        do {
            let count = try onImport(pgnText)
            errorMessage = nil
            if PGNImportService.shouldShowLargeImportNotice(importedCount: count) {
                importedCountForNotice = count
                statusMessage = count == 1 ? "Imported 1 game." : "Imported \(count) games."
                showingLargeImportNotice = true
            } else {
                statusMessage = count == 1 ? "Imported 1 game." : "Imported \(count) games."
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }
}
