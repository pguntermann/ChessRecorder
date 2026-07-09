//
//  HelpView.swift
//  Chess Recorder
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    helpSection(
                        title: "Getting started",
                        body: """
                        Tap Record and speak your move. Pause briefly when finished — the app waits a moment, then plays the move on the board. You can also enter moves by tapping pieces when Touch input is enabled in Settings.
                        """
                    )

                    helpSection(
                        title: "Supported phrases (English)",
                        examples: [
                            "\"e4\" — pawn to e4",
                            "\"Knight f3\" — knight to f3",
                            "\"Knight g1 to f3\" — knight from g1 to f3",
                            "\"e takes d5\" or \"exd5\" — pawn capture",
                            "\"Bishop c4\" — bishop to c4",
                            "\"Castle kingside\" — O-O",
                            "\"Undo\" — take back the last move"
                        ]
                    )

                    helpSection(
                        title: "Supported phrases (German)",
                        examples: [
                            "\"e4\" — Bauer nach e4",
                            "\"Springer f3\" — Springer nach f3",
                            "\"Springer g1 auf f3\" — Springer von g1 nach f3",
                            "\"e schlägt d5\" — Bauer schlägt auf d5",
                            "\"Läufer c4\" — Läufer nach c4",
                            "\"Kurz rochiert\" — O-O",
                            "\"Zurück\" — letzten Zug zurücknehmen"
                        ]
                    )

                    helpSection(
                        title: "Tips",
                        body: """
                        If a phrase is not recognized, use Teach phrase after a failed attempt or add custom phrases in Settings. Corrections can fix recurring mis-hearings such as \"9\" → \"knight\".
                        """
                    )
                }
                .padding()
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Text(AppInfo.displayName)
                .font(.title2)
                .bold()

            Text(AppInfo.versionLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func helpSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func helpSection(title: String, examples: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    Text("• \(example)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    HelpView()
}
