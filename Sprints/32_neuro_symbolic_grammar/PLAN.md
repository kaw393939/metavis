# Sprint 32: Neuro-Symbolic Grammar (GBNF)

## Goal
Eliminate "Hallucinated JSON" errors by upgrading the Local LLM integration to use GBNF (Grammar-Based Normalization Form) constraints, ensuring that the AI can *only* emit valid `IntentCommands`.

## Rationale
The current `LocalLLMService` uses a mock regex or simple prompt. Real LLMs often chatter or output broken JSON. By forcing the model's logits to conform to a GBNF grammar derived from our Swift `Codable` structs, we guarantee execution safety.

## Deliverables
## Deliverables
1.  **`IntentCommand` Schema:** Export the `AgentAction` enum (defined in **Sprint 25**) to a JSON Schema or GBNF grammar definition. The schema must be the canonical representation of the Swift type.
2.  **`LocalCreatorDevice`:** A valid implementation of `VirtualDevice` (from the HAL) that wraps a local model (Llama-3/Mistral).
    *   *Optimization:* Must use `CoreML` with **Int8 Quantization** to run efficiently on the **Neural Engine (ANE)**.
    *   *Memory:* Use `IOSurface` for KV-Cache to prevent CPU-GPU copy overhead.
3.  **Grammar Enforcer:** A mechanism (or simulation of one) that rejects tokens which do not fit the grammar.
4.  **Test:** `NeuroSymbolicReliabilityTests` which fuzz the input prompt but assert 100% valid JSON output.

## Out of Scope
- Training the model. We are strictly building the *inference harness* / constraint engine.
