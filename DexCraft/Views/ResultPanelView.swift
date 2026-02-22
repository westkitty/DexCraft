import SwiftUI

struct ResultPanelView: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Forged Prompt")
                    .font(.headline)
                Spacer()
                Button("Hide") {
                    viewModel.isResultPanelVisible = false
                }
                .buttonStyle(.bordered)
            }

            qualityGate

            Toggle("Show Diff View", isOn: $viewModel.showDiff)
                .toggleStyle(.switch)

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
                        Text(viewModel.generatedPrompt)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                }
            }
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Button("Copy to Clipboard") {
                    viewModel.copyToClipboard()
                }
                .buttonStyle(.borderedProminent)

                if viewModel.selectedTarget == .agenticIDE {
                    Menu("IDE Export") {
                        Button("Export .cursorrules") {
                            viewModel.exportForIDE(.cursorRules)
                        }

                        Button("Export copilot-instructions.md") {
                            viewModel.exportForIDE(.copilotInstructions)
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
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
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
