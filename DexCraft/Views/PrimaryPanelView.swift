import SwiftUI

struct PrimaryPanelView: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    @State private var isTemplateManagerPresented = false
    @State private var isHistoryManagerPresented = false
    @State private var isStructuredDraftExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    selectorSection
                    roughInputEditor
                    structuredEditorPreview

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
            HStack(spacing: 10) {
                Toggle("Auto-optimize prompt", isOn: $viewModel.autoOptimizePrompt)
                    .toggleStyle(.switch)
                    .font(.caption)

                Button {
                    viewModel.toggleEmbeddedTinyModelEnabled()
                } label: {
                    Label(
                        viewModel.isEmbeddedTinyModelEnabled ? "Tiny LLM On" : "Tiny LLM Off",
                        systemImage: viewModel.isEmbeddedTinyModelEnabled ? "sparkles" : "sparkles.slash"
                    )
                    .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(viewModel.isEmbeddedTinyModelEnabled ? .cyan : .secondary)
            }

            if viewModel.isEmbeddedTinyModelEnabled && !viewModel.tinyModelStatus.isEmpty {
                Text(viewModel.tinyModelStatus)
                    .font(.caption2)
                    .foregroundStyle(
                        viewModel.tinyModelStatus.localizedCaseInsensitiveContains("applied") ? .green : .yellow
                    )
                    .lineLimit(2)
            }

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
                .glassInset(cornerRadius: 8)
            }

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
                    .glassInset(cornerRadius: 8)
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
                    .glassInset(cornerRadius: 8)
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
                    .fill(.ultraThinMaterial)
                    .opacity(0.30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

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

    private var structuredEditorPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isStructuredDraftExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        Text("Goal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.draftGoal)
                            .font(.system(size: 12))
                            .frame(height: 44)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .glassInset(cornerRadius: 8)
                    }

                    Group {
                        Text("Context")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.draftContext)
                            .font(.system(size: 12))
                            .frame(height: 56)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .glassInset(cornerRadius: 8)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Constraints (one per line)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $viewModel.draftConstraintsText)
                                .font(.system(size: 12))
                                .frame(height: 66)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .glassInset(cornerRadius: 8)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Deliverables (one per line)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $viewModel.draftDeliverablesText)
                                .font(.system(size: 12))
                                .frame(height: 66)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .glassInset(cornerRadius: 8)
                        }
                    }

                    HStack {
                        Text("Preview Format")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Preview Format", selection: $viewModel.structuredPreviewFormat) {
                            ForEach(Format.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    ScrollView {
                        Text(viewModel.structuredPreview)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(height: 170)
                    .glassInset(cornerRadius: 10)
                }
                .padding(.top, 6)
            } label: {
                Text("Structured Draft + Live Preview")
                    .font(.headline)
            }
            .animation(.easeInOut(duration: 0.18), value: isStructuredDraftExpanded)
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
        case .library:
            libraryTab
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .glassInset(cornerRadius: 8)
            }
            .menuStyle(.borderlessButton)

            Text("Options are in this pull-down to keep the forge controls visible.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .glassCard()
    }

    private var libraryTab: some View {
        PromptLibraryTab(viewModel: viewModel)
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
            .glassInset(cornerRadius: 8)

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
            Text("Export Defaults")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("IDE format")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("IDE Export", selection: $viewModel.preferredIDEExportFormat) {
                    ForEach(PromptEngineViewModel.IDEExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassInset(cornerRadius: 8)

            Divider()
                .padding(.vertical, 4)

            Text("Embedded Tiny Model")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Status: \(viewModel.isEmbeddedTinyModelEnabled ? "Enabled" : "Disabled") (\(viewModel.embeddedTinyModelIdentifier))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Runtime is bundled inside DexCraft. No external llama setup is required.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tiny Model Override (.gguf, optional)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        "/path/to/SmolLM2-135M-Instruct-*.gguf",
                        text: Binding(
                            get: { viewModel.embeddedTinyModelPath },
                            set: { viewModel.updateEmbeddedTinyModelPath($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Browse") {
                        viewModel.browseEmbeddedTinyModelPath()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("When enabled, successful tiny-model output overrides heuristic output.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !viewModel.tinyModelStatus.isEmpty {
                Text(viewModel.tinyModelStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .glassCard()
    }
}

private struct PromptLibraryTab: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    @State private var selectedPromptID: UUID?
    @State private var selectedPromptForTags: PromptLibraryItem?
    @State private var newCategoryName: String = ""
    @State private var newTagName: String = ""
    @State private var newPromptTitle: String = ""
    @State private var newPromptBody: String = ""
    @State private var newPromptCategoryID: UUID?

    private var selectedPrompt: PromptLibraryItem? {
        guard let selectedPromptID else { return nil }
        return viewModel.promptLibraryPrompts.first(where: { $0.id == selectedPromptID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search title, body, or tag", text: $viewModel.promptLibrarySearchQuery)
                    .textFieldStyle(.roundedBorder)
                Text("\(viewModel.filteredPromptLibraryPrompts.count) prompts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                categoryColumn
                promptColumn
            }

            HStack(spacing: 8) {
                TextField("New tag", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                Button("Add Tag") {
                    viewModel.createPromptLibraryTag(name: newTagName)
                    newTagName = ""
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .glassCard()
        .sheet(item: $selectedPromptForTags) { prompt in
            PromptTagAssignmentSheet(viewModel: viewModel, prompt: prompt)
        }
    }

    private var categoryColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    categoryRow(title: "All", id: nil, canDelete: false)
                    ForEach(viewModel.promptLibraryCategories) { category in
                        categoryRow(title: category.name, id: category.id, canDelete: true)
                    }
                }
            }
            .frame(minHeight: 240, maxHeight: 240)

            HStack(spacing: 8) {
                TextField("New category", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    viewModel.createPromptLibraryCategory(name: newCategoryName)
                    newCategoryName = ""
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(width: 190, alignment: .topLeading)
    }

    private var promptColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompts")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(selection: $selectedPromptID) {
                ForEach(viewModel.filteredPromptLibraryPrompts) { prompt in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(prompt.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(viewModel.promptLibraryCategoryName(for: prompt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(prompt.id)
                }
            }
            .frame(minHeight: 180, maxHeight: 220)

            if let selectedPrompt {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Menu("Category: \(viewModel.promptLibraryCategoryName(for: selectedPrompt))") {
                            Button("Uncategorized") {
                                viewModel.updatePromptLibraryPromptCategory(promptId: selectedPrompt.id, categoryId: nil)
                            }
                            ForEach(viewModel.promptLibraryCategories) { category in
                                Button(category.name) {
                                    viewModel.updatePromptLibraryPromptCategory(promptId: selectedPrompt.id, categoryId: category.id)
                                }
                            }
                        }

                        Button("Assign Tags") {
                            selectedPromptForTags = selectedPrompt
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            viewModel.deletePromptLibraryPrompt(promptId: selectedPrompt.id)
                            selectedPromptID = nil
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    let tags = viewModel.promptLibraryTagNames(for: selectedPrompt)
                    Text(tags.isEmpty ? "Tags: None" : "Tags: \(tags.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Prompt title", text: $newPromptTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Prompt body", text: $newPromptBody, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $newPromptCategoryID) {
                    Text("Uncategorized").tag(Optional<UUID>.none)
                    ForEach(viewModel.promptLibraryCategories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.menu)

                Button("Add Prompt") {
                    viewModel.createPromptLibraryPrompt(
                        title: newPromptTitle,
                        body: newPromptBody,
                        categoryId: newPromptCategoryID
                    )
                    newPromptTitle = ""
                    newPromptBody = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func categoryRow(title: String, id: UUID?, canDelete: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                viewModel.promptLibrarySelectedCategoryId = id
            } label: {
                HStack {
                    Text(title)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if viewModel.promptLibrarySelectedCategoryId == id {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(viewModel.promptLibrarySelectedCategoryId == id ? Color.cyan.opacity(0.2) : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if canDelete, let id, let category = viewModel.promptLibraryCategories.first(where: { $0.id == id }) {
                Button(role: .destructive) {
                    viewModel.deletePromptLibraryCategory(category)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct PromptTagAssignmentSheet: View {
    @ObservedObject var viewModel: PromptEngineViewModel
    let prompt: PromptLibraryItem

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTagIDs: Set<UUID>

    init(viewModel: PromptEngineViewModel, prompt: PromptLibraryItem) {
        self.viewModel = viewModel
        self.prompt = prompt
        _selectedTagIDs = State(initialValue: Set(prompt.tagIds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assign Tags")
                .font(.title3.weight(.semibold))
            Text(prompt.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.promptLibraryTags.isEmpty {
                Text("No tags available. Add a tag first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.promptLibraryTags) { tag in
                            Toggle(
                                tag.name,
                                isOn: Binding(
                                    get: { selectedTagIDs.contains(tag.id) },
                                    set: { enabled in
                                        if enabled {
                                            selectedTagIDs.insert(tag.id)
                                        } else {
                                            selectedTagIDs.remove(tag.id)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                Button("Save") {
                    viewModel.updatePromptLibraryPromptTags(promptId: prompt.id, tagIds: Array(selectedTagIDs))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 280)
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
                    .opacity(0.30)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.015))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func glassInset(cornerRadius: CGFloat = 8) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .opacity(0.30)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}
