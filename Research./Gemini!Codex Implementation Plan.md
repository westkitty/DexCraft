# **RESEARCH\_SYNTHESIS**

| Feature Dimension | Remote LLM Enhancement (Legacy) | Offline Heuristic Pipeline (OHPEE) |
| :---- | :---- | :---- |
| **Execution Environment** | Upstream remote API | Client-side Web Worker (TypeScript) |
| **Paradigm** | Probabilistic text generation | Deterministic AST compilation |
| **Latency** | Network-bound (high) | Synchronous / Zero-network (\<5ms) |
| **Output Structure** | Unbounded string / Nested wrappers | Strict JSON SpecObject |
| **Conflict Resolution** | Unpredictable (Prompt drift) | Mathematical topological sort (DAG) |
| **Scaling Cost** | O(Tokens) API pricing | O(Nodes) Local compute (Free) |

**Convergence List:**

* Both architectures attempt to isolate user intent from system constraints.  
* Both recognize the necessity of enforcing Nano Banana Pro coherence protocols.  
* Both target the transformation of ambiguous inputs into constraint-bound instructions.

**Conflict List:**

* The legacy system treats prompt engineering as a generative text task, resulting in scaffold inflation; the OHPEE treats it as a deterministic compilation target.  
* The legacy system wraps inputs in nested XML/Markdown without modifying the core payload; OHPEE mutates the core payload via AST patching and strips raw text wrappers.  
* The legacy system cannot guarantee byte-for-byte reproducibility; OHPEE enforces it via cryptographic hashing and pure functions.

**Ranked Implementation Shortlist:**

1. **Zero-Dependency TypeScript OHPEE (Selected):** Client-side Abstract Syntax Tree parsing, DAG rule application, and deterministic string compilation.  
2. **Hybrid Remote Schema Enforcement:** Upstream LLM constrained by strict JSON Schema (Rejected due to latency and token cost).  
3. **Legacy Template Injection:** Client-side regex wrapping (Rejected due to cosmetic superficiality).

# **EMPIRICAL\_CORPUS\_REPORT**

**Corpus Scope:** 20 records (8 Image, 4 Code, 4 Plan, 4 Writing) extracted from dexcraft\_batch\_outputs.json and history.json.

{  
  "CORPUS\_METRICS": {  
    "mean\_similarity": 0.042,  
    "median\_similarity": 0.040,  
    "worst\_case\_similarity": 0.018,  
    "mean\_structural\_delta": 15,  
    "mean\_constraint\_retention": 100,  
    "mean\_redundancy\_ratio": 24.6  
  }  
}

**Failure Type Distribution:**

* Scaffold Inflation: 20/20 (100%)  
* Template Echoing: 20/20 (100%)  
* Nested Wrapper Duplication: 20/20 (100%)  
* Cosmetic Rewrite (No Payload Transformation): 20/20 (100%)  
* Actionable Parameter Injection: 0/20 (0%)

**DEFINITION\_OF\_ENHANCEMENT:**

* MAX\_ALLOWED\_SIMILARITY: 0.85 (A valid enhancement must alter at least 15% of the payload string via heuristic injection, excluding wrappers).  
* MIN\_STRUCTURAL\_DELTA: 1 (The AST must register at least one new semantic node, e.g., BBOX\_DEF, ENVIRONMENT, or CONSTRAINT).  
* REQUIRED\_CONSTRAINT\_RETENTION: 100 (Zero user-defined directives may be dropped).  
* REDUNDANCY\_IMPROVEMENT\_REQUIRED: Total output token length must be ![][image1] 3.0x the input token length, strictly prohibiting boilerplate inflation.

# **SYSTEM\_GROUNDING**

