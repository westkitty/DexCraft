import SwiftUI

struct ResultPanelView: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.autoOptimizePrompt ? "Optimized Prompt Preview" : "Forged Prompt")
                    .font(.headline)
                Spacer()
                Button("Hide") {
                    viewModel.isResultPanelVisible = false
                }
                .buttonStyle(.bordered)
            }

            Group {
                if viewModel.showDiff {
                    ScrollView {
                        Text(viewModel.diffText())
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                } else {
                    ScrollView {
                        Text(viewModel.userVisiblePrompt)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.015))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )

            HStack(spacing: 8) {
                Button("Copy to Clipboard") {
                    viewModel.copyToClipboard()
                }
                .buttonStyle(.borderedProminent)

                Menu("Export") {
                    Button("Markdown (.md)") {
                        viewModel.exportOptimizedPromptAsMarkdown()
                    }

                    if viewModel.selectedTarget == .agenticIDE {
                        Divider()
                        Button(viewModel.preferredIDEExportFormat.displayName) {
                            viewModel.exportForIDE(viewModel.preferredIDEExportFormat)
                        }
                        Divider()
                        Button("Export .cursorrules") {
                            viewModel.exportForIDE(.cursorRules)
                        }

                        Button("Export copilot-instructions.md") {
                            viewModel.exportForIDE(.copilotInstructions)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show debug report", isOn: $viewModel.showDebugReport)
                    .toggleStyle(.switch)
                Toggle("Show Diff View", isOn: $viewModel.showDiff)
                    .toggleStyle(.switch)
                qualityGate
                optimizationSummary
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var qualityGate: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quality Gate")
                .font(.subheadline.weight(.semibold))

            ForEach(viewModel.qualityChecks) { check in
                HStack(spacing: 8) {
                    Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.passed ? .green : .red)
                    Text(check.title)
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.30)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.015))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var optimizationSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Offline Optimization")
                .font(.subheadline.weight(.semibold))

            Text("Model: \(viewModel.selectedModelFamily.rawValue)")
                .font(.caption)
            Text("Scenario: \(viewModel.selectedScenarioProfile.rawValue)")
                .font(.caption)
            Text("Suggested Params: \(viewModel.optimizationParameterSummary)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !viewModel.optimizationAppliedRules.isEmpty {
                Text("Applied Rules")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                ForEach(viewModel.optimizationAppliedRules, id: \.self) { rule in
                    Text("• \(rule)")
                        .font(.caption2)
                }
            }

            if !viewModel.optimizationWarnings.isEmpty {
                Text("Warnings")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                ForEach(viewModel.optimizationWarnings, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.30)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.015))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}
