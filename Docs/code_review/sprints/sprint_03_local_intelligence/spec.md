# Sprint 03: Local Intelligence Integration

## 1. Objective
Replace the `LocalLLMService` mock in `MetaVisServices` with a real binding to a local Quantized LLM (e.g. Llama-3-8B) using `MLX` or `CoreML`. Implement RAG (Retrieval Augmented Generation) to handle timeline context scaling.

## 2. Scope
*   **Target Modules**: `MetaVisServices`
*   **Key Files**: `LocalLLMService.swift`, `LLMEditingContext.swift`, `IntentParser.swift`

## 3. Acceptance Criteria
1.  **Real Inference**: `LocalLLMService.generate()` must return non-deterministic, semantically correct responses for complex prompts (e.g. "Make the clip that looks sad appear later").
2.  **Context Scaling**: Support prompts referencing a timeline with 500 clips via Vector Search / Embedding filtering.
3.  **Performance**: Latency < 2s for standard prompts on M2 hardware.

## 4. Implementation Strategy
*   Import `MLX` (or `CoreML` backing).
*   Add `EmbeddingService` to encode `ClipSummary` text descriptions.
*   Update `LocalLLMService` to: 1) Embed User Query, 2) Search Clips, 3) Construct Prompt, 4) Infer.

## 5. Artifacts
*   [Architecture](./architecture.md)
*   [TDD Plan](./tdd_plan.md)
