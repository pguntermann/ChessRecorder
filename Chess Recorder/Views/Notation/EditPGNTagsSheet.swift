//
//  EditPGNTagsSheet.swift
//  Chess Recorder
//

import SwiftUI

struct EditPGNTagsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let roundTitle: String
    let initialMetadata: PGNMetadata
    let initialDate: Date
    let onSave: (PGNMetadata, Date) -> Void

    @State private var event: String
    @State private var site: String
    @State private var white: String
    @State private var black: String
    @State private var date: Date

    init(
        roundTitle: String,
        metadata: PGNMetadata,
        date: Date,
        onSave: @escaping (PGNMetadata, Date) -> Void
    ) {
        self.roundTitle = roundTitle
        self.initialMetadata = metadata
        self.initialDate = date
        self.onSave = onSave
        _event = State(initialValue: metadata.event)
        _site = State(initialValue: metadata.site)
        _white = State(initialValue: metadata.white)
        _black = State(initialValue: metadata.black)
        _date = State(initialValue: date)
    }

    private var editedMetadata: PGNMetadata {
        PGNMetadata(
            event: trimmedOrPlaceholder(event, fallback: AppSettings.defaultPGNEvent),
            site: trimmedOrPlaceholder(site, fallback: "?"),
            white: trimmedOrPlaceholder(white, fallback: "?"),
            black: trimmedOrPlaceholder(black, fallback: "?")
        )
    }

    private var hasChanges: Bool {
        editedMetadata != initialMetadata
            || !Calendar.current.isDate(date, inSameDayAs: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Event") {
                        TextField(AppSettings.defaultPGNEvent, text: $event)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    LabeledContent("Site") {
                        TextField("?", text: $site)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    DatePicker(
                        "Date",
                        selection: $date,
                        displayedComponents: .date
                    )

                    LabeledContent("White") {
                        TextField("?", text: $white)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    LabeledContent("Black") {
                        TextField("?", text: $black)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    Button {
                        let previousWhite = white
                        white = black
                        black = previousWhite
                    } label: {
                        Label("Switch White & Black", systemImage: "arrow.left.arrow.right")
                    }
                } header: {
                    Text(roundTitle)
                } footer: {
                    Text("These tags apply only to this game’s PGN headers. Round, Result, and ECO stay as recorded.")
                }
            }
            .navigationTitle("Edit PGN Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editedMetadata, date)
                        dismiss()
                    }
                    .disabled(!hasChanges)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func trimmedOrPlaceholder(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
