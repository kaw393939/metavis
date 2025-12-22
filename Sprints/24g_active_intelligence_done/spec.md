# Sprint 24g: Active Intelligence - Specification

**Goal:** Give the engine a real brain.

## Objectives

1.  **Real Local LLM Integration (Priority P0)**
    *   **Problem:** `LocalLLMService` is currently a mock with `sleep(0.5)`.
    *   **Requirement:** Replace the current mock behavior with a protocol-based `LLMProvider` abstraction and a deterministic provider suitable for tests.
    *   **Optional:** Provide an integration path for a real on-device model when/if weights are available, without making the core system depend on large bundled assets.
    *   **Success Metric:** `processCommand` returns valid intent JSON from an actual provider implementation (deterministic in tests), not hardcoded regex.

2.  **Multimodal Gemini Support (Priority P1)**
    *   **Problem:** `GeminiDevice` claims to be multimodal but `ask_expert` only accepts text.
    *   **Requirement:** Update public API to accept `imageData` (JPEG/PNG). Update `GeminiClient` to expose multipart generation.
    *   **Success Metric:** Interpreting a frame and asking "What color is the shirt?" returns the correct color from the Cloud API.

3.  **Session Responsiveness (Priority P2)**
    *   **Problem:** `ProjectSession` does not cancel stale LLM requests.
    *   **Requirement:** Implement `Task` tracking and cancellation in `processCommand`.
    *   **Success Metric:** Rapidly typing 5 queries results in only the final query completing; intermediate ones are cancelled.

4.  **Secure Configuration (Priority P3)**
    *   **Carryover from hardening:** Refactor `GeminiConfig` and `EntitlementManager` to be robust and secure.
    *   **Requirement:** Remove `UNLOCK_PRO_2025` backdoor. Use a TokenBucket-style limiter for API limits.
    *   **Success Metric:** API keys are stored securely, and rate limits are enforced without hardcoded values.

5.  **Deterministic AI Context (Priority P3)**
    *   **Problem:** `ProjectSession.analyzeFrame` uses `Date()` (wall clock) for throttling, making AI behavior non-deterministic during tests.
    *   **Requirement:** Use `simulationTime` for throttling and context timestamps.
    *   **Success Metric:** AI suggestions are identical across multiple runs of the same "God Test" recipe.

6.  **Formalized Intent Schema (Priority P3)**
    *   **Problem:** `UserIntent` schema is ad-hoc and not synchronized with the LLM system prompt.
    *   **Requirement:** Define a strict schema description for intents. Embed this schema in the System Prompt. Validate LLM output against it.
    *   **Success Metric:** `processCommand` throws precise schema validation errors if the LLM hallucinates an invalid action.

## Notes on Current Implementation
- Entitlements: unlock behavior is driven by an injected verifier (default denies). There is no hardcoded unlock code.
- Gemini rate limiting: optional token bucket configured via `GEMINI_RATE_LIMIT_RPS` and `GEMINI_RATE_LIMIT_BURST`.
