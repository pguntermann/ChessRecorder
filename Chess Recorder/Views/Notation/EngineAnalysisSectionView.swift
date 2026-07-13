//
//  EngineAnalysisSectionView.swift
//  Chess Recorder
//

import SwiftUI

struct EngineAnalysisSectionView: View {
    let game: ChessGame
    let useAlgebraicNotation: Bool
    @Bindable var analysisService: EngineAnalysisService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Engine Analysis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    if analysisService.isActive {
                        analysisService.stop()
                    } else {
                        analysisService.startAnalyzing(game: game)
                    }
                } label: {
                    Label(
                        analysisService.isActive ? "Stop" : "Start",
                        systemImage: analysisService.isActive ? "stop.fill" : "play.fill"
                    )
                    .font(.subheadline)
                    .imageScale(.medium)
                }
                .disabled(!analysisService.isEngineReady)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(analysisService.display.evaluationText)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                
                if let phase = analysisService.display.gamePhase, analysisService.isActive {
                    Text(phase.rawValue)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                
                if analysisService.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
                
                Spacer()
                
                Text(analysisService.display.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if let wdl = analysisService.display.winProbability, analysisService.isActive {
                WinProbabilityBarView(wdl: wdl)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Main line")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text(principalLineText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }

    private var principalLineText: String {
        let text = useAlgebraicNotation
            ? analysisService.display.principalLineSAN
            : analysisService.display.principalLineUCI
        return text.isEmpty ? "—" : text
    }
}

private struct WinProbabilityBarView: View {
    let wdl: WinProbabilityDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Win probability")
                .font(.caption2)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let total = max(wdl.white + wdl.draw + wdl.black, 0.001)
                let whiteWidth = geometry.size.width * wdl.white / total
                let drawWidth = geometry.size.width * wdl.draw / total
                let blackWidth = max(0, geometry.size.width - whiteWidth - drawWidth)

                HStack(spacing: 1) {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: whiteWidth)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: drawWidth)
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: blackWidth)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                )
            }
            .frame(height: 7)

            HStack {
                wdlLabel("White", percent: wdl.whitePercent)
                Spacer(minLength: 8)
                wdlLabel("Draw", percent: wdl.drawPercent)
                Spacer(minLength: 8)
                wdlLabel("Black", percent: wdl.blackPercent)
            }
        }
    }

    private func wdlLabel(_ title: String, percent: Int) -> Text {
        Text("\(title) \(percent)%")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
