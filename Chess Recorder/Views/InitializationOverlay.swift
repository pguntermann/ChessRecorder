//
//  InitializationOverlay.swift
//  Chess Recorder
//

import SwiftUI

struct InitializationOverlay: View {
    let phase: InitializationPhase
    let context: InitializationContext
    var presentation: Presentation = .fullscreen

    enum Presentation {
        /// Covers the main app during startup.
        case fullscreen
        /// Covers a presented sheet — must be fully opaque, not translucent.
        case modal
    }

    private var activePhase: InitializationPhase {
        context.steps.contains(phase) ? phase : (context.steps.first ?? phase)
    }

    var body: some View {
        ZStack {
            switch presentation {
            case .fullscreen:
                Color(uiColor: .systemBackground)
                    .opacity(0.94)
            case .modal:
                Color(uiColor: .systemBackground)
            }

            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)

                VStack(spacing: 8) {
                    Text(activePhase.title)
                        .font(.headline)

                    Text(activePhase.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(context.steps, id: \.self) { step in
                        InitializationStepRow(
                            title: step.title,
                            isComplete: step.isComplete(relativeTo: activePhase, in: context),
                            isCurrent: step == activePhase
                        )
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.top, 4)

                Text("Step \(activePhase.stepNumber(in: context)) of \(context.totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(32)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activePhase.title). \(activePhase.detail)")
    }
}

private struct InitializationStepRow: View {
    let title: String
    let isComplete: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(textColor)
        }
    }

    private var iconName: String {
        if isComplete { return "checkmark.circle.fill" }
        if isCurrent { return "ellipsis.circle.fill" }
        return "circle"
    }

    private var iconColor: Color {
        if isComplete { return .green }
        if isCurrent { return .accentColor }
        return .secondary.opacity(0.45)
    }

    private var textColor: Color {
        if isCurrent { return .primary }
        if isComplete { return .secondary }
        return .secondary.opacity(0.55)
    }
}
