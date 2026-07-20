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

    /// When true (developer override), the usual 20-game cap is not enforced.
    var overrideGameLimit: Bool = false
    let onImport: (String) async throws -> Int

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
    @State private var isImporting = false

    private var hasPGNText: Bool {
        !pgnText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canEditInSheet: Bool {
        loadedByteCount > 0 && loadedByteCount <= Self.maxEditableUTF8ByteCount
    }

    private var gameCountLimit: Int? {
        PGNImportService.gameCountLimit(overrideLimit: overrideGameLimit)
    }

    private var hasImportablePGN: Bool {
        guard hasPGNText, estimatedGameCount > 0 else { return false }
        if let gameCountLimit, estimatedGameCount > gameCountLimit {
            return false
        }
        return true
    }

    private var canImport: Bool {
        hasImportablePGN && !isImporting
    }

    private var importFooterText: String {
        if let gameCountLimit {
            return "Imports up to \(gameCountLimit) games from a standard PGN (mainline only, standard starting position). Games are added to your current session."
        }
        return "Imports games from a standard PGN (mainline only, standard starting position). The usual game-count limit is overridden. Games are added to your current session."
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
                    .disabled(isImporting)

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .disabled(isImporting)
                } footer: {
                    Text(importFooterText)
                }

                Section {
                    Button {
                        importPGN()
                    } label: {
                        if isImporting {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(importProgressLabel)
                            }
                        } else {
                            Text("Import Games")
                        }
                    }
                    .disabled(!hasImportablePGN || isImporting)

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
                                    .disabled(isImporting)
                            } else {
                                largePGNPreview
                            }
                        }
                        .disabled(isImporting)
                    } footer: {
                        if canEditInSheet {
                            Text("Optional — open only if you want to inspect or tweak the text before importing.")
                        } else if let gameCountLimit {
                            Text("This PGN is too large to edit here. You can preview the start of the file, then import as-is (still limited to \(gameCountLimit) games).")
                        } else {
                            Text("This PGN is too large to edit here. You can preview the start of the file, then import as-is.")
                        }
                    }
                }
            }
            .navigationTitle("Import PGN")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isImporting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(importProgressLabel)
                    } else {
                        Button("Import") {
                            importPGN()
                        }
                        .disabled(!canImport)
                    }
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

    private var importProgressLabel: String {
        if estimatedGameCount > 1 {
            return "Importing \(estimatedGameCount) games…"
        }
        return "Importing…"
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
        } else if let gameCountLimit, estimatedGameCount > gameCountLimit {
            statusMessage = status
            errorMessage = PGNImportService.ImportError.tooManyGames(
                found: estimatedGameCount,
                limit: gameCountLimit
            ).localizedDescription
        } else {
            statusMessage = status
        }
    }

    private func importPGN() {
        guard canImport else { return }
        isImporting = true
        errorMessage = nil
        statusMessage = importProgressLabel

        Task { @MainActor in
            // Let the ProgressView paint before the import starts.
            await Task.yield()
            defer { isImporting = false }

            do {
                let count = try await onImport(pgnText)
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
}
