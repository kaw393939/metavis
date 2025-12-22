# Sprint 24g: Active Intelligence - Implementation Plan

## Goal Description
Give the engine a real brain. We will replace the mock "Active Intelligence" layer with a real on-device LLM (or a highly capable structured fallback), enable multimodal (vision) queries via Gemini, and harden the session management for responsiveness and security.

## User Review Required
> [!IMPORTANT]
> **New Dependency:** This sprint may introduce optional model-runner dependencies and/or model weights.
> **Breaking Change:** `GeminiDevice.perform` signature change to support binary payloads.

## Proposed Changes

### MetaVisServices
#### [MODIFY] [Sources/MetaVisServices/LocalLLMService.swift](../../Sources/MetaVisServices/LocalLLMService.swift)
- **Implement** `LLMProvider` protocol.
- **Integrate** a real model runner (e.g. `MLXLLMService` if on macOS 14+, or `CoreMLLLMService`).
    - *Fallback:* If weights are missing, implement a `RuleBasedLLMService` that is much more sophisticated than the current mock (fuzzy matching, proper tokenization).
- **Hardening:** Ensure thread safety during inference.

#### [MODIFY] [Sources/MetaVisServices/Gemini/GeminiDevice.swift](../../Sources/MetaVisServices/Gemini/GeminiDevice.swift)
- Update `ask_expert` to accept optional `imageData` (JPEG/PNG) and `imageMimeType`.
- Update `perform` to extract `imageData` from parameters and call `GeminiClient` accordingly.

#### [MODIFY] [Sources/MetaVisServices/Gemini/GeminiClient.swift](../../Sources/MetaVisServices/Gemini/GeminiClient.swift)
- Ensure `generateContent` exposes the existing multipart support publically (it currently exists internally but might be private).

### MetaVisSession
#### [MODIFY] [Sources/MetaVisSession/ProjectSession.swift](../../Sources/MetaVisSession/ProjectSession.swift)
- **Cancellation:** In `processCommand`, maintain a reference to the current `Task`. Cancel it if a new command arrives before completion.
- **Determinism:** Update `analyzeFrame(pixelBuffer:time:)` to use the `time` argument for throttling decisions, not `Date()`.

#### [MODIFY] [Sources/MetaVisSession/EntitlementManager.swift](../../Sources/MetaVisSession/EntitlementManager.swift)
- Remove `UNLOCK_PRO_2025` hardcode.
- Use an injected unlock verifier closure so production can plug in a signed-token verifier later.

### MetaVisServices (Hardening)
#### [ADD] [Sources/MetaVisServices/TokenBucket.swift](../../Sources/MetaVisServices/TokenBucket.swift)
- Token bucket limiter used for optional Gemini API rate limiting.
- Configured via `GEMINI_RATE_LIMIT_RPS` and `GEMINI_RATE_LIMIT_BURST`.

## Verification Plan

### Automated Tests
1.  **Multimodal Payload:**
    - Unit test `GeminiDevice.perform` with a dummy Base64 image. Assert `GeminiClient` received the `.inlineData` case.
2.  **Session Cancellation:**
    - Unit test `ProjectSession`: Call `processCommand` twice rapidly. Assert first task is cancelled.
3.  **Schema Validation:**
    - Unit test `IntentParser` with invalid JSON. Assert it throws a specific validation error.

### Manual Verification
1.  **Visual QA:**
    - Open `MetaVisLab`.
    - Run `lab gemini-analyze --image test_frame.jpg "What color is this?"`.
    - Verify correct response from cloud.
2.  **Responsiveness:**
    - Type fast in the CLI/REPL. Verify "Thinking..." states don't stack up.
