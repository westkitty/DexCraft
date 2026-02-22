import SwiftUI

struct PrimaryPanelView: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image("DexCraftWatermark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .padding(4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("DexCraft")
                    .font(.title3.weight(.semibold))
                Spacer()

                Button {
                    viewModel.requestDetachedWindowToggle()
                } label: {
                    Label(
                        viewModel.isDetachedWindowActive ? "Attach" : "Pop Out",
                        systemImage: viewModel.isDetachedWindowActive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)

                Text("Offline")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            targetPicker
            roughInputEditor

            if !viewModel.detectedVariables.isEmpty {
                variableSection
            }

            tabPicker
            tabContent

            Spacer(minLength: 4)

            Button(action: viewModel.forgePrompt) {
                HStack {
                    Spacer()
                    Label("Forge Prompt", systemImage: "hammer.fill")
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var targetPicker: some View {
        Picker("Target Environment", selection: $viewModel.selectedTarget) {
            ForEach(PromptTarget.allCases) { target in
                Text(target.segmentTitle).tag(target)
            }
        }
        .pickerStyle(.segmented)
    }

    private var roughInputEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Rough Input")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    viewModel.roughInput = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.roughInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.2))

                TransparentTextEditor(text: $viewModel.roughInput)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if viewModel.roughInput.isEmpty {
                    Text("Paste rough thoughts, tasks, notes, or constraints...")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 160)
        }
    }

    private var variableSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Variable Injection")
                .font(.headline)

            ForEach(viewModel.detectedVariables, id: \.self) { variable in
                HStack(spacing: 8) {
                    Text("{\(variable)}")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 120, alignment: .leading)

                    TextField("Value", text: viewModel.bindingForVariable(variable))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var tabPicker: some View {
        Picker("Panel", selection: $viewModel.activeTab) {
            ForEach(WorkbenchTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.activeTab {
        case .enhance:
            enhancementTab
        case .templates:
            templatesTab
        case .history:
            historyTab
        case .settings:
            settingsTab
        }
    }

    private var enhancementTab: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            Toggle("Enforce Markdown", isOn: $viewModel.options.enforceMarkdown)
            Toggle("No Conversational Filler", isOn: $viewModel.options.noConversationalFiller)
            Toggle("Add File Tree Request", isOn: $viewModel.options.addFileTreeRequest)
            Toggle("Include Verification Checklist", isOn: $viewModel.options.includeVerificationChecklist)
            Toggle("Include Risks / Edge Cases", isOn: $viewModel.options.includeRisksAndEdgeCases)
            Toggle("Include Alternatives", isOn: $viewModel.options.includeAlternatives)
            Toggle("Include Validation Steps", isOn: $viewModel.options.includeValidationSteps)
            Toggle("Include Revert Plan", isOn: $viewModel.options.includeRevertPlan)
            Toggle("Section-Aware Parsing", isOn: $viewModel.options.preferSectionAwareParsing)
            Toggle("Strict Code Only", isOn: $viewModel.options.strictCodeOnly)
            Toggle("Perplexity Search Verification", isOn: $viewModel.options.includeSearchVerificationRequirements)
                .disabled(viewModel.selectedTarget != .perplexity)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var templatesTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Template name", text: $viewModel.templateNameDraft)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    viewModel.saveCurrentAsTemplate()
                }
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(viewModel.templates) { template in
                        HStack {
                            Button(template.name) {
                                viewModel.applyTemplate(template)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)

                            Spacer()

                            Text(template.target.segmentTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Button(role: .destructive) {
                                viewModel.deleteTemplate(template)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last \(viewModel.history.count) prompts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    viewModel.clearHistory()
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(viewModel.history) { entry in
                        Button {
                            viewModel.loadHistoryEntry(entry)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.target.segmentTitle)
                                        .font(.caption.weight(.semibold))
                                    Text(viewModel.formatDate(entry.timestamp))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IDE Export Default")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("IDE Export", selection: $viewModel.preferredIDEExportFormat) {
                ForEach(PromptEngineViewModel.IDEExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)

            Text("All processing is local and deterministic. No network calls are made.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
