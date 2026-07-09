//
//  TeachCorrectionView.swift
//  Chess Recorder
//

import SwiftUI

struct TeachCorrectionView: View {
    @Environment(\.dismiss) private var dismiss

    let language: RecognitionLanguage
    let onSave: (String, String) -> Void

    @State private var heard = ""
    @State private var replacement = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Use corrections to normalize recurring recognition mistakes before move parsing, for example “9” -> “knight”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("What speech recognition heard") {
                    TextField("e.g. 9", text: $heard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("What it should mean") {
                    TextField("e.g. knight", text: $replacement)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add Correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            heard.trimmingCharacters(in: .whitespacesAndNewlines),
                            replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
