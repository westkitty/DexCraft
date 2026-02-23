# Offline Prompt Research Notes (Development-Time)

Date: 2026-02-23  
Purpose: Document source-backed prompt behavior guidance translated into local, runtime-offline heuristics.

## Method
- Prioritized official vendor docs and model cards where available.
- Encoded only conservative, implementation-relevant guidance.
- Any quantitative profile score (1-5 reliability/bias) is a **heuristic**, not a vendor guarantee.

## Family-by-Family Inputs

### 1) OpenAI GPT-style (Chat/Tools/JSON)
- Sources:
  - https://platform.openai.com/docs/guides/structured-outputs
  - https://platform.openai.com/docs/guides/function-calling
  - https://platform.openai.com/docs/guides/text?api-mode=responses
- Runtime rule mapping:
  - Strong schema/tool guidance support -> higher JSON/tool reliability heuristic.
  - Keep system concise, make output contract explicit, prefer deterministic settings for structured tasks.

### 2) Anthropic Claude-style
- Sources:
  - https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags
  - https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/overview
  - https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/chain-of-thought
- Runtime rule mapping:
  - Explicit section delimiters/tags help consistency.
  - Tool-use should be explicitly gated by scenario reliability rules.

### 3) Google Gemini-style
- Sources:
  - https://ai.google.dev/gemini-api/docs/structured-output
  - https://ai.google.dev/gemini-api/docs/function-calling
  - https://ai.google.dev/gemini-api/docs/system-instructions
- Runtime rule mapping:
  - Use schema-first output contract for structured tasks.
  - Keep system instructions direct and scoped.

### 4) xAI Grok-style
- Sources:
  - https://docs.x.ai/docs/guides/structured-outputs
  - https://docs.x.ai/docs/guides/function-calling
  - https://docs.x.ai/docs/api-reference
- Runtime rule mapping:
  - Keep explicit JSON contract but include validation/repair fallback.
  - Treat tool reliability as moderate unless scenario can tolerate fallback plans.

### 5) Meta Llama-family (open-weight)
- Sources:
  - https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct
  - https://huggingface.co/docs/transformers/chat_templating
- Runtime rule mapping:
  - Chat template adherence matters for consistency.
  - Prefer short, explicit instruction blocks and delimiters.

### 6) Mistral-family (open + API)
- Sources:
  - https://docs.mistral.ai/capabilities/structured_output/
  - https://docs.mistral.ai/capabilities/function_calling/
  - https://docs.mistral.ai/guides/prompting_capabilities/
- Runtime rule mapping:
  - Structured output and function-calling are first-class; still enforce strict output contracts.

### 7) DeepSeek-family
- Sources:
  - https://api-docs.deepseek.com/
  - https://api-docs.deepseek.com/guides/function_calling
- Runtime rule mapping:
  - Use explicit format constraints and deterministic prompts.
  - Keep tool and strict-JSON behavior at moderate heuristic confidence.

### 8) Qwen-family
- Sources:
  - https://qwen.readthedocs.io/en/latest/
  - https://qwen.readthedocs.io/en/latest/getting_started/concepts.html
- Runtime rule mapping:
  - Compact prompts + clear delimiters improve output consistency.
  - Treat strict formatting reliability as moderate unless scenario includes repair logic.

### 9) Cohere Command/Rerank-family
- Sources:
  - https://docs.cohere.com/docs/prompting-command-r
  - https://docs.cohere.com/docs/rerank-overview
  - https://docs.cohere.com/docs/embeddings
- Runtime rule mapping:
  - Favor concise instruction style.
  - Highlight ranking/embedding-specific usage patterns in notes; keep output contracts explicit.

### 10) Local CLI Runtimes (Ollama / llama.cpp / generic local)
- Sources:
  - https://ollama.com/blog/structured-outputs
  - https://ollama.com/blog/tools-support
  - https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md
- Runtime rule mapping:
  - Short prompts, explicit steps, and low-creativity defaults.
  - Strict JSON/tool behavior can be brittle depending on runtime/model -> require fallback and warnings.

## Cross-Cutting Offline Rules
- JSON scenario:
  - High reliability families: strict JSON-only contract.
  - Lower reliability families: JSON-repair protocol and warning.
- Tool-using scenario:
  - High tool reliability families: explicit tool loop.
  - Lower tool reliability families: manual-step fallback (no tool-call syntax).
- CLI scenario:
  - Force command-forward, copy/paste runnable output constraints.
- Research scenario:
  - Require citations discipline and uncertainty marking.

## Implementation Note
- The app ships these as local Swift tables (`OfflinePromptKnowledgeBase`) and deterministic transformations (`OfflinePromptOptimizer`).
- No runtime network calls are needed for optimization decisions.
