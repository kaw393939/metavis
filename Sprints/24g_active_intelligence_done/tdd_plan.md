# Sprint 24g: TDD Plan

## 1. Unit Tests

### `MetaVisServicesTests`
*   **`testMultimodalPayloadConstruction`**:
    *   **Action:** Call `GeminiClient.generateContent` with image data.
    *   **Assert:** Request body contains correct Base64 `inlineData`.
*   **`testLLMCancellation`**:
    *   **Action:** Fire request A (slow), immediately fire request B.
    *   **Assert:** Request A throws CancellationError or returns nil; Request B completes.

### `MetaVisSessionTests`
*   **`testSessionCommandCancellation`**:
    *   **Setup:** Use `MockLLMService` with delayed response.
    *   **Action:** Call `processCommand("foo")`, then `processCommand("bar")`.
    *   **Assert:** "foo" is cancelled; "bar" returns result.
*   **`testVisualContextInjection`**:
    *   **Setup:** `state.visualContext` has "One Person".
    *   **Action:** `processCommand`.
    *   **Assert:** LLM Request Context JSON contains `visualContext`.

## 2. Integration Tests

### `MetaVisLab Gemini`
*   **`testMultimodalAnalysis`**:
    *   **Action:** Run `metavislab gemini-analyze --input cat.jpg --prompt "What animal?"`.
    *   **Assert:** Output contains "Cat". (Requires networked test or robust Mock of the internal HTTP client, but validates the plumbing).

## 3. Performance Tests
*   **`testInferenceLatency`**:
    *   Measure wall clock time for 100 simple prompts on ANE (Apple Neural Engine).
    *   Target: < 200ms per prompt.