* **Template Recursion Depth (Depth \= 2):** Artifact dexcraft\_batch\_outputs.json proves inputs are wrapped in a Markdown template (\#\#\# Scenario, \#\#\# Output Contract), which itself nests an XML template (\<Legacy Canonical Draft\>, \<objective\>, \<context\>).  
* **Preamble Duplication Frequency (100%):** Artifact history.json and dexcraft\_batch\_outputs.json show identical text (You are an execution-focused assistant...) injected into every single record regardless of the task domain (Image, Code, Plan, Writing).  
* **Scaffold Reuse Pattern:** Artifact templates.json dictates strict 4-heading structures. The enhancement engine blindly injects user input into the \[Goal\] or \[Context\] fields rather than extracting and manipulating the parameters.  
* **Evidence of Nested Wrapping:** Artifact dexcraft\_batch\_outputs.json (ID: IMG-001) takes a 12-word input ("Make an album cover...") and outputs a 348-word response where the original string is simply echoed untouched on line 15 and line 47\.  
* **OHPEE Integration State:** Artifact Offline Prompt Enhancement Design.txt fully specifies a functional AST pipeline, but local execution artifacts prove the application is still defaulting to the REMOTE\_LLM routing logic, bypassing the deterministic engine entirely.

# **ARCHITECTURE\_SPEC**

**A. Internal Representation**

A strictly typed Abstract Syntax Tree (AST) representing ParsedPrompt. Node types: ROOT, SCENE, SUBJECT, ACTION, ENVIRONMENT, CONSTRAINT, BBOX\_DEF, REF\_DEF.

**B. Constraint Lock Enforcement**

A Directed Acyclic Graph (DAG) Rule Engine utilizing Kahn's Algorithm. Conflicts are resolved via numeric precedence: System Invariants (Critical) \> Hard Constraints (High) \> Scenario Defaults (Medium) \> Soft Preferences (Low). Tie-breaker: Topological depth, then lexical sort.

**C. Similarity Guard Logic**

function calculateSimilarityGuard(input: string, compiledOutput: string): number {  
  const distance \= levenshtein(input, compiledOutput);  
  const maxLength \= Math.max(input.length, compiledOutput.length);  
  return (maxLength \- distance) / maxLength;  
}  
// MUST throw if return \> MAX\_ALLOWED\_SIMILARITY

**D. Redundancy Compression Rule**

All meta-text, conversational framing, and system preambles (e.g., "\#\#\# System Preamble", "\<objective\>") are stripped during the Compiler phase. Only nodes attached to the semantic AST are stringified.

**E. Template Normalization Rule**

Legacy XML tags and Markdown boundaries are identified during the Lexer phase and flattened into AST properties. They are not carried over into the final compiled text.

**F. Deterministic Hash Generation**

deterministicHash \= SHA-256(rawInput \+ JSON.stringify(activeRuleHashes) \+ JSON.stringify(generationParameters))

Utilized as the primary key for the IndexedDB SpecObject audit record.

**G. Rewrite Intensity Modes**

* LOW: Resolves BBOX and REF indices only.  
* MEDIUM: Injects default scenario lighting/environment variables.  
* HIGH: Executes full semantic expansion and subjective disambiguation.

**H. Superficial Rewrite Rejection Function**

function rejectIfSuperficial(input: string, output: string, ast: ParsedPrompt): boolean {  
  const inputTokens \= tokenize(input).length;  
  const outputTokens \= tokenize(output).length;  
  const redundancyRatio \= outputTokens / Math.max(inputTokens, 1);  
    
  if (redundancyRatio \> 3.0) return true;  
    
  const heuristicAdditions \= ast.children.filter(n \=\> n.provenance \=== 'HEURISTIC\_DERIVATION').length;  
  if (heuristicAdditions \< 1\) return true;  
    
  const similarity \= calculateSimilarityGuard(input, output);  
  if (similarity \> 0.85) return true;

  return false;  
}

**I. Failure Return Behavior**

If rejectIfSuperficial returns true, the pipeline aborts the transformation, dumps a deterministic error trace to the local audit log, and returns the strictly normalized, original raw input to prevent network failure.

# **EVALUATION\_HARNESS\_SPEC**

* **JSON Corpus Schema:** { "id": string, "raw\_input": string, "expected\_nodes": string\[\], "max\_redundancy": number }  
* **Execution Flow:** 1\. Ingest test\_corpus.json. 2\. Pass to Lexer. 3\. Build AST. 4\. Execute topological DAG rule sort. 5\. Compile to string. 6\. Execute rejectIfSuperficial(). 7\. Generate SpecObject.  
* **Metric Computation:** Calculate Redundancy Ratio, Heuristic Node Delta, and Levenshtein Similarity per corpus item.  
* **Pass/Fail Report Format:** \[PASS/FAIL\] | ID: \<id\> | Delta: \<ast\_delta\> | Ratio: \<redundancy\_ratio\> | Sim: \<similarity\>  
* **Local Execution Instructions:**  
  npx tsx src/features/prompt-enhancement/tests/harness.ts \--corpus=dexcraft\_batch\_inputs.json \--strict  
* **Deterministic Output Example:**  
  {  
    "originalPrompt": "cat astronaut on mars",  
    "enhancedPrompt": "Photorealistic cat astronaut walking on the surface of Mars. Professional cinematic lighting, balanced contrast, 85mm lens.",  
    "deterministicHash": "8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92",  
    "generationParameters": { "aspectRatio": "16:9", "resolution": "2K", "referenceImages": \[\] },  
    "spatialConstraints": \[\],  
    "auditTrail": \[{ "ruleId": "HEU\_AMBIGUITY\_REDUCT", "actionTaken": "Injected scenario default lighting and lens parameters." }\]  
  }

# **VALIDATION\_GATE\_CHECK**

1. **Does this architecture prevent append-only inflation?** YES. The Redundancy Compression Rule strips non-semantic text, and the rejection function caps redundancy at 3.0x.  
2. **Can it detect cosmetic rewrite?** YES. The calculateSimilarityGuard strictly limits textual stagnation (MAX\_ALLOWED\_SIMILARITY ![][image1] 0.85).  
3. **Are numeric thresholds enforced?** YES. Enforced directly within the rejectIfSuperficial gate logic before final compilation.  
4. **Is regression measurable?** YES. Regression is caught by Golden Fixture snapshot tests against the deterministic SHA-256 hash in the SpecObject.  
5. **Are file boundaries respected?** YES. The architecture is isolated entirely within /src/features/prompt-enhancement/ as pure TS functions, preventing contamination of the legacy React service layer.

# **FINAL\_CODEX\_PROMPT**

\#\#\# Scenario  
IDE Coding Assistant (macOS)

\#\#\# Task  
Implement the Offline Heuristic Prompt Enhancement Engine (OHPEE) for DexCraft to replace the failing probabilistic LLM enhancement pipeline. 

Context: The current implementation suffers from 100% scaffold inflation (Mean Redundancy Ratio: 24.6) and zero actionable payload transformation. Inputs are being redundantly wrapped in nested XML/Markdown templates without structural enhancement.

You must build a purely functional, synchronous TypeScript pipeline inside \`/src/features/prompt-enhancement/\`.

\#\#\# Output Contract  
\- Output sections in this order: Plan, Unified Diff, Tests, Validation Commands.  
\- Prefer minimal diff footprint and deterministic file paths.  
\- Write or update tests before final patch summary when feasible.

\#\#\# Required Architecture Specs  
1\. AST Definitions: Create \`/src/features/prompt-enhancement/types/ast.ts\`. Define types for \`ROOT\`, \`SCENE\`, \`SUBJECT\`, \`ACTION\`, \`ENVIRONMENT\`, \`CONSTRAINT\`, \`BBOX\_DEF\`, \`REF\_DEF\`. Define the \`SpecObject\` interface.  
2\. Pipeline: Create \`/src/features/prompt-enhancement/ast/Lexer.ts\` and \`Parser.ts\`. Must strip all legacy XML (\`\<objective\>\`, \`\<context\>\`) and Markdown preambles entirely.  
3\. Rule Engine: Create \`/src/features/prompt-enhancement/rules/RuleEngine.ts\`. Implement a Directed Acyclic Graph (DAG) using Kahn's algorithm for rule dependencies.  
4\. Compilation & Rejection: Create \`/src/features/prompt-enhancement/compiler/Stringifier.ts\`. You MUST implement the following specific rejection logic:

\`\`\`typescript  
export function rejectIfSuperficial(input: string, output: string, ast: ParsedPrompt): boolean {  
  const inputTokens \= input.split(/\\s+/).length;  
  const outputTokens \= output.split(/\\s+/).length;  
  const redundancyRatio \= outputTokens / Math.max(inputTokens, 1);  
  if (redundancyRatio \> 3.0) return true;  
    
  const heuristicAdditions \= ast.children.filter(n \=\> n.provenance \=== 'HEURISTIC\_DERIVATION').length;  
  if (heuristicAdditions \< 1\) return true;  
    
  const distance \= levenshtein(input, output); // Assume fast-levenshtein import  
  const similarity \= (Math.max(input.length, output.length) \- distance) / Math.max(input.length, output.length);  
  if (similarity \> 0.85) return true;

  return false;  
}

5. Service Integration: Modify /src/services/gemini/GeminiService.ts to implement the Strategy Design Pattern. Intercept settings.enhancementMode \=== 'OFFLINE\_HEURISTIC' to route to OHPEE instead of the remote LLM.

### **Non-Negotiable Constraints**

* DO NOT use probabilistic LLM calls in this pipeline.  
* DO NOT allow superficial rewrites to pass.  
* DO NOT use external dependencies for the DAG sort. Write pure functions.  
* DO NOT embed any conversational or therapy-language feedback in the audit log.  
* MUST calculate a deterministic SHA-256 hash for the final SpecObject.

### **Definition of Done**

* TypeScript compilation passes strictly.  
* Unit tests for rejectIfSuperficial prove it rejects inputs with \> 3.0 redundancy ratio and \> 0.85 similarity.  
* GeminiService.ts correctly routes offline enhancement requests synchronously.

### **Validation Commands**

npx tsc \--noEmit  
npx vitest run src/features/prompt-enhancement/  


[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA8AAAAXCAYAAADUUxW8AAABUElEQVR4XqVTPU/DMBB1JAYWBoaKpb27NCmVkJgY2NgZ+QH8ADYGtg5ITDAxVWLgx3LfsSOm5qrn+OL3ns8Xt3SllIAMnU4iOs0DRohHqpJqv8ok3yWn2myhuFJXJE/b+XxRtQ575GQiKDxvXOo8nLLuIJUy7sYVALwj4JNgubg9pbfGdcMwbHqiTwERfW23W8jFkOUePKzXmx0gfCsAP1h4JYiK2u6b4FYAiEcWHFh4KXBvi3Cf5yeLpS9E/asAEX/Z4KYhzJM4Y9btsb/eXyDCG5scBdzdu1zMK9c5LMv1k8RZiQ890bmAP88Ln/1HQH3/oHwnd3kXPLKScLP8TMAGz25yL3Bq++X0nXxPhTFqp3EcVwLlLxLX4W6iVlRTH6bcfHkkbowAQa6kX00H/wkqaP4o0Ib5fvMiLHw3T/5p7hLxJLXF6dw1LfeZMib/AaaANGaIWBGRAAAAAElFTkSuQmCC>