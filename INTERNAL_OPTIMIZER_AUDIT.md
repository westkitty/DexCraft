# DexCraft Offline Optimizer Audit (Internal Scratchpad)

Date: 2026-02-23

## Repo Audit Findings
- Prompt input entry point: `DexCraft/Views/PrimaryPanelView.swift` via `TransparentTextEditor` bound to `PromptEngineViewModel.roughInput`.
- Model/provider-ish selection currently present: `PromptTarget` (`Claude`, `Gemini/ChatGPT`, `Perplexity`, `Agentic IDE`) in `DexCraft/Models/PromptTarget.swift`, selected in `PrimaryPanelView.targetPicker`.
- Prompt pipeline: `PromptEngineViewModel.forgePrompt()` in `DexCraft/ViewModels/PromptEngineViewModel.swift`.
- Parsing/template logic:
  - section parsing: `parseInputSections`
  - canonical merge/rules: `buildCanonicalPrompt`
  - target rendering: `renderPrompt`, `renderClaudePrompt`, `renderCanonicalMarkdown`
- Existing options/constraints: `DexCraft/Models/EnhancementOptions.swift`.
- Output panel and copy/export actions: `DexCraft/Views/ResultPanelView.swift`, `PromptEngineViewModel.copyToClipboard`, `exportForIDE`.
- Persistence:
  - templates: `templates.json` via `StorageManager`
  - history: `history.json` via `StorageManager`
  - models: `PromptTemplate`, `PromptHistoryEntry`

## Clean Insertion Point
- Best insertion point is inside `PromptEngineViewModel.forgePrompt()` after variable substitution and canonical prompt construction.
- Reason:
  - keeps existing deterministic parsing/rendering pipeline available (no regression for current users),
  - exposes one central place to branch between legacy formatting and new offline model/scenario optimizer,
  - minimizes UI churn by reusing existing `generatedPrompt` preview and copy/export flow.

## Integration Decisions
- Keep legacy `PromptTarget` behavior intact.
- Add offline optimization layer with:
  - `ModelFamily` (10 required families, including Grok + Local CLI Runtime),
  - `ScenarioProfile` (IDE, CLI, JSON, Longform, Research, Tool Agent),
  - deterministic optimizer (`OfflinePromptOptimizer`) returning applied rules/warnings for transparency.
- UI extension:
  - add two menu pickers (model family + scenario),
  - add `Auto-optimize prompt` toggle,
  - show optimizer metadata and suggested params in result panel,
  - add `.md` export.
