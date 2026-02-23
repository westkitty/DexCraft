import SwiftUI

struct PrimaryPanelView: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    @State private var isTemplateManagerPresented = false
    @State private var isHistoryManagerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    selectorSection
                    roughInputEditor

                    if !viewModel.detectedVariables.isEmpty {
                        variableSection
                    }

                    tabPicker
                    tabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isTemplateManagerPresented) {
            TemplateManagerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isHistoryManagerPresented) {
            HistoryManagerSheet(viewModel: viewModel)
        }
    }

    private var headerBar: some View {
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
    }

    private var selectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Auto-optimize prompt", isOn: $viewModel.autoOptimizePrompt)
                .toggleStyle(.switch)
                .font(.caption)

            if viewModel.autoOptimizePrompt {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model Family")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Model Family", selection: $viewModel.selectedModelFamily) {
                        ForEach(ModelFamily.allCases) { family in
                            Text(family.rawValue).tag(family)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Scenario / Use Case")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Scenario / Use Case", selection: $viewModel.selectedScenarioProfile) {
                        ForEach(ScenarioProfile.allCases) { scenario in
                            Text(scenario.rawValue).tag(scenario)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Text("Legacy formatting: \(viewModel.selectedTarget.segmentTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Menu("Adjust") {
                        ForEach(PromptTarget.allCases) { target in
                            Button(target.rawValue) {
                                viewModel.selectedTarget = target
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Target Environment")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Target Environment", selection: $viewModel.selectedTarget) {
                        ForEach(PromptTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .glassCard()
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
        .padding(10)
        .glassCard()
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
        .glassCard()
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Enhancement Options")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
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
            } label: {
                Label("Configure Enhancements (\(viewModel.options.activeConstraintCount) active)", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)

            Text("Options are in this pull-down to keep the forge controls visible.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .glassCard()
    }

    private var templatesTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(viewModel.templates.count) saved templates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Template Manager") {
                    isTemplateManagerPresented = true
                }
                .buttonStyle(.bordered)
            }

            Menu("Quick Apply Template") {
                ForEach(Array(viewModel.templates.prefix(12))) { template in
                    Button(template.name) {
                        viewModel.applyTemplate(template)
                    }
                }
            }
            .disabled(viewModel.templates.isEmpty)
            .menuStyle(.borderlessButton)

            Text("Use the manager pop-up for full template editing and scrolling.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .glassCard()
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History: \(viewModel.history.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open History") {
                    isHistoryManagerPresented = true
                }
                .buttonStyle(.bordered)
            }

            if let latest = viewModel.history.first {
                Text("Latest: \(latest.target.segmentTitle) at \(viewModel.formatDate(latest.timestamp))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No saved history yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .glassCard()
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
        .glassCard()
    }
}

private struct TemplateManagerSheet: View {
    @ObservedObject var viewModel: PromptEngineViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Template Manager")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(viewModel.templates.count) templates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                TextField("Template name", text: $viewModel.templateNameDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Save Current Input") {
                    viewModel.saveCurrentAsTemplate()
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.templates) { template in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(template.target.segmentTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Load") {
                                viewModel.applyTemplate(template)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                viewModel.deleteTemplate(template)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .glassCard(cornerRadius: 8)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 520)
        .background(Color.black.opacity(0.15))
    }
}

private struct HistoryManagerSheet: View {
    @ObservedObject var viewModel: PromptEngineViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prompt History")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(viewModel.history.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear") {
                    viewModel.clearHistory()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.history.isEmpty)
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.history) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.target.segmentTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(viewModel.formatDate(entry.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Load") {
                                viewModel.loadHistoryEntry(entry)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .glassCard(cornerRadius: 8)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 520)
        .background(Color.black.opacity(0.15))
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
