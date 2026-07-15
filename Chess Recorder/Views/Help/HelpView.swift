//
//  HelpView.swift
//  Chess Recorder
//

import SwiftUI
import UIKit

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private static let alternativePhrasingTips = [
        "\"Knight from e to d5\" — file disambiguation with prepositions",
        "\"Knight from e7 to d5\" — full source square",
        "\"e7 to d5\" — coordinates only (when unambiguous)"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    aboutSection

                    Divider()

                    helpSection(
                        title: "Getting started",
                        cardStyle: true,
                        body: """
                        Tap Record and speak your move. Pause briefly when finished — the app waits a moment, then plays the move on the board. You can also enter moves by tapping pieces when Touch input is enabled in Settings.
                        """
                    )

                    helpSection(
                        title: "Example phrases (English)",
                        cardStyle: true,
                        examples: [
                            "\"e4\" — pawn to e4",
                            "\"Knight f3\" — knight to f3",
                            "\"Knight g1 to f3\" — knight from g1 to f3",
                            "\"g1 f3\" or \"g1 to f3\" — knight from g1 to f3 (coordinates)",
                            "\"Rook f to d1\" — rook on the f-file to d1",
                            "\"Rook d takes c8\" — rook on the d-file captures on c8",
                            "\"e takes d5\" or \"exd5\" — pawn capture",
                            "\"Bishop c4\" — bishop to c4",
                            "\"Castle kingside\" — O-O",
                            "\"Undo\" — take back the last move"
                        ]
                    )

                    helpSection(
                        title: "Example phrases (German)",
                        cardStyle: true,
                        examples: [
                            "\"e4\" — Bauer nach e4",
                            "\"Springer f3\" — Springer nach f3",
                            "\"Springer g1 auf f3\" — Springer von g1 nach f3",
                            "\"g1 f3\" or \"g1 nach f3\" — Springer von g1 nach f3 (Koordinaten)",
                            "\"Turm f auf d1\" — Turm von der f-Linie nach d1",
                            "\"Turm d schlägt c8\" — Turm von der d-Linie schlägt auf c8",
                            "\"e schlägt d5\" — Bauer schlägt auf d5",
                            "\"Läufer c4\" — Läufer nach c4",
                            "\"Kurz rochiert\" — O-O",
                            "\"Zurück\" — letzten Zug zurücknehmen"
                        ]
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tips")
                            .font(.headline)

                        Text("""
                        If a phrase is not recognized, use Teach phrase after a failed attempt or add custom phrases in Settings. Corrections can fix recurring mis-hearings such as \"9\" → \"knight\".

                        When a specific wording fails — for example \"Knight e d5\" for a knight from the e-file to d5 — try other phrasings that spell out the move more explicitly:
                        """)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Self.alternativePhrasingTips, id: \.self) { example in
                                Text("• \(example)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .helpSectionCard()
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

                VStack(spacing: 6) {
                    Text(AppInfo.copyrightNotice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(AppInfo.contactEmail) {
                        openContactEmail()
                    }
                    .font(.subheadline)
                }
                .multilineTextAlignment(.center)
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
        .helpSectionCard()
    }

    private func openContactEmail() {
        #if targetEnvironment(simulator)
        UIPasteboard.general.string = AppInfo.contactEmail
        #else
        openURL(AppInfo.contactEmailURL) { accepted in
            if !accepted {
                UIPasteboard.general.string = AppInfo.contactEmail
            }
        }
        #endif
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

    private func helpSection(title: String, cardStyle: Bool = false, body: String) -> some View {
        Group {
            if cardStyle {
                helpSectionContent(title: title, body: body)
                    .helpSectionCard()
            } else {
                helpSectionContent(title: title, body: body)
            }
        }
    }

    private func helpSectionContent(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpSection(title: String, cardStyle: Bool = false, examples: [String]) -> some View {
        Group {
            if cardStyle {
                helpSectionContent(title: title, examples: examples)
                    .helpSectionCard()
            } else {
                helpSectionContent(title: title, examples: examples)
            }
        }
    }

    private func helpSectionContent(title: String, examples: [String]) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func helpSectionCard() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HelpView()
}
