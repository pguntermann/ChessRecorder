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
                    aboutSection

                    Divider()

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
                            "\"Rook f to d1\" — rook on the f-file to d1",
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
                            "\"Turm f auf d1\" — Turm von der f-Linie nach d1",
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
            .navigationTitle("About & Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(spacing: 20) {
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

            attributionSection
        }
    }

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attribution & License")
                .font(.headline)

            Text("Chess Recorder is free software released under the GNU General Public License v3.0.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Chess Recorder builds on several open-source projects:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(AppInfo.acknowledgments) { acknowledgment in
                    bulletLink(
                        "\(acknowledgment.name) (\(acknowledgment.license))",
                        destination: acknowledgment.url
                    )
                }
            }

            Text("The full source code and additional information can be accessed using the links below:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                bulletLink("Source code", destination: AppInfo.repositoryURL)
                bulletLink("License", destination: AppInfo.licenseURL)
                bulletLink("Third-party licenses", destination: AppInfo.thirdPartyLicensesURL)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func bulletLink(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(title)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
