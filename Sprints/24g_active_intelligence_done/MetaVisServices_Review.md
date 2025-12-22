# MetaVisServices Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisServices`

## 1. Executive Summary

`MetaVisServices` is the gateway for AI and cloud integrations. It currently houses two primary subsystems: a production-ready **Google Gemini** integration and a prototype **Local LLM** service.

**Strengths:**
- **Robust Gemini Client:** The `GeminiClient` is well-implemented with retry logic for model resolution (handling 404s/400s) and fallback encoding (snake_case vs camelCase).
- **Environment Handling:** `GeminiConfig` safely handles API keys, stripping whitespace and supporting multiple variable names (`GEMINI_API_KEY`, `GOOGLE_API_KEY`).
- **Device Abstraction:** `GeminiDevice` correctly wraps the client as a `VirtualDevice`, integrating the cloud service into the engine's node graph.

**Critical Gaps:**
- **Fake Local LLM:** `LocalLLMService` entirely mocked. It uses hardcoded string matching (e.g., `if q.contains("ripple")`) and simulated `Task.sleep` to mimic an AI. It does not load or run any CoreML models.
- **Limited Device Actions:** The `GeminiDevice` only exposes an `ask_expert` action that accepts text. It does not currently expose actions to send images or video frames to Gemini, efficiently limiting it to text-only interactions within the engine graph, despite the underlying client supporting multimodal payloads.

---

## 2. Detailed Findings

### 2.1 Gemini Integration (`Gemini/`)
- **Client:** `GeminiClient` is a Sendable struct using `URLSession`. It implements a smart "model resolution" heuristic, scoring models by keywords like "gemini", "flash", "pro" if the configured model is unavailable.
- **Config:** Reads from environment variables. Defaults model to `gemini-2.5-flash`.
- **Concurrency:** Fully async/await.

### 2.2 Local LLM (`LocalLLMService.swift`)
- **Mock Implementation:** The `generate(request:)` method checks for keywords like "ripple", "cut", "speed", "blue" and returns pre-canned JSON responses.
- **Intent Parsing:** `IntentParser` extracts JSON from markdown fences.
- **Use Case:** This appears to be a stub for the "Jarvis" or "Studio Mode" natural language interface.

### 2.3 User Intents (`UserIntent.swift`)
- Defines a strong schema for editorial intents (`cut`, `trim_in`, `color_grade`, `speed`). This schema is good, but the "intelligence" producing it is currently fake.

---

## 3. Recommendations

1.  **Implement Real Local LLM:** Replace the mock logic in `LocalLLMService` with a real `LanguageModel` integration (e.g., using `CoreML` or a connection to `Ollama`).
2.  **Enable Multimodal Device Actions:** Update `GeminiDevice` to accept byte buffers or file paths in its `ask_expert` action (or a new `analyze_media` action) so the engine can pipe video frames to it.
3.  **Standardize Intent Format:** Ensure the `UserIntent` JSON schema is synchronized with the system prompt of the real LLM once implemented.
