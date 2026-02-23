# DexCraft Prompting Playbooks (Offline)

This file documents the deterministic prompt wrappers used by DexCraft at runtime.

## Claude (Anthropic)
- Wrapper style: XML tags.
- Core tags: `<objective>`, `<context>`, `<requirements>`, `<constraints>`, `<deliverables>`.
- Notes: keep boundaries explicit and list sections as bullets.

Example:
```xml
<objective>Implement deterministic prompt restructuring.</objective>
<context>DexCraft is offline-only at runtime.</context>
<requirements>
- Add a restructuring engine.
</requirements>
```

## Gemini / ChatGPT
- Wrapper style: Markdown headings.
- Core sections: `### Goal`, `### Context`, `### Requirements`, `### Constraints`, `### Deliverables`.
- Notes: concise markdown, deterministic ordering.

Example:
```markdown
### Goal
Restructure run-on dictation into implementable prompt sections.

### Requirements
- Split mixed paragraphs into normalized bullets.
```

## Perplexity
- Wrapper style: Markdown headings plus required verification block.
- Core sections: Goal/Context/Requirements/Constraints/Deliverables.
- Required block: `### Search & Verification Requirements` with explicit citation expectations.

Example:
```markdown
### Search & Verification Requirements
- Cite sources inline as markdown links for factual claims.
```

## Agentic IDE (Cursor/Windsurf/Copilot)
- Wrapper style: Markdown scaffold for implementation workflows.
- Core sections: Goal/Context/Requirements/Constraints/Deliverables.
- Required scaffold: Plan, Unified Diff, Tests, Validation, Build/Run Commands, Git/Revert Plan.

Example:
```markdown
### Plan
- Implement minimal deterministic changes first.

### Tests
- Add regression tests for restructuring buckets.
```
