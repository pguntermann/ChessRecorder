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
        VStack(alignment: .leading, spacing: 8) {
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
                    .font(.caption)
                }
                .disabled(!analysisService.isEngineReady)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(analysisService.display.evaluationText)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                
                if analysisService.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
                
                Spacer()
                
                Text(analysisService.display.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
